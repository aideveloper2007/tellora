"""Owner's own design ("Upload my HTML files"): unpacks a ZIP (or one HTML file) safely and asks
Claude to MARK the shop parts of the page, without changing the design.

Returns to Rails:
  index   - path of the home page inside the package (e.g. "index.html")
  files   - every allowed file: path, content type, base64 data
  map     - CSS selectors Rails uses to connect the page to the shop:
            product grid + one card (name, price, old price, image, link), cart / account /
            search / logo links, plus a one-sentence description of the shop

Nothing in the owner's HTML or CSS is rewritten here; Rails does the linking.
"""

import base64
import io
import json
import logging
import mimetypes
import posixpath
import re
import zipfile
from typing import Any, Dict, List, Optional

from app.services.screenshot_design import _ask

logger = logging.getLogger(__name__)

MAX_UPLOAD = 60 * 1024 * 1024        # the ZIP itself
MAX_TOTAL = 200 * 1024 * 1024        # all files unpacked
MAX_FILE = 25 * 1024 * 1024          # one file unpacked
MAX_FILES = 1500
ALLOWED = {
    ".html", ".htm", ".css", ".js", ".mjs", ".json", ".map", ".txt", ".xml",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".svg", ".ico", ".bmp",
    ".woff", ".woff2", ".ttf", ".otf", ".eot",
    ".mp4", ".webm", ".ogg", ".mp3", ".wav", ".pdf",
}
EXTRA_TYPES = {".woff2": "font/woff2", ".woff": "font/woff", ".ttf": "font/ttf", ".otf": "font/otf",
               ".webp": "image/webp", ".avif": "image/avif", ".mjs": "text/javascript", ".js": "text/javascript",
               ".svg": "image/svg+xml", ".map": "application/json"}


class PackageError(Exception):
    """A problem the store owner should see (in plain words)."""


def _content_type(path: str) -> str:
    ext = posixpath.splitext(path)[1].lower()
    return EXTRA_TYPES.get(ext) or mimetypes.guess_type(path)[0] or "application/octet-stream"


def _safe_path(name: str) -> Optional[str]:
    """A clean relative path inside the package, or None for anything unsafe or unwanted."""
    name = name.replace("\\", "/")
    if name.startswith("/") or re.match(r"^[A-Za-z]:", name):
        return None
    parts = [p for p in name.split("/") if p not in ("", ".")]
    if not parts or any(p == ".." for p in parts):
        return None
    if parts[0] == "__MACOSX" or any(p.startswith(".") for p in parts):
        return None
    if posixpath.splitext(parts[-1])[1].lower() not in ALLOWED:
        return None
    return "/".join(parts)


def unpack(filename: str, data: bytes) -> Dict[str, Any]:
    """Unpack the upload. Returns {"index": path, "files": {path: bytes}}."""
    if len(data) > MAX_UPLOAD:
        raise PackageError("The file is larger than 60 MB")

    files: Dict[str, bytes] = {}
    lower = (filename or "").lower()
    if lower.endswith((".html", ".htm")):
        files["index.html"] = data
    else:
        try:
            archive = zipfile.ZipFile(io.BytesIO(data))
        except zipfile.BadZipFile:
            raise PackageError("Upload a .zip file of your site (or a single .html file)")
        entries = [e for e in archive.infolist() if not e.is_dir()]
        if len(entries) > MAX_FILES:
            raise PackageError(f"The ZIP has more than {MAX_FILES} files")
        total = 0
        for entry in entries:
            path = _safe_path(entry.filename)
            if not path:
                continue
            if entry.file_size > MAX_FILE:
                raise PackageError(f"{path} is larger than 25 MB")
            total += entry.file_size
            if total > MAX_TOTAL:
                raise PackageError("The unpacked site is larger than 200 MB")
            with archive.open(entry) as handle:
                content = handle.read(MAX_FILE + 1)
            if len(content) > MAX_FILE:
                raise PackageError(f"{path} is larger than 25 MB")
            files[path] = content

        # Drop one common top folder ("mysite/index.html" -> "index.html")
        tops = {p.split("/")[0] for p in files}
        if len(tops) == 1 and all("/" in p for p in files):
            top = next(iter(tops)) + "/"
            files = {p[len(top):]: c for p, c in files.items()}

    pages = sorted((p for p in files if p.lower().endswith((".html", ".htm"))), key=lambda p: (p.count("/"), p))
    if not pages:
        raise PackageError("No .html page was found in the upload")
    index = next((p for p in pages if posixpath.basename(p).lower() in ("index.html", "index.htm")), pages[0])
    return {"index": index, "files": files}


def _outline(html: str, limit: int = 60000) -> str:
    """The page structure for Claude: tags, ids and classes kept; scripts, styles and long texts trimmed."""
    html = re.sub(r"<!--.*?-->", "", html, flags=re.S)
    html = re.sub(r"<(script|style|noscript)\b[^>]*>.*?</\1\s*>", r"<\1></\1>", html, flags=re.S | re.I)
    html = re.sub(r"<svg\b[^>]*>.*?</svg\s*>", "<svg></svg>", html, flags=re.S | re.I)
    html = re.sub(r"\s(srcset|sizes|style|data-[a-z-]*src[a-z-]*)\s*=\s*(\"[^\"]*\"|'[^']*')", "", html, flags=re.I)
    html = re.sub(r">([^<]{120,})<", lambda m: ">" + m.group(1)[:100] + "…<", html)
    html = re.sub(r"\s+", " ", html)
    return html[:limit]


MAP_PROMPT = """Below is the HTML of an online store's home page, made by the owner's designer (scripts, styles and
long texts are trimmed). We will NOT change the design. We only need CSS selectors so the shop can connect
real data to it. Answer ONLY with this JSON (use null when something does not exist):

{
  "product_grid": "selector of the ONE element that directly contains the product cards (products with prices, not categories)",
  "product_card": "selector of one card, relative to product_grid (e.g. \\":scope > .card\\")",
  "card_name": "selector inside the card of the product name text",
  "card_price": "selector inside the card of the current price text",
  "card_compare_price": "selector inside the card of the old (crossed out) price, or null",
  "card_sale_label": "selector inside the card of a sale / promotion badge, or null",
  "card_image": "selector inside the card of the main product <img>",
  "card_link": "selector inside the card of the link to the product (or null)",
  "card_button": "selector inside the card of an add to cart / buy button (or null)",
  "cart_link": "selector of the cart / basket link or button in the header",
  "account_link": "selector of the account / login link",
  "search_link": "selector of the search link or button",
  "logo_link": "selector of the logo link",
  "description": "one sentence: what the shop sells, in the page's language"
}

Selectors must be valid CSS that matches in this HTML (prefer ids and specific classes).

HTML:
"""


def map_page(html: str) -> Dict[str, Any]:
    """Ask Claude for the selectors. Never raises: an empty map just means 'show the page as it is'."""
    try:
        answer = _ask([{"type": "text", "text": MAP_PROMPT + _outline(html)}], max_tokens=1500)
        match = re.search(r"\{.*\}", answer, re.S)
        value = json.loads(match.group(0)) if match else {}
        if not isinstance(value, dict):
            return {}
        return {k: (v.strip() if isinstance(v, str) and v.strip() else None) for k, v in value.items()
                if k in MAP_KEYS}
    except Exception as e:  # noqa: BLE001
        logger.warning(f"[design-package] page map failed: {e}")
        return {}


MAP_KEYS = ("product_grid", "product_card", "card_name", "card_price", "card_compare_price", "card_sale_label",
            "card_image", "card_link", "card_button", "cart_link", "account_link", "search_link", "logo_link",
            "description")


def build_package(filename: str, data: bytes) -> Dict[str, Any]:
    package = unpack(filename, data)
    index_html = package["files"][package["index"]].decode("utf-8", errors="replace")
    page_map = map_page(index_html)
    logger.info(f"[design-package] {len(package['files'])} files, index {package['index']}, "
                f"grid {'found' if page_map.get('product_grid') else 'not found'}")
    return {
        "index": package["index"],
        "map": page_map,
        "files": [{"path": path, "content_type": _content_type(path), "data": base64.b64encode(content).decode()}
                  for path, content in package["files"].items()],
    }
