"""Screenshot to store design: rebuilds a store's home page from screenshots the owner uploads.

How it gets close to an exact copy (POST /api/v1/screenshot-design):
  1. SECTIONS: the full-page desktop screenshot is cut into its real sections (header + hero,
     collection cards, banners, product grid, footer ...) at the background gaps between them,
     measured from the pixels, not guessed.
  2. ONE SECTION AT A TIME: Claude (vision) gets each section at high resolution and writes
     HTML + CSS for that section only, with its exact height. Photos and the logo are cut out
     of the screenshot itself; their boxes are snapped to the real edges in the pixels.
  3. CHECK AND FIX, PER SECTION: each section is rendered in a real browser (Chromium) at the
     screenshot's width and compared with its part of the screenshot. Claude gets the original,
     its render and a difference map, and corrects the code. The best version of each section
     is kept.
  4. The sections are joined; the whole page is rendered and compared once more for the score.

The product grid is a template that Tellora fills with the store's real products.
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

from PIL import Image, ImageChops, ImageFilter, ImageOps, ImageStat

from app.services.claude_llm import get_claude_llm

logger = logging.getLogger(__name__)

SECTION_GAP_CSS = 40         # a background gap at least this tall separates two sections
SECTION_MIN_CSS = 380        # smaller sections are joined to the next one
SECTION_MAX_CSS = 1600       # taller sections are split at their calmest row
CLAUDE_WIDTH = 1400          # sections are sent to Claude at this width
FIX_PASSES = 2               # corrections per section after the first version
SECTION_TARGET = 0.975       # stop correcting a section at this match
PARALLEL = 3                 # sections worked on at the same time
MAX_TOKENS = 20000

# Same base as the storefront (MirrorDesign::RESET in Rails): browser defaults inside .tm-root
RESET = (".tm-root{all:revert;display:block;font:initial;color:initial;line-height:normal;letter-spacing:normal;"
         "word-spacing:normal;text-align:start;text-transform:none}"
         ".tm-root *:where(:not(svg, svg *)){all:revert}")

SECTION_RULES = """
Rules for an exact copy:
- Copy every text EXACTLY as written (same language, accents, capitals, punctuation).
- The page is {viewport}px wide. This section is exactly {height}px tall. Measure every size in CSS pixels
  of that width: in the image, 1 CSS pixel = {ratio:.3f} image pixels.
- Match colours (pick them from the image), font sizes, weights, letter spacing, line heights, positions,
  widths, heights, paddings, margins, borders, radius and shadows as precisely as you can measure them.
- Choose the closest Google Fonts for the fonts you see (serif vs sans, weight, width).
- Inside the page every element starts from the browser defaults (Times New Roman 16px, default margins):
  set fonts, margins, paddings, list styles and image sizes explicitly.
- The section's root element is <section class="tm-sec tm-sec-{index}"> with height:{height}px; position:relative;
  overflow:hidden; width:100%; box-sizing:border-box. Every CSS rule MUST start with ".tm-root .tm-sec-{index}".
  No rules for html, body or *. No @import. You may use @media.
- No JavaScript, no <script>, no inline event handlers, no <iframe>, no <form> (use <div> and <a>).
- Icons (search, account, cart, truck, phone, arrows ...): inline <svg> with simple paths, right size and colour.
- Every photo, product photo, logo or picture area: <img src="tellora-image:ID" alt="..."> (or CSS
  background url(tellora-image:ID)), sized and placed exactly where it is. Text written ON TOP of a photo
  in the screenshot is real HTML text placed over the image.
- Links: logo -> "/", cart -> "/cart", account -> "/account", search -> "/products", shop / collection /
  category / discover / explore links -> "/products", anything else -> "#".
""".strip()

GRID_RULES = """
- THIS SECTION HAS THE PRODUCT GRID. Write ONE container <div data-tellora-products="N"> (N = number of products
  shown) styled exactly like the grid, containing ONLY one <template data-tellora-card>...</template> with the card
  markup. In the card use the placeholders {{{{name}}}}, {{{{price}}}}, {{{{compare_price}}}}, {{{{sale_label}}}},
  {{{{image}}}} (an image URL: <img src="{{{{image}}}}">) and {{{{url}}}} (product link, also for an "Add to cart"
  button). compare_price and sale_label are empty when a product is not on sale: put each in its own element and
  hide it with CSS when :empty. Do NOT list product photos in <images>; list the products in <products>.
""".strip()

OUTPUT_FORMAT = """
Output EXACTLY these tagged parts, nothing before or after them:
{html_parts}
<css>...</css>                  all CSS for this section
<images>[...]</images>          JSON list: {{"id": "...", "box": [x, y, width, height]}} for every tellora-image ID,
                                box in pixels of the IMAGE you were given (tight around the picture only)
<fonts>[...]</fonts>            JSON list of Google Font family names used in this section
<products>[...]</products>      JSON list (only for the product grid): {{"name": "...", "price": "...",
                                "compare_price": "", "sale_label": "", "box": [x, y, width, height]}}
<description>...</description>  one sentence: what the shop sells, in the site's language (first section only)
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


def _jpeg_b64(image: Image.Image, quality: int = 85) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=quality)
    return base64.b64encode(buffer.getvalue()).decode()


def _image_block(image: Image.Image) -> Dict[str, Any]:
    return {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": _jpeg_b64(image)}}


def _fit(image: Image.Image, width: int) -> Image.Image:
    if image.width == width:
        return image
    return image.resize((width, max(1, round(image.height * width / image.width))), Image.LANCZOS)


def segment(image: Image.Image, dpr: float) -> List[Tuple[int, int]]:
    """Cut a full-page screenshot into sections at horizontal background gaps. Returns [(top, bottom)] in image px."""
    width = 480
    scale = image.width / width
    small = image.convert("L").resize((width, max(1, round(image.height / scale))))
    rows = small.height
    std = [ImageStat.Stat(small.crop((0, y, width, y + 1))).stddev[0] for y in range(rows)]
    uniform = [s < 3.0 for s in std]
    rows_per_css = dpr / scale
    min_gap = max(1, round(SECTION_GAP_CSS * rows_per_css))

    def css(h: int) -> float:
        return h / rows_per_css

    cuts = [0]
    y = 0
    while y < rows:
        if uniform[y]:
            start = y
            while y < rows and uniform[y]:
                y += 1
            if y - start >= min_gap and start > 0 and y < rows:
                cuts.append((start + y) // 2)
        else:
            y += 1
    cuts.append(rows)
    sections = [(cuts[i], cuts[i + 1]) for i in range(len(cuts) - 1) if cuts[i + 1] > cuts[i]]

    merged: List[Tuple[int, int]] = []
    for top, bottom in sections:
        if merged and css(merged[-1][1] - merged[-1][0]) < SECTION_MIN_CSS:
            merged[-1] = (merged[-1][0], bottom)
        else:
            merged.append((top, bottom))
    if len(merged) > 1 and css(merged[-1][1] - merged[-1][0]) < SECTION_MIN_CSS:
        last = merged.pop()
        merged[-1] = (merged[-1][0], last[1])

    out: List[Tuple[int, int]] = []
    for top, bottom in merged:
        stack = [(top, bottom)]
        while stack:
            t, b = stack.pop(0)
            if css(b - t) <= SECTION_MAX_CSS:
                out.append((t, b))
                continue
            lo, hi = t + (b - t) // 3, t + 2 * (b - t) // 3
            cut = min(range(lo, hi), key=lambda r: std[r])
            stack[0:0] = [(t, cut), (cut, b)]
    return [(round(t * scale), min(image.height, round(b * scale))) for t, b in out]


def snap(section: Image.Image, box: Tuple[int, int, int, int], edges: Optional[Image.Image] = None) -> Tuple[int, int, int, int]:
    """Move each side of a rough image box to the strongest straight edge near it."""
    x0, y0, x1, y1 = box
    w, h = section.size
    edges = edges or section.convert("L").filter(ImageFilter.FIND_EDGES)
    mx, my = max(24, round((x1 - x0) * 0.15)), max(24, round((y1 - y0) * 0.15))

    def row_score(y: int) -> float:
        return ImageStat.Stat(edges.crop((x0, y, x1, y + 1))).mean[0] if 0 <= y < h and x1 > x0 else 0.0

    def col_score(x: int) -> float:
        return ImageStat.Stat(edges.crop((x, y0, x + 1, y1))).mean[0] if 0 <= x < w and y1 > y0 else 0.0

    def best(current: int, lo: int, hi: int, score, limit: int) -> int:
        candidates = range(max(0, lo), min(limit, hi))
        if not candidates:
            return current
        found = max(candidates, key=score)
        return found if score(found) > max(score(current) * 1.5, 12) else current

    ny0 = 0 if y0 < my else best(y0, y0 - my, y0 + my, row_score, h)
    ny1 = h if y1 > h - my else best(y1 - 1, y1 - 1 - my, y1 - 1 + my, row_score, h) + 1
    nx0 = 0 if x0 < mx else best(x0, x0 - mx, x0 + mx, col_score, w)
    nx1 = w if x1 > w - mx else best(x1 - 1, x1 - 1 - mx, x1 - 1 + mx, col_score, w) + 1
    if nx1 - nx0 < 8 or ny1 - ny0 < 8:
        return box
    return (nx0, ny0, nx1, ny1)


def _cut(section: Image.Image, scale: float, entries: List[Dict[str, Any]], prefix: str,
         edges: Image.Image) -> Dict[str, Dict[str, str]]:
    """Cut the requested images out of a full-resolution section (boxes given in Claude-image pixels)."""
    out: Dict[str, Dict[str, str]] = {}
    for entry in entries or []:
        try:
            ident = re.sub(r"[^a-zA-Z0-9_-]", "", str(entry["id"]))[:40]
            x, y, w, h = [float(v) for v in entry["box"]]
        except (KeyError, ValueError, TypeError):
            continue
        if not ident or w < 4 or h < 4:
            continue
        box = (round(x / scale), round(y / scale), round((x + w) / scale), round((y + h) / scale))
        box = (max(0, box[0]), max(0, box[1]), min(section.width, box[2]), min(section.height, box[3]))
        if box[2] - box[0] < 4 or box[3] - box[1] < 4:
            continue
        box = snap(section, box, edges)
        crop = section.crop(box)
        buffer = io.BytesIO()
        if "logo" in ident.lower():
            crop.save(buffer, format="PNG", optimize=True)
            kind = "image/png"
        else:
            crop.save(buffer, format="JPEG", quality=90)
            kind = "image/jpeg"
        out[f"{prefix}{ident}"] = {"content_type": kind, "data": base64.b64encode(buffer.getvalue()).decode()}
    return out


# ---------------------------------------------------------------------------
# Claude
# ---------------------------------------------------------------------------

def _field(item: Any, name: str) -> Any:
    """Read a field from an SDK object or a plain dict (newer API events can arrive as dicts)."""
    if isinstance(item, dict):
        return item.get(name)
    return getattr(item, name, None)


def _ask(content: List[Dict[str, Any]], max_tokens: int = MAX_TOKENS) -> str:
    """One Claude call, streamed (long answers), primary model then fallbacks.

    Reads the raw event stream and keeps only the text, so it works whatever
    SDK version is installed.
    """
    llm = get_claude_llm()
    last_error = None
    for model in [llm.model] + [m for m in llm.fallback_models if m != llm.model]:
        try:
            stream = llm.client.messages.create(model=model, max_tokens=max_tokens, stream=True,
                                                messages=[{"role": "user", "content": content}])
            parts: List[str] = []
            stop_reason = None
            for event in stream:
                kind = _field(event, "type")
                if kind == "content_block_delta":
                    delta = _field(event, "delta")
                    if _field(delta, "type") == "text_delta":
                        parts.append(_field(delta, "text") or "")
                elif kind == "message_delta":
                    stop_reason = _field(_field(event, "delta"), "stop_reason") or stop_reason
            text = "".join(parts)
            if stop_reason == "max_tokens":
                logger.warning("[screenshot-design] answer was cut at the token limit")
            if not text.strip():
                raise RuntimeError("Claude returned an empty answer")
            return text
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


# ---------------------------------------------------------------------------
# One section
# ---------------------------------------------------------------------------

class Section:
    def __init__(self, index: int, count: int, image: Image.Image, top: int, viewport: int, dpr: float):
        self.index = index
        self.count = count
        self.image = image                       # full resolution
        self.top = top
        self.viewport = viewport
        self.dpr = dpr
        self.height_css = round(image.height / dpr)
        self.scale = CLAUDE_WIDTH / image.width   # Claude-image px per full-resolution px
        self.claude_image = _fit(image, CLAUDE_WIDTH)
        self.edges = image.convert("L").filter(ImageFilter.FIND_EDGES)
        self.first = index == 0
        self.last = index == count - 1
        self.is_grid = False
        self.best: Optional[Dict[str, Any]] = None

    @property
    def prefix(self) -> str:
        return f"s{self.index}-"

    def html_parts(self) -> str:
        if not (self.first or self.last):
            return "<main_html>...</main_html>       this section"
        parts, roots = [], []
        if self.first:
            parts.append("<header_html>...</header_html>   ONLY the announcement bar + header/navigation at the top")
            roots.append('<div class="tm-sec tm-sec-{i} tm-sec-head"> for the header')
        parts.append("<main_html>...</main_html>       the rest of this section")
        roots.append('<section class="tm-sec tm-sec-{i}"> for the rest')
        if self.last:
            parts.append("<footer_html>...</footer_html>   ONLY the site footer at the bottom")
            roots.append('<div class="tm-sec tm-sec-{i} tm-sec-foot"> for the footer')
        note = ("\nEach part has its own root element: " + ", ".join(roots)
                + ". Their heights must add up to exactly {h}px (the section root rule above applies to each of them, "
                  "with its own height).")
        return "\n".join(parts) + note.format(i=self.index, h=self.height_css)

    def rules(self) -> str:
        rules = SECTION_RULES.format(viewport=self.viewport, height=self.height_css,
                                     ratio=self.claude_image.width / self.viewport, index=self.index)
        if self.is_grid:
            rules += "\n" + GRID_RULES
        return rules + "\n\n" + OUTPUT_FORMAT.format(html_parts=self.html_parts())

    def first_prompt(self, store_name: str) -> str:
        where = "the top" if self.first else ("the bottom" if self.last else f"part {self.index + 1} of {self.count}")
        return (
            f"You are a senior front-end developer making a pixel-accurate copy of the home page of the online store "
            f"\"{store_name}\". The image is {where} of the page: one section, {self.viewport}px wide and "
            f"{self.height_css}px tall. Rebuild ONLY this section as HTML and CSS so it looks EXACTLY like the image.\n\n"
            + self.rules()
        )

    def fix_prompt(self, design: Dict[str, Any], score: float, boxes: Dict[str, Tuple[int, int, int, int]]) -> str:
        placed = "\n".join(
            f"- {ident}: left {round(b[0] / self.dpr)}px, top {round(b[1] / self.dpr)}px, "
            f"width {round((b[2] - b[0]) / self.dpr)}px, height {round((b[3] - b[1]) / self.dpr)}px"
            for ident, b in boxes.items())
        current = "\n".join(f"<{name}>{design.get(name, '')}</{name}>"
                            for name in ("header_html", "main_html", "footer_html", "css") if design.get(name))
        return (
            f"The images are: 1) the ORIGINAL section, 2) YOUR RENDER of your code, 3) a difference map (bright = "
            f"different). Match: {score * 100:.1f}%. Make your render identical to the original: fix every difference in "
            f"size, position, spacing, colour, font, weight, line breaks, borders and missing or extra elements.\n\n"
            + (f"The photos are measured exactly here (CSS px inside this section); place them exactly like this:\n{placed}\n\n"
               if placed else "")
            + "Return the COMPLETE corrected section in the same tagged format.\n\n" + self.rules()
            + "\n\nYour current code:\n" + current
        )

    def parse(self, text: str) -> Dict[str, Any]:
        design = {
            "header_html": _clean_html(_tag(text, "header_html")) if self.first else "",
            "main_html": _clean_html(_tag(text, "main_html")),
            "footer_html": _clean_html(_tag(text, "footer_html")) if self.last else "",
            "css": _clean_css(_tag(text, "css")),
            "images": _json_list(_tag(text, "images")),
            "fonts": [f for f in _json_list(_tag(text, "fonts")) if isinstance(f, str) and re.fullmatch(r"[A-Za-z0-9 ]{2,40}", f)][:3],
            "products": [p for p in _json_list(_tag(text, "products")) if isinstance(p, dict)][:24],
            "description": _tag(text, "description")[:300],
        }
        if not (design["header_html"] or design["main_html"] or design["footer_html"]):
            raise ValueError(f"Section {self.index}: the answer had no HTML")
        # Prefix image ids so sections never clash (once: corrections may already use prefixed ids)
        for key in ("header_html", "main_html", "footer_html", "css"):
            design[key] = re.sub(r"tellora-image:([a-zA-Z0-9_-]+)", lambda m: f"tellora-image:{self.local_id(m.group(1), True)}", design[key])
        for entry in design["images"]:
            if isinstance(entry, dict) and "id" in entry:
                entry["id"] = self.local_id(str(entry["id"]), False)
        return design

    def local_id(self, ident: str, prefixed: bool) -> str:
        """Image id without (prefixed=False) or with (prefixed=True) this section's prefix, never doubled."""
        ident = re.sub(r"[^a-zA-Z0-9_-]", "", ident)[:60]
        while ident.startswith(self.prefix):
            ident = ident[len(self.prefix):]
        return f"{self.prefix}{ident}" if prefixed else ident

    def cut_images(self, design: Dict[str, Any]) -> Tuple[Dict[str, Dict[str, str]], Dict[str, Tuple[int, int, int, int]]]:
        images = _cut(self.image, self.scale, design["images"], self.prefix, self.edges)
        boxes = {}
        for entry in design["images"]:
            try:
                ident = self.prefix + re.sub(r"[^a-zA-Z0-9_-]", "", str(entry["id"]))[:40]
                x, y, w, h = [float(v) for v in entry["box"]]
                box = (round(x / self.scale), round(y / self.scale), round((x + w) / self.scale), round((y + h) / self.scale))
                boxes[ident] = snap(self.image, box, self.edges)
            except (KeyError, ValueError, TypeError):
                continue
        # Product photos for checking the grid (the real store fills in its own products)
        for i, product in enumerate(design["products"]):
            try:
                x, y, w, h = [float(v) for v in product["box"]]
            except (KeyError, ValueError, TypeError):
                continue
            ident = f"{self.prefix}product{i}"
            images.update(_cut(self.image, self.scale, [{"id": f"product{i}", "box": [x, y, w, h]}], self.prefix, self.edges))
            product["image_id"] = ident
        return images, boxes


# ---------------------------------------------------------------------------
# Rendering and comparing
# ---------------------------------------------------------------------------

def _document(parts: List[Dict[str, Any]], images: Dict[str, Dict[str, str]], fonts: List[str], page_bg: str,
              extra_css: str = "") -> str:
    def src(ident: str) -> str:
        image = images.get(ident)
        return f"data:{image['content_type']};base64,{image['data']}" if image else ""

    def swap(text: str) -> str:
        return re.sub(r"tellora-image:([a-zA-Z0-9_-]+)", lambda m: src(m.group(1)), text)

    header = "".join(p.get("header_html", "") for p in parts)
    footer = "".join(p.get("footer_html", "") for p in parts)
    main = ""
    for part in parts:
        sample = [{"name": p.get("name"), "price": p.get("price"), "compare_price": p.get("compare_price"),
                   "sale_label": p.get("sale_label"), "image": src(str(p.get("image_id", ""))), "url": "#"}
                  for p in part.get("products", [])]
        main += fill_products(part.get("main_html", ""), sample)
    css = "".join(p.get("css", "") for p in parts) + extra_css

    families = "&".join("family=" + f.replace(" ", "+") + ":ital,wght@0,300;0,400;0,500;0,600;0,700;1,400" for f in fonts)
    font_link = f'<link rel="stylesheet" href="https://fonts.googleapis.com/css2?{families}&display=swap">' if families else ""
    blocks = ""
    if header:
        blocks += f"<div class='tm-root tm-header'>{swap(header)}</div>"
    blocks += f"<div class='tm-root tm-main'>{swap(main)}</div>"
    if footer:
        blocks += f"<div class='tm-root tm-footer'>{swap(footer)}</div>"
    return (
        "<!doctype html><html><head><meta charset='utf-8'>" + font_link
        + f"<style>html,body{{margin:0;padding:0;background:{page_bg}}}{RESET}{swap(css)}</style>"
        + f"</head><body>{blocks}</body></html>"
    )


class Renderer:
    """One Chromium for the whole job; each render gets its own page."""

    def __init__(self, viewport: int, dpr: float):
        self.viewport = viewport
        self.dpr = dpr
        self._playwright = None
        self._browser = None

    async def __aenter__(self):
        from playwright.async_api import async_playwright
        self._playwright = await async_playwright().start()
        self._browser = await self._playwright.chromium.launch(args=["--no-sandbox"])
        return self

    async def __aexit__(self, *exc):
        if self._browser:
            await self._browser.close()
        if self._playwright:
            await self._playwright.stop()

    async def render(self, html: str, width: Optional[int] = None) -> Image.Image:
        page = await self._browser.new_page(viewport={"width": width or self.viewport, "height": 100},
                                            device_scale_factor=self.dpr)
        try:
            await page.set_content(html, wait_until="networkidle", timeout=60000)
            await page.evaluate("document.fonts.ready")
            await page.wait_for_timeout(300)
            shot = await page.screenshot(full_page=True, type="png")
        finally:
            await page.close()
        return _open(shot)


def _score(original: Image.Image, render: Image.Image) -> float:
    """Similarity 0..1 of two images of the same width (height differences count against)."""
    width = 480
    a = original.convert("L").resize((width, max(1, round(original.height * width / original.width))))
    b = render.convert("L").resize((width, max(1, round(render.height * width / render.width))))
    height = min(a.height, b.height)
    if height < 4:
        return 0.0
    diff = ImageChops.difference(a.crop((0, 0, width, height)), b.crop((0, 0, width, height)))
    pixel_match = 1 - ImageStat.Stat(diff).mean[0] / 255
    height_match = height / max(a.height, b.height)
    return pixel_match * (0.6 + 0.4 * height_match)


def _diff_map(original: Image.Image, render: Image.Image) -> Image.Image:
    render = render.crop((0, 0, original.width, original.height)) if render.height >= original.height else render
    canvas = Image.new("RGB", original.size, (0, 0, 0))
    canvas.paste(render, (0, 0))
    diff = ImageChops.difference(original, canvas).convert("L").point(lambda v: min(255, v * 4))
    return diff.convert("RGB")


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def _find_grid(sections: List[Section]) -> None:
    """Ask once which section holds the product grid (small thumbnails, cheap)."""
    content: List[Dict[str, Any]] = []
    for s in sections:
        content.append({"type": "text", "text": f"Section {s.index}:"})
        content.append(_image_block(_fit(s.image, 500)))
    content.append({"type": "text", "text": (
        "These are the sections of an online store home page, top to bottom. Which section shows a grid of PRODUCTS "
        "with prices (not collections or categories)? Answer only with JSON: {\"products\": [section numbers]}.")})
    try:
        answer = _ask(content, max_tokens=200)
        match = re.search(r"\{.*\}", answer, re.S)
        indexes = json.loads(match.group(0)).get("products", []) if match else []
        for s in sections:
            s.is_grid = s.index in indexes
    except Exception as e:  # noqa: BLE001
        logger.warning(f"[screenshot-design] product grid detection failed: {e}")


def _page_background(image: Image.Image) -> str:
    small = image.resize((64, max(1, round(image.height * 64 / image.width))))
    colors = small.getcolors(64 * small.height) or []
    r, g, b = max(colors, key=lambda c: c[0])[1] if colors else (255, 255, 255)
    return "#{:02x}{:02x}{:02x}".format(r, g, b)


async def _build_section(section: Section, store_name: str, renderer: Renderer, page_bg: str,
                         gate: asyncio.Semaphore) -> Dict[str, Any]:
    content: List[Dict[str, Any]] = [_image_block(section.claude_image),
                                     {"type": "text", "text": section.first_prompt(store_name)}]
    for attempt in range(FIX_PASSES + 1):
        try:
            async with gate:
                design = section.parse(await asyncio.to_thread(_ask, content))
        except Exception as e:  # noqa: BLE001
            logger.warning(f"[screenshot-design] section {section.index} answer {attempt + 1} failed: {e}")
            if section.best:
                break
            if attempt == FIX_PASSES:
                raise
            continue
        images, boxes = section.cut_images(design)
        render = await renderer.render(_document([design], images, design["fonts"], page_bg))
        score = _score(section.image, render)
        logger.info(f"[screenshot-design] section {section.index + 1}/{section.count}: pass {attempt + 1} match {score * 100:.1f}%")
        if section.best is None or score > section.best["score"]:
            section.best = {"design": design, "images": images, "score": score}
        if score >= SECTION_TARGET or attempt == FIX_PASSES:
            break
        shown = render.crop((0, 0, render.width, min(render.height, section.image.height)))
        content = [
            _image_block(section.claude_image),
            _image_block(_fit(shown, CLAUDE_WIDTH)),
            _image_block(_fit(_diff_map(section.image, render), CLAUDE_WIDTH)),
            {"type": "text", "text": section.fix_prompt(design, score, boxes)},
        ]
    return section.best


async def _mobile_css(parts: List[Dict[str, Any]], mobile: Image.Image) -> str:
    """One extra pass: @media CSS so the same HTML matches the phone screenshot."""
    _, dpr = _viewport(mobile)
    dpr = max(dpr, mobile.width / 430) if mobile.width > 430 else 1.0
    step = int(1400 * dpr)
    content: List[Dict[str, Any]] = []
    for top in range(0, min(mobile.height, step * 8), step):
        content.append(_image_block(_fit(mobile.crop((0, top, mobile.width, min(mobile.height, top + step))), 500)))
    html = "\n".join(p.get("header_html", "") + p.get("main_html", "") + p.get("footer_html", "") for p in parts)
    content.append({"type": "text", "text": (
        "The images are a phone screenshot of a store home page, top to bottom. Below is the HTML of the desktop version. "
        "Write ONLY the CSS inside one @media (max-width: 768px) { ... } block so this same HTML looks exactly like the "
        "phone screenshot. Every rule must start with .tm-root. Output only <css>...</css>.\n\n" + html[:60000])})
    try:
        return _clean_css(_tag(await asyncio.to_thread(_ask, content), "css"))
    except Exception as e:  # noqa: BLE001
        logger.warning(f"[screenshot-design] mobile CSS failed: {e}")
        return ""


async def build_design(desktop: bytes, mobile: Optional[bytes], store_name: str) -> Dict[str, Any]:
    original = _open(desktop)
    viewport, dpr = _viewport(original)
    cuts = segment(original, dpr)
    sections = [Section(i, len(cuts), original.crop((0, top, original.width, bottom)), top, viewport, dpr)
                for i, (top, bottom) in enumerate(cuts)]
    page_bg = _page_background(original)
    logger.info(f"[screenshot-design] {store_name}: viewport {viewport}px @{dpr:.2f}x, {len(sections)} sections")

    await asyncio.to_thread(_find_grid, sections)

    gate = asyncio.Semaphore(PARALLEL)
    async with Renderer(viewport, dpr) as renderer:
        results = await asyncio.gather(*(_build_section(s, store_name, renderer, page_bg, gate) for s in sections),
                                       return_exceptions=True)
        parts, images, fonts = [], {}, []
        for section, result in zip(sections, results):
            if isinstance(result, Exception) or not result:
                logger.warning(f"[screenshot-design] section {section.index} dropped: {result}")
                continue
            parts.append(result["design"])
            images.update(result["images"])
            fonts += [f for f in result["design"]["fonts"] if f not in fonts]
        if not parts:
            raise RuntimeError("No section of the page could be rebuilt")
        fonts = fonts[:4]

        mobile_css = await _mobile_css(parts, _open(mobile)) if mobile else ""

        page = await renderer.render(_document(parts, images, fonts, page_bg, mobile_css))
        score = _score(original, page)
    logger.info(f"[screenshot-design] {store_name}: whole page match {score * 100:.1f}%")

    products = [p for part in parts for p in part.get("products", [])]
    description = next((p["description"] for p in parts if p.get("description")), "")
    return {
        "header_html": "".join(p.get("header_html", "") for p in parts),
        "main_html": "".join(p.get("main_html", "") for p in parts),
        "footer_html": "".join(p.get("footer_html", "") for p in parts),
        "css": "".join(p.get("css", "") for p in parts) + mobile_css,
        "page_bg": page_bg,
        "fonts": fonts,
        "products": products,
        "description": description,
        "images": images,
        "score": round(score * 100, 1),
        "passes": len(parts),
        "sections": [{"index": s.index, "score": round((s.best or {}).get("score", 0) * 100, 1)} for s in sections],
        "viewport": viewport,
    }