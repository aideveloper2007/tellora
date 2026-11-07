"""Screenshot to store design: rebuilds a store's home page from screenshots the owner uploads.

Flow (POST /api/v1/screenshot-design):
  1. The desktop screenshot (and an optional mobile one) is cut into slices for Claude (vision).
  2. Claude writes the page as HTML + CSS: header, main content and footer, with the exact
     texts, colours, sizes and spacing it sees. Photos and the logo are cut out of the
     screenshot itself (Claude gives their position), so they are the owner's real images.
  3. The page is rendered in a real browser (Chromium via Playwright) at the screenshot's
     width, photographed, and compared with the original. Claude gets the regions that
     differ most and corrects the code. This repeats until the match is high enough.
  4. The best version is returned with its match score.

The product grid is a template: Tellora fills it with the store's real products.
No JavaScript is kept and all CSS is scoped under .tm-root, so the design cannot
break the rest of the store.
"""

import asyncio
import base64
import io
import json
import logging
import re
from typing import Any, Dict, List, Optional, Tuple

from PIL import Image, ImageChops, ImageOps, ImageStat

from app.services.claude_llm import get_claude_llm, _response_text

logger = logging.getLogger(__name__)

SLICE_CSS_HEIGHT = 1400      # CSS pixels of page per slice sent to Claude
CLAUDE_SLICE_WIDTH = 1000    # slices are resized to this width for Claude
MAX_SLICES = 14
MAX_PASSES = 4               # first build + up to 3 corrections
TARGET_SCORE = 0.97
BAND_CSS_HEIGHT = 300        # compare the page in horizontal bands of this height
MAX_TOKENS = 32000

# Same base as the storefront (MirrorDesign::RESET in Rails): browser defaults inside .tm-root
RESET = (".tm-root{all:revert;display:block;font:initial;color:initial;line-height:normal;letter-spacing:normal;"
         "word-spacing:normal;text-align:start;text-transform:none}"
         ".tm-root *:where(:not(svg, svg *)){all:revert}")

PARTS = ("header_html", "main_html", "footer_html", "css", "page_bg", "images", "fonts", "products", "description")

RULES = """
Output EXACTLY these tagged parts, nothing before or after them:
<header_html>...</header_html>      the site's announcement bar + header/navigation
<main_html>...</main_html>          everything between the header and the footer
<footer_html>...</footer_html>      the footer
<css>...</css>                      all CSS
<page_bg>#rrggbb</page_bg>          the page background colour
<images>[...]</images>              JSON list of photos/logos to cut from the screenshot
<fonts>[...]</fonts>                JSON list of Google Font family names used, e.g. ["Cormorant Garamond", "Montserrat"]
<products>[...]</products>          JSON list of the products visible in the product grid
<description>...</description>      one sentence: what the shop sells, in the site's language

Rules for an exact copy:
- Copy every text EXACTLY as written (same language, accents, capitals, punctuation).
- Match colours, font sizes, font weights, letter spacing, line heights, widths, heights, paddings,
  margins, borders, border radius, shadows and alignment as precisely as you can measure them.
  Desktop width of the page is {viewport}px. Measure sizes in CSS pixels of that width.
- Choose the closest Google Fonts for the fonts you see (serif vs sans, weight, width).
- The page is assembled as three blocks: <div class="tm-root tm-header">header_html</div>,
  <div class="tm-root tm-main">main_html</div>, <div class="tm-root tm-footer">footer_html</div>.
  Inside them every element starts from the browser's default styles (Times New Roman 16px, default margins),
  so set fonts, margins, paddings, list styles and image sizes explicitly.
- Every CSS rule MUST start with .tm-root (e.g. ".tm-root .hero h1 {{...}}"). No rules for html, body or *.
  Do not use @import. You may use @media and @keyframes.
- No JavaScript, no <script>, no inline event handlers, no <iframe>, no <form> elements (use <div> and <a>).
- Icons (search, account, cart, truck, phone, ...): draw them as inline <svg> with simple paths.
- Photos, product photos, logos and any image area: <img src="tellora-image:ID" alt="..."> or a CSS
  background "url(tellora-image:ID)". Every ID must appear in <images>.
  <images> entries: {{"id": "hero", "slice": 0, "box": [x, y, width, height]}} where slice is the index of
  the screenshot slice (0 = first image given) and box is in that slice image's pixels. Boxes must
  contain ONLY the image area, tight, with no text drawn on top of it if the text is real HTML text.
  Text that is painted inside a photo stays in the photo.
- Links: logo -> "/", cart icon -> "/cart", account icon -> "/account", search icon -> "/products",
  every shop / collection / category / "discover" / "explore" link -> "/products", anything else -> "#".
- The product grid: write ONE container <div data-tellora-products="N"> (N = number of products shown),
  styled exactly like the screenshot's grid, containing ONLY one <template data-tellora-card>...</template>
  with the card markup. In the card use these placeholders: {{{{name}}}}, {{{{price}}}}, {{{{compare_price}}}},
  {{{{sale_label}}}}, {{{{image}}}} (an image URL: <img src="{{{{image}}}}">) and {{{{url}}}} (product link,
  also use it for an "Add to cart" button). compare_price and sale_label are empty when a product is
  not on sale: put each in its own element and add CSS so that element is hidden when :empty.
  <products> entries: {{"name": "...", "price": "...", "compare_price": "" or "...", "sale_label": "" or "...",
  "image_id": "product1"}} (with image_id listed in <images>).
- If a mobile screenshot is given, add an @media (max-width: 768px) block that matches it.
""".strip()


# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

def _open(data: bytes) -> Image.Image:
    image = Image.open(io.BytesIO(data))
    image = ImageOps.exif_transpose(image)
    return image.convert("RGB")


def _viewport(image: Image.Image) -> Tuple[int, float]:
    """CSS width of the page and the device pixel ratio of the screenshot."""
    width = image.width
    if width > 2000:              # retina screenshot (2x)
        return round(width / 2), width / round(width / 2)
    return width, 1.0


def _jpeg_b64(image: Image.Image, quality: int = 82) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=quality)
    return base64.b64encode(buffer.getvalue()).decode()


def _slices(image: Image.Image, dpr: float, target_width: int) -> List[Dict[str, Any]]:
    """Cut a full-page screenshot into slices. Each slice keeps its scale back to the original."""
    step = int(SLICE_CSS_HEIGHT * dpr)
    slices = []
    for index, top in enumerate(range(0, image.height, step)):
        if index >= MAX_SLICES:
            break
        part = image.crop((0, top, image.width, min(image.height, top + step)))
        scale = target_width / part.width
        resized = part.resize((target_width, max(1, round(part.height * scale))), Image.LANCZOS)
        slices.append({"top": top, "scale": scale, "image": resized})
    return slices


def _image_block(image: Image.Image) -> Dict[str, Any]:
    return {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": _jpeg_b64(image)}}


def _cut_images(original: Image.Image, slices: List[Dict[str, Any]], entries: List[Dict[str, Any]]) -> Dict[str, Dict[str, str]]:
    """Cut every requested image out of the full-resolution screenshot."""
    out: Dict[str, Dict[str, str]] = {}
    for entry in entries or []:
        try:
            ident = re.sub(r"[^a-zA-Z0-9_-]", "", str(entry["id"]))[:40]
            part = slices[int(entry.get("slice", 0))]
            x, y, w, h = [float(v) for v in entry["box"]]
        except (KeyError, ValueError, TypeError, IndexError):
            continue
        if not ident or w < 4 or h < 4:
            continue
        scale = part["scale"]
        box = (round(x / scale), round(part["top"] + y / scale), round((x + w) / scale), round(part["top"] + (y + h) / scale))
        box = (max(0, box[0]), max(0, box[1]), min(original.width, box[2]), min(original.height, box[3]))
        if box[2] - box[0] < 4 or box[3] - box[1] < 4:
            continue
        crop = original.crop(box)
        buffer = io.BytesIO()
        if "logo" in ident.lower():
            crop.save(buffer, format="PNG", optimize=True)
            kind = "image/png"
        else:
            crop.save(buffer, format="JPEG", quality=90)
            kind = "image/jpeg"
        out[ident] = {"content_type": kind, "data": base64.b64encode(buffer.getvalue()).decode()}
    return out


# ---------------------------------------------------------------------------
# Claude
# ---------------------------------------------------------------------------

def _ask(content: List[Dict[str, Any]]) -> str:
    """One Claude call with streaming (long answers), primary model then fallbacks."""
    llm = get_claude_llm()
    last_error = None
    for model in [llm.model] + [m for m in llm.fallback_models if m != llm.model]:
        try:
            with llm.client.messages.stream(model=model, max_tokens=MAX_TOKENS,
                                            messages=[{"role": "user", "content": content}]) as stream:
                message = stream.get_final_message()
            return _response_text(message)
        except Exception as e:  # noqa: BLE001
            last_error = e
            if "404" in str(e) or "not_found" in str(e):
                continue
            raise
    raise last_error or RuntimeError("No Claude model available")


def _tag(text: str, name: str) -> str:
    match = re.search(rf"<{name}>(.*?)</{name}>", text, re.S)
    return match.group(1).strip() if match else ""


def _json_list(text: str) -> List[Any]:
    text = text.strip()
    if text.startswith("```"):
        text = text.strip("`").lstrip("json").strip()
    try:
        value = json.loads(text) if text else []
    except ValueError:
        return []
    return value if isinstance(value, list) else []


def _parse(text: str) -> Dict[str, Any]:
    design = {
        "header_html": _clean_html(_tag(text, "header_html")),
        "main_html": _clean_html(_tag(text, "main_html")),
        "footer_html": _clean_html(_tag(text, "footer_html")),
        "css": _clean_css(_tag(text, "css")),
        "page_bg": _tag(text, "page_bg") if re.fullmatch(r"#[0-9a-fA-F]{6}", _tag(text, "page_bg") or "") else "#ffffff",
        "images": _json_list(_tag(text, "images")),
        "fonts": [f for f in _json_list(_tag(text, "fonts")) if isinstance(f, str) and re.fullmatch(r"[A-Za-z0-9 ]{2,40}", f)][:4],
        "products": [p for p in _json_list(_tag(text, "products")) if isinstance(p, dict)][:24],
        "description": _tag(text, "description")[:300],
    }
    if not design["main_html"]:
        raise ValueError("The design answer had no page content")
    return design


def _clean_html(html: str) -> str:
    html = re.sub(r"<(script|iframe|object|embed|style|noscript)\b[^>]*>.*?</\1\s*>", "", html, flags=re.S | re.I)
    html = re.sub(r"</?(script|iframe|object|embed|style|base|meta|link|noscript)\b[^>]*>", "", html, flags=re.I)
    html = re.sub(r"\son[a-z]+\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+)", "", html, flags=re.I)
    html = re.sub(r"javascript:", "", html, flags=re.I)
    html = re.sub(r"<(/?)form\b", r"<\1div", html, flags=re.I)
    return html.strip()


def _clean_css(css: str) -> str:
    css = re.sub(r"@import[^;]*;", "", css, flags=re.I)
    css = re.sub(r"expression\s*\(", "", css, flags=re.I)
    css = css.replace("</style", "")
    return css.strip()


def _first_prompt(viewport: int, store_name: str, slice_count: int, mobile_count: int) -> str:
    return (
        f"You are a senior front-end developer. The images are a full-page screenshot of the home page of the online "
        f"store \"{store_name}\", cut into {slice_count} slices from top to bottom"
        + (f", followed by {mobile_count} slices of the same page on a phone" if mobile_count else "")
        + ". Rebuild this page as HTML and CSS so that it looks EXACTLY like the screenshot: a pixel-accurate copy.\n\n"
        + RULES.format(viewport=viewport)
    )


def _fix_prompt(viewport: int, design: Dict[str, Any], bands: List[Dict[str, Any]], score: float) -> str:
    regions = "\n".join(f"- Region {i + 1}: page y {b['y0']}px to {b['y1']}px (difference {b['diff']:.1f}%)"
                        for i, b in enumerate(bands))
    current = "\n".join(f"<{name}>{design[name] if isinstance(design[name], str) else json.dumps(design[name], ensure_ascii=False)}</{name}>"
                        for name in PARTS)
    return (
        f"Your HTML/CSS copy of the store home page was rendered and compared with the original screenshot. "
        f"Match score: {score * 100:.1f}%. The images come in pairs for each region below: first the ORIGINAL, then YOUR "
        f"RENDER of the same region.\n{regions}\n\n"
        "Fix every difference you see (sizes, spacing, positions, colours, fonts, borders, missing or extra elements) "
        "and also check the rest of the page. Keep the image IDs and boxes that are right; you may change boxes that "
        "are wrong (they refer to the original full-page slices you saw first).\n\n"
        "Return the COMPLETE corrected page in the same tagged format.\n\n"
        + RULES.format(viewport=viewport)
        + "\n\nCurrent version:\n" + current
    )


# ---------------------------------------------------------------------------
# Rendering and comparing
# ---------------------------------------------------------------------------

def fill_products(html: str, products: List[Dict[str, str]]) -> str:
    """Fill the product grid template with products: dicts with name, price, compare_price, sale_label, image, url."""
    def esc(value: Any) -> str:
        return (str(value or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;"))

    def grid(match: re.Match) -> str:
        opening, count, inner = match.group(1), int(match.group(2) or 0), match.group(3)
        template = re.search(r"<template\s+data-tellora-card[^>]*>(.*?)</template>", inner, re.S)
        if not template:
            return match.group(0)
        cards = []
        for product in products[: max(count, 1)]:
            card = template.group(1)
            for key in ("name", "price", "compare_price", "sale_label", "image", "url"):
                card = card.replace("{{" + key + "}}", esc(product.get(key)))
            cards.append(card)
        return opening + inner.replace(template.group(0), "".join(cards)) + "</div>"

    return re.sub(r"(<div[^>]*data-tellora-products=\"(\d*)\"[^>]*>)(.*?<template\s+data-tellora-card.*?</template>.*?)</div>",
                  grid, html, count=1, flags=re.S)


def _document(design: Dict[str, Any], images: Dict[str, Dict[str, str]]) -> str:
    def src(ident: str) -> str:
        image = images.get(ident)
        return f"data:{image['content_type']};base64,{image['data']}" if image else ""

    sample = [{
        "name": p.get("name"), "price": p.get("price"), "compare_price": p.get("compare_price"),
        "sale_label": p.get("sale_label"), "image": src(str(p.get("image_id", ""))), "url": "#",
    } for p in design["products"]]

    def swap(text: str) -> str:
        return re.sub(r"tellora-image:([a-zA-Z0-9_-]+)", lambda m: src(m.group(1)), text)

    body = (f"<div class='tm-root tm-header'>{swap(design['header_html'])}</div>"
            f"<div class='tm-root tm-main'>{fill_products(swap(design['main_html']), sample)}</div>"
            f"<div class='tm-root tm-footer'>{swap(design['footer_html'])}</div>")
    fonts = "&".join("family=" + f.replace(" ", "+") + ":ital,wght@0,300;0,400;0,500;0,600;0,700;1,400" for f in design["fonts"])
    font_link = f'<link rel="stylesheet" href="https://fonts.googleapis.com/css2?{fonts}&display=swap">' if fonts else ""
    return (
        "<!doctype html><html><head><meta charset='utf-8'>" + font_link
        + f"<style>html,body{{margin:0;padding:0;background:{design['page_bg']}}}{RESET}{swap(design['css'])}</style>"
        + f"</head><body>{body}</body></html>"
    )


async def _render(html: str, viewport: int, dpr: float) -> Image.Image:
    from playwright.async_api import async_playwright

    async with async_playwright() as p:
        browser = await p.chromium.launch(args=["--no-sandbox"])
        try:
            page = await browser.new_page(viewport={"width": viewport, "height": 900}, device_scale_factor=dpr)
            await page.set_content(html, wait_until="networkidle", timeout=60000)
            await page.evaluate("document.fonts.ready")
            await page.wait_for_timeout(400)
            shot = await page.screenshot(full_page=True, type="png")
        finally:
            await browser.close()
    return _open(shot)


def _compare(original: Image.Image, render: Image.Image, dpr: float) -> Tuple[float, List[Dict[str, Any]]]:
    """Similarity 0..1 and the bands of the page that differ most."""
    width = 480
    a = original.convert("L").resize((width, max(1, round(original.height * width / original.width))))
    b = render.convert("L").resize((width, max(1, round(render.height * width / render.width))))
    height = min(a.height, b.height)
    if height < 10:
        return 0.0, []
    a_top, b_top = a.crop((0, 0, width, height)), b.crop((0, 0, width, height))
    diff = ImageChops.difference(a_top, b_top)
    pixel_match = 1 - ImageStat.Stat(diff).mean[0] / 255
    height_match = min(a.height, b.height) / max(a.height, b.height)
    score = pixel_match * (0.7 + 0.3 * height_match)

    css_per_px = (original.width / dpr) / width
    band = max(8, round(BAND_CSS_HEIGHT / css_per_px))
    bands = []
    for top in range(0, height, band):
        region = diff.crop((0, top, width, min(height, top + band)))
        bands.append({
            "y0": round(top * css_per_px), "y1": round(min(height, top + band) * css_per_px),
            "diff": ImageStat.Stat(region).mean[0] / 255 * 100,
        })
    if b.height > a.height * 1.05 or a.height > b.height * 1.05:
        bands.append({"y0": round(height * css_per_px), "y1": round(max(a.height, b.height) * css_per_px), "diff": 100.0})
    bands.sort(key=lambda x: -x["diff"])
    return score, bands[:3]


def _band_images(original: Image.Image, render: Image.Image, bands: List[Dict[str, Any]], dpr: float) -> List[Dict[str, Any]]:
    blocks = []
    for item in bands:
        for image in (original, render):
            top, bottom = round(item["y0"] * dpr), round(item["y1"] * dpr)
            top = min(top, max(0, image.height - 10))
            bottom = min(max(bottom, top + 10), image.height)
            part = image.crop((0, top, image.width, bottom))
            scale = CLAUDE_SLICE_WIDTH / part.width
            blocks.append(_image_block(part.resize((CLAUDE_SLICE_WIDTH, max(1, round(part.height * scale))), Image.LANCZOS)))
    return blocks


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

async def build_design(desktop: bytes, mobile: Optional[bytes], store_name: str) -> Dict[str, Any]:
    original = _open(desktop)
    viewport, dpr = _viewport(original)
    slices = _slices(original, dpr, CLAUDE_SLICE_WIDTH)

    mobile_slices: List[Dict[str, Any]] = []
    if mobile:
        phone = _open(mobile)
        _, phone_dpr = _viewport(phone)
        phone_dpr = max(phone_dpr, phone.width / 430) if phone.width > 430 else 1.0
        mobile_slices = _slices(phone, phone_dpr, 500)[:6]

    first = [_image_block(s["image"]) for s in slices] + [_image_block(s["image"]) for s in mobile_slices]
    first.append({"type": "text", "text": _first_prompt(viewport, store_name, len(slices), len(mobile_slices))})

    logger.info(f"[screenshot-design] {store_name}: viewport {viewport}px @{dpr:.2f}x, {len(slices)} slices")
    design = _parse(await asyncio.to_thread(_ask, first))
    images = _cut_images(original, slices, design["images"])

    best = None
    for attempt in range(1, MAX_PASSES + 1):
        render = await _render(_document(design, images), viewport, dpr)
        score, bands = _compare(original, render, dpr)
        logger.info(f"[screenshot-design] {store_name}: pass {attempt} match {score * 100:.1f}%")
        if best is None or score > best["score"]:
            best = {"design": design, "images": images, "score": score, "passes": attempt}
        if score >= TARGET_SCORE or attempt == MAX_PASSES:
            break

        content = [_image_block(s["image"]) for s in slices]
        content += _band_images(original, render, bands, dpr)
        content.append({"type": "text", "text": _fix_prompt(viewport, design, bands, score)})
        try:
            design = _parse(await asyncio.to_thread(_ask, content))
            images = _cut_images(original, slices, design["images"]) or images
        except Exception as e:  # noqa: BLE001
            logger.warning(f"[screenshot-design] correction {attempt} failed: {e}")
            break

    result = best["design"]
    return {
        "header_html": result["header_html"],
        "main_html": result["main_html"],
        "footer_html": result["footer_html"],
        "css": result["css"],
        "page_bg": result["page_bg"],
        "fonts": result["fonts"],
        "products": result["products"],
        "description": result["description"],
        "images": best["images"],
        "score": round(best["score"] * 100, 1),
        "passes": best["passes"],
        "viewport": viewport,
    }
