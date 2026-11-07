"""Reads an existing online store (Shopify, WooCommerce, Shoper, Wix, any site) and
extracts its brand: name, logo, colours, fonts, words and photos.

Used by POST /api/v1/site-import when a store owner moves to Tellora. The Rails app
checks that the owner controls the domain (DNS TXT record) BEFORE calling this.

We never copy the old theme's code. We only read the brand, so Tellora can rebuild
the look on one of its own design families.

Safety: the URL comes from a user, so every request (and every redirect) is checked
to point at a public internet address, with size limits and timeouts.
"""

import asyncio
import colorsys
import ipaddress
import json
import logging
import re
import socket
from collections import Counter
from html.parser import HTMLParser
from typing import Any, Dict, List, Optional, Tuple
from urllib.parse import urljoin, urlparse

import httpx

logger = logging.getLogger(__name__)

USER_AGENT = "Mozilla/5.0 (compatible; TelloraImporter/1.0; +https://tellora.store)"
TIMEOUT = httpx.Timeout(12.0, connect=6.0)
MAX_HTML = 3_000_000      # bytes
MAX_CSS = 1_500_000       # bytes per stylesheet
MAX_STYLESHEETS = 4
MAX_REDIRECTS = 5
MAX_IMAGES = 12

GENERIC_FONTS = {
    "serif", "sans-serif", "monospace", "cursive", "fantasy", "system-ui", "inherit", "initial",
    "unset", "-apple-system", "blinkmacsystemfont", "segoe ui", "roboto", "helvetica", "helvetica neue",
    "arial", "times", "times new roman", "georgia", "ui-sans-serif", "ui-serif", "apple color emoji",
    "segoe ui emoji", "segoe ui symbol", "noto color emoji", "var", "verdana", "tahoma",
}


class ImportError_(Exception):
    """A problem the store owner should see (in plain words)."""


# ---------------------------------------------------------------------------
# Safe fetching
# ---------------------------------------------------------------------------

def _public_host(host: str) -> bool:
    """True when every address of the host is a public internet address."""
    if not host:
        return False
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    addresses = {info[4][0] for info in infos}
    if not addresses:
        return False
    for address in addresses:
        ip = ipaddress.ip_address(address.split("%")[0])
        if (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast
                or ip.is_reserved or ip.is_unspecified):
            return False
    return True


def _check_url(url: str) -> str:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ImportError_("Only http and https addresses can be read")
    if parsed.port not in (None, 80, 443):
        raise ImportError_("Only standard web addresses can be read")
    if not _public_host(parsed.hostname or ""):
        raise ImportError_("That address could not be reached on the public internet")
    return url


async def _fetch(client: httpx.AsyncClient, url: str, limit: int) -> Tuple[str, str]:
    """GET a URL safely. Returns (final_url, text)."""
    current = url
    for _ in range(MAX_REDIRECTS + 1):
        await asyncio.to_thread(_check_url, current)
        async with client.stream("GET", current) as response:
            if response.status_code in (301, 302, 303, 307, 308):
                location = response.headers.get("location")
                if not location:
                    raise ImportError_("The site sent a broken redirect")
                current = urljoin(current, location)
                continue
            if response.status_code == 401 or response.status_code == 403:
                raise ImportError_("The site refused our visit (it may be password protected or behind a firewall)")
            if response.status_code >= 400:
                raise ImportError_(f"The site answered with error {response.status_code}")

            chunks = []
            size = 0
            async for chunk in response.aiter_bytes():
                size += len(chunk)
                if size > limit:
                    break
                chunks.append(chunk)
            body = b"".join(chunks)
            encoding = response.encoding or "utf-8"
            return str(response.url), body.decode(encoding, errors="replace")
    raise ImportError_("The site redirected too many times")


# ---------------------------------------------------------------------------
# HTML reading (standard library parser, no extra packages)
# ---------------------------------------------------------------------------

class _PageReader(HTMLParser):
    TEXT_TAGS = {"h1", "h2", "h3", "p", "li", "a", "button", "span", "title"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.meta: Dict[str, str] = {}
        self.links: List[Dict[str, str]] = []
        self.images: List[Dict[str, Any]] = []
        self.inline_css: List[str] = []
        self.json_ld: List[str] = []
        self.texts: List[Tuple[str, str]] = []   # (tag, text)
        self.nav: List[str] = []
        self.title = ""
        self._stack: List[Tuple[str, Dict[str, str]]] = []
        self._capture: Optional[str] = None
        self._buffer: List[str] = []
        self._in_style = False
        self._in_script_ld = False
        self._in_nav = 0
        self._in_header = 0
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        a = {k.lower(): (v or "") for k, v in attrs}
        if tag in ("script", "noscript", "svg", "template"):
            if tag == "script" and a.get("type", "").lower() == "application/ld+json":
                self._in_script_ld = True
                self._buffer = []
            else:
                self._skip += 1
            return
        if tag == "style":
            self._in_style = True
            self._buffer = []
            return
        if tag == "meta":
            key = (a.get("property") or a.get("name") or "").lower()
            if key and a.get("content"):
                self.meta[key] = a["content"]
            return
        if tag == "link":
            self.links.append(a)
            return
        if tag == "nav":
            self._in_nav += 1
        if tag == "header":
            self._in_header += 1
        if tag == "img":
            info = dict(a)
            info["_in_header"] = self._in_header > 0
            info["_parent_class"] = " ".join(attrs_dict.get("class", "") for _, attrs_dict in self._stack[-3:])
            self.images.append(info)
            return
        if tag in self.TEXT_TAGS and self._skip == 0:
            # Block tags start a new piece of text; inline tags inside one are part of it
            if self._capture is None or tag in ("h1", "h2", "h3", "p", "li", "title"):
                self._flush()
                self._capture = tag
                self._buffer = []
        self._stack.append((tag, a))

    def handle_endtag(self, tag):
        if tag in ("script", "noscript", "svg", "template"):
            if self._in_script_ld and tag == "script":
                self.json_ld.append("".join(self._buffer))
                self._in_script_ld = False
                self._buffer = []
            elif self._skip:
                self._skip -= 1
            return
        if tag == "style":
            self.inline_css.append("".join(self._buffer))
            self._in_style = False
            self._buffer = []
            return
        if tag == "nav" and self._in_nav:
            self._in_nav -= 1
        if tag == "header" and self._in_header:
            self._in_header -= 1
        if tag == self._capture:
            self._flush()
        while self._stack:
            open_tag, _ = self._stack.pop()
            if open_tag == tag:
                break

    def handle_data(self, data):
        if self._in_style or self._in_script_ld:
            self._buffer.append(data)
        elif self._capture and self._skip == 0:
            self._buffer.append(data)

    def _flush(self):
        if not self._capture:
            return
        text = re.sub(r"\s+", " ", "".join(self._buffer)).strip()
        if text:
            if self._capture == "title":
                self.title = self.title or text
            elif (self._in_nav or self._in_header) and self._capture in ("a", "span", "button", "li") and len(text) <= 30:
                self.nav.append(text)
            else:
                self.texts.append((self._capture, text))
        self._capture = None
        self._buffer = []


# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------

HEX_RE = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
RGB_RE = re.compile(r"rgba?\(\s*(\d{1,3})[\s,]+(\d{1,3})[\s,]+(\d{1,3})")
TRIPLET_RE = re.compile(r"^\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})\s*$")
BRAND_PROP_RE = re.compile(r"--[\w-]*(accent|primary|brand|button|btn|link|highlight|theme|main|secondary)[\w-]*\s*:\s*([^;}{]+)", re.I)
SELECTOR_RE = re.compile(r"(\.btn|\.button|button|\.shopify-payment-button|a:hover|\.primary)[^{]{0,80}\{([^}]{0,600})\}", re.I)


def _to_hex(r: int, g: int, b: int) -> str:
    return "#{:02x}{:02x}{:02x}".format(max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))


def _parse_color(value: str) -> Optional[str]:
    value = value.strip()
    m = HEX_RE.search(value)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return "#" + h.lower()
    m = RGB_RE.search(value)
    if m:
        return _to_hex(*(int(x) for x in m.groups()))
    m = TRIPLET_RE.match(value)  # Shopify themes store colours as "18, 18, 18"
    if m:
        return _to_hex(*(int(x) for x in m.groups()))
    return None


def _hls(hex_color: str) -> Tuple[float, float, float]:
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return colorsys.rgb_to_hls(r, g, b)


def _is_neutral(hex_color: str) -> bool:
    h, l, s = _hls(hex_color)
    return s < 0.18 or l > 0.93 or l < 0.06


def _pick_colors(css_blobs: List[str], meta_theme: Optional[str]) -> Dict[str, Any]:
    brand_votes: Counter = Counter()
    all_votes: Counter = Counter()

    for css in css_blobs:
        for _, value in BRAND_PROP_RE.findall(css):
            color = _parse_color(value)
            if color:
                brand_votes[color] += 3
        for _, body in SELECTOR_RE.findall(css):
            for prop in re.findall(r"(?:background(?:-color)?|color|border-color)\s*:\s*([^;]+)", body, re.I):
                color = _parse_color(prop)
                if color:
                    brand_votes[color] += 2
        for m in HEX_RE.finditer(css):
            color = _parse_color(m.group(0))
            if color:
                all_votes[color] += 1

    if meta_theme:
        color = _parse_color(meta_theme)
        if color:
            brand_votes[color] += 4

    accent = None
    for color, _ in brand_votes.most_common():
        if not _is_neutral(color):
            accent = color
            break
    if not accent:
        for color, _ in all_votes.most_common(40):
            if not _is_neutral(color):
                accent = color
                break
    if not accent:
        # A black and white brand: use its darkest button colour
        dark = [c for c, _ in brand_votes.most_common() if _hls(c)[1] < 0.35]
        accent = dark[0] if dark else None

    palette = [c for c, _ in (brand_votes + all_votes).most_common(12)]
    return {"accent": accent, "palette": palette[:8]}


# ---------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------

FONT_FAMILY_RE = re.compile(r"font-family\s*:\s*([^;}{]+)", re.I)
FONT_VAR_RE = re.compile(r"--([\w-]*font[\w-]*)\s*:\s*([^;}{]+)", re.I)
HEADING_WORDS = ("heading", "header", "display", "title", "headline")
GOOGLE_FAMILY_RE = re.compile(r"family=([^&:]+)")


def _clean_font(name: str) -> Optional[str]:
    first = name.split(",")[0].strip().strip("'\"").strip()
    if not first or first.lower() in GENERIC_FONTS or first.startswith("var(") or len(first) > 40:
        return None
    if not re.match(r"^[A-Za-z0-9 ]+$", first):
        return None
    return first


def _font_candidates(css_blobs: List[str], links: List[Dict[str, str]]) -> Dict[str, List[str]]:
    heading: Counter = Counter()
    body: Counter = Counter()

    for link in links:
        href = link.get("href", "")
        if "fonts.googleapis.com" in href:
            for fam in GOOGLE_FAMILY_RE.findall(href):
                name = _clean_font(fam.replace("+", " "))
                if name:
                    heading[name] += 2
                    body[name] += 2

    for css in css_blobs:
        for prop, value in FONT_VAR_RE.findall(css):
            prop = prop.lower()
            if any(word in prop for word in ("size", "weight", "style", "scale", "spacing", "height")):
                continue
            name = _clean_font(value)
            if not name:
                continue
            if any(word in prop for word in HEADING_WORDS):
                heading[name] += 5
            else:
                body[name] += 5
        for m in re.finditer(r"(h1|h2|\.h1|\.h2|\.heading|\.title)[^{]{0,60}\{([^}]{0,400})\}", css, re.I):
            for value in FONT_FAMILY_RE.findall(m.group(2)):
                name = _clean_font(value)
                if name:
                    heading[name] += 3
        for m in re.finditer(r"(body|html)\s*\{([^}]{0,400})\}", css, re.I):
            for value in FONT_FAMILY_RE.findall(m.group(2)):
                name = _clean_font(value)
                if name:
                    body[name] += 3
        for value in FONT_FAMILY_RE.findall(css):
            name = _clean_font(value)
            if name:
                body[name] += 1

    return {"heading": [n for n, _ in heading.most_common(5)], "body": [n for n, _ in body.most_common(5)]}


async def _google_font_spec(client: httpx.AsyncClient, name: str) -> Optional[str]:
    """Return a Google Fonts css2 family spec that works for this font, or None."""
    base = name.strip().replace(" ", "+")
    for spec in (f"{base}:wght@400;600;700", f"{base}:wght@400;700", base):
        try:
            response = await client.get(f"https://fonts.googleapis.com/css2?family={spec}&display=swap")
            if response.status_code == 200 and "@font-face" in response.text:
                return spec
        except httpx.HTTPError:
            return None
    return None


# ---------------------------------------------------------------------------
# Images
# ---------------------------------------------------------------------------

def _best_src(img: Dict[str, Any], page_url: str) -> Tuple[Optional[str], int]:
    """Largest image URL from src / srcset / data-src, with its width (0 if unknown)."""
    best, best_w = None, 0
    srcset = img.get("srcset") or img.get("data-srcset") or ""
    for part in srcset.split(","):
        bits = part.strip().split()
        if not bits:
            continue
        width = 0
        if len(bits) > 1 and bits[1].endswith("w"):
            try:
                width = int(bits[1][:-1])
            except ValueError:
                width = 0
        if width >= best_w:
            best, best_w = bits[0], width
    if not best:
        best = img.get("src") or img.get("data-src") or img.get("data-original")
        try:
            best_w = int(img.get("width") or 0)
        except ValueError:
            best_w = 0
    if not best or best.startswith("data:"):
        return None, 0
    url = urljoin(page_url, best.strip())
    if url.startswith("//"):
        url = "https:" + url
    return url, best_w


def _sized(url: str, width: int = 1800) -> str:
    """Ask Shopify's image CDN for a large JPEG (other hosts: unchanged)."""
    parsed = urlparse(url)
    if "shopify" in (parsed.hostname or "") or "/cdn/shop/" in parsed.path:
        base = re.sub(r"([?&])(width|height|crop|format)=[^&]*", r"\1", url).rstrip("?&")
        joiner = "&" if "?" in base else "?"
        return f"{base}{joiner}width={width}&format=pjpg"
    return url


def _is_logo(img: Dict[str, Any]) -> bool:
    hints = " ".join([img.get("class", ""), img.get("alt", ""), img.get("id", ""), img.get("src", ""),
                      str(img.get("_parent_class", ""))]).lower()
    return "logo" in hints


def _pick_images(reader: _PageReader, page_url: str) -> Dict[str, Any]:
    logo = None
    photos: List[Tuple[str, int]] = []
    seen = set()

    for img in reader.images:
        url, width = _best_src(img, page_url)
        if not url or not url.startswith("http"):
            continue
        lower = url.lower()
        if lower.endswith(".svg") and not _is_logo(img):
            continue
        if any(skip in lower for skip in ("icon", "sprite", "payment", "badge", "pixel", "tracking", "avatar", "spinner")):
            if not _is_logo(img):
                continue
        if not logo and _is_logo(img) and (img.get("_in_header") or len(photos) < 3):
            logo = url
            continue
        if url in seen:
            continue
        seen.add(url)
        photos.append((url, width))

    og = reader.meta.get("og:image") or reader.meta.get("twitter:image")
    if og:
        og = urljoin(page_url, og)
        if og.startswith("//"):
            og = "https:" + og
        if og not in seen:
            photos.insert(0, (og, 1200))

    # Bigger photos first, keeping page order among equals
    photos = sorted(photos, key=lambda p: -min(p[1] or 600, 2000))
    return {"logo": logo, "photos": [_sized(u) for u, _ in photos[:MAX_IMAGES]]}


async def _public_images(urls: List[str]) -> List[str]:
    checks = await asyncio.gather(*(asyncio.to_thread(_public_host, urlparse(u).hostname or "") for u in urls))
    return [u for u, ok in zip(urls, checks) if ok]


# ---------------------------------------------------------------------------
# Words
# ---------------------------------------------------------------------------

def _organization(json_ld: List[str]) -> Dict[str, str]:
    found: Dict[str, str] = {}

    def walk(node):
        if isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, dict):
            kind = node.get("@type")
            kinds = kind if isinstance(kind, list) else [kind]
            if any(k in ("Organization", "Store", "OnlineStore", "LocalBusiness", "WebSite") for k in kinds):
                if node.get("name") and "name" not in found:
                    found["name"] = str(node["name"])
                logo = node.get("logo")
                if isinstance(logo, dict):
                    logo = logo.get("url")
                if isinstance(logo, str) and "logo" not in found:
                    found["logo"] = logo
                if node.get("description") and "description" not in found:
                    found["description"] = str(node["description"])
            for value in node.values():
                if isinstance(value, (dict, list)):
                    walk(value)

    for raw in json_ld:
        try:
            walk(json.loads(raw))
        except (ValueError, TypeError):
            continue
    return found


def _platform(html: str, page_url: str) -> str:
    lower = html.lower()
    if "cdn.shopify.com" in lower or "shopify.theme" in lower or "/cdn/shop/" in lower:
        return "shopify"
    if "woocommerce" in lower or "wp-content" in lower:
        return "woocommerce"
    if "shoper" in lower and ("shoparena" in lower or "shoper.pl" in lower):
        return "shoper"
    if "wix.com" in lower or "wixstatic.com" in lower:
        return "wix"
    if "squarespace" in lower:
        return "squarespace"
    if "bigcommerce" in lower:
        return "bigcommerce"
    return "other"


def _words(reader: _PageReader) -> Dict[str, Any]:
    headings = []
    paragraphs = []
    for tag, text in reader.texts:
        if tag in ("h1", "h2", "h3") and 3 <= len(text) <= 120 and text not in headings:
            headings.append(text)
        elif tag == "p" and 50 <= len(text) <= 600 and text not in paragraphs:
            paragraphs.append(text)
    nav = []
    for item in reader.nav:
        if item not in nav:
            nav.append(item)
    return {"headings": headings[:14], "paragraphs": paragraphs[:8], "nav": nav[:12]}


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

async def read_site(url: str) -> Dict[str, Any]:
    """Read a store's home page and return its brand. Raises ImportError_ with a plain message."""
    url = url.strip()
    if not re.match(r"^https?://", url, re.I):
        url = "https://" + url

    headers = {"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml,text/css;q=0.9,*/*;q=0.8",
               "Accept-Language": "en,*;q=0.5"}
    async with httpx.AsyncClient(timeout=TIMEOUT, headers=headers, follow_redirects=False) as client:
        try:
            final_url, html = await _fetch(client, url, MAX_HTML)
        except ImportError_:
            raise
        except httpx.HTTPError as e:
            raise ImportError_(f"We could not open {urlparse(url).hostname}: {e.__class__.__name__}")

        reader = _PageReader()
        try:
            reader.feed(html)
            reader.close()
        except Exception as e:  # broken HTML should never stop the import
            logger.warning(f"HTML parse problem on {final_url}: {e}")

        if len(reader.texts) < 3 and not reader.images:
            raise ImportError_("The page had almost nothing on it. Is the store password protected?")

        # Stylesheets: inline ones plus the first few linked ones
        css_blobs = list(reader.inline_css)
        style_attrs = re.findall(r'style="([^"]{0,500})"', html)
        css_blobs.extend(style_attrs[:200])
        sheet_urls = []
        for link in reader.links:
            rel = link.get("rel", "").lower()
            href = link.get("href", "")
            if "stylesheet" in rel and href and "fonts.googleapis" not in href:
                sheet_urls.append(urljoin(final_url, href if not href.startswith("//") else "https:" + href))
        for sheet in sheet_urls[:MAX_STYLESHEETS]:
            try:
                _, css = await _fetch(client, sheet, MAX_CSS)
                css_blobs.append(css)
            except Exception as e:
                logger.info(f"Stylesheet skipped ({sheet}): {e}")

        colors = _pick_colors(css_blobs, reader.meta.get("theme-color"))

        candidates = _font_candidates(css_blobs, reader.links)
        fonts: Dict[str, Any] = {}
        for role, names in (("display", candidates["heading"] or candidates["body"]), ("body", candidates["body"])):
            for name in names[:3]:
                spec = await _google_font_spec(client, name)
                if spec:
                    fonts[role] = {"name": name, "spec": spec}
                    break

    org = _organization(reader.json_ld)
    images = _pick_images(reader, final_url)
    logo = images["logo"] or (urljoin(final_url, org["logo"]) if org.get("logo") else None)
    if logo and logo.startswith("//"):
        logo = "https:" + logo
    photos = await _public_images(images["photos"])
    if logo and not (await _public_images([logo])):
        logo = None

    site_name = (reader.meta.get("og:site_name") or org.get("name") or reader.title.split("|")[0].split("–")[0]).strip()
    description = (reader.meta.get("description") or reader.meta.get("og:description") or org.get("description") or "").strip()
    words = _words(reader)

    brand = {
        "source_url": final_url,
        "platform": _platform(html, final_url),
        "site_name": site_name[:80],
        "description": description[:400],
        "logo_url": logo,
        "accent": colors["accent"],
        "palette": colors["palette"],
        "fonts": fonts,
        "language": (re.search(r'<html[^>]*\slang="([a-zA-Z-]{2,10})"', html) or [None, None])[1],
    }
    logger.info(f"Read {final_url}: platform={brand['platform']} accent={brand['accent']} "
                f"fonts={ {k: v['name'] for k, v in fonts.items()} } logo={'yes' if logo else 'no'} photos={len(photos)}")
    return {"brand": brand, "words": words, "photos": photos}


def summary_for_plan(site: Dict[str, Any], store_name: str) -> str:
    """The text given to the page-plan writer: the shop's own words, so the plan reuses them."""
    brand = site["brand"]
    words = site["words"]
    lines = [
        f"This shop already sells online at {urlparse(brand['source_url']).hostname} and is moving to a new platform.",
        "Rebuild its home page with ITS OWN words: reuse its real headlines, product types and story wherever they fit. "
        "Only write new words where the shop has none. Keep the same language the shop uses.",
        f"Shop name: {store_name or brand['site_name']}",
    ]
    if brand.get("description"):
        lines.append(f"Shop description: {brand['description']}")
    if words["nav"]:
        lines.append("Menu: " + ", ".join(words["nav"]))
    if words["headings"]:
        lines.append("Headlines on the current site: " + " | ".join(words["headings"]))
    if words["paragraphs"]:
        lines.append("Text on the current site: " + " ".join(words["paragraphs"][:4]))
    text = "\n".join(lines)
    return text[:1900]
