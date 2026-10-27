import json
import re
import threading
from pathlib import Path
from typing import Any, Dict
from urllib.parse import urlparse, urlunparse

BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_FILE = BASE_DIR / "config" / "dashboard_data.json"
CANVA_URL_FILE = BASE_DIR / "canva_url.txt"

_LOCK = threading.RLock()

_HEX32_RE = re.compile(
    r"([0-9a-fA-F]{32}|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"
)


def to_canva_embed_url(raw_url: str) -> str:
    """Convert a standard Canva design link (/edit or /view) into an embeddable /view?embed URL."""
    url = (raw_url or "").strip()
    if not url:
        return ""
    if "canva.com/design/" in url:
        base = re.sub(r"/(edit|view|watch)(\?.*)?$", "", url)
        return f"{base}/view?embed"
    return url


def to_notion_embed_url(raw_input: str, default_subdomain: str = "icfhn") -> str:
    """
    Convert any published Notion database/page URL or <iframe> snippet into an
    embeddable https://<workspace>.notion.site/ebd/<32hex_id>?v=<view_id> URL
    that sends 'frame-ancestors https: http:' instead of 'x-frame-options: SAMEORIGIN'.
    Non-Notion URLs are returned unchanged so any custom web embed works too.
    """
    text = (raw_input or "").strip()
    if not text:
        return ""

    # 1. If the user pasted a full <iframe ... src="..."> snippet, extract src
    if "<iframe" in text.lower():
        m = re.search(r'src=["\']([^"\']+)["\']', text, flags=re.IGNORECASE)
        if m:
            text = m.group(1).strip()

    parsed = urlparse(text)
    host = (parsed.netloc or "").lower()
    if not host:
        return text

    is_notion = (
        host.endswith(".notion.site")
        or host in ("notion.site", "www.notion.so", "notion.so", "app.notion.com")
    )
    if not is_notion:
        return text

    subdomain = (default_subdomain or "icfhn").strip().lower()
    segments = [s for s in parsed.path.split("/") if s]

    # 2. Determine the .notion.site host
    if host.endswith(".notion.site"):
        target_host = host
    else:
        if (
            len(segments) >= 2
            and segments[0].lower() not in ("p", "ebd")
            and not _HEX32_RE.search(segments[0])
        ):
            target_host = f"{segments[0].lower()}.notion.site"
        else:
            target_host = f"{subdomain}.notion.site"

    # 3. Extract the 32-hex page/database ID and build /ebd/<id> path
    if segments and segments[0].lower() == "ebd" and len(segments) >= 2:
        id_match = _HEX32_RE.search(segments[1])
        if id_match:
            clean_id = id_match.group(1).replace("-", "").lower()
            target_path = f"/ebd/{clean_id}"
        else:
            target_path = parsed.path
    else:
        id_match = _HEX32_RE.search(parsed.path)
        if id_match:
            clean_id = id_match.group(1).replace("-", "").lower()
            target_path = f"/ebd/{clean_id}"
        else:
            target_path = parsed.path

    return urlunparse(("https", target_host, target_path, "", parsed.query, ""))


def load_config() -> Dict[str, Any]:
    with _LOCK:
        if not CONFIG_FILE.exists():
            raise FileNotFoundError(f"Configuration file missing: {CONFIG_FILE}")
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)

        # Sync from canva_url.txt if it was modified externally and differs
        if CANVA_URL_FILE.exists():
            txt_url = CANVA_URL_FILE.read_text(encoding="utf-8").strip()
            if txt_url and txt_url != "https://www.canva.com/design/LINK":
                if data.get("canva", {}).get("url") != txt_url:
                    data.setdefault("canva", {})["url"] = txt_url
                    data["canva"]["embed_url"] = to_canva_embed_url(txt_url)

        # Ensure notion_view has a computed embed_url
        notion_view = data.get("notion_view")
        if isinstance(notion_view, dict) and notion_view.get("url"):
            sub = notion_view.get("subdomain") or "icfhn"
            notion_view["embed_url"] = to_notion_embed_url(notion_view["url"], sub)

        return data


def save_config(data: Dict[str, Any]) -> Dict[str, Any]:
    with _LOCK:
        canva_cfg = data.get("canva", {})
        raw_url = (canva_cfg.get("url") or "").strip()
        if raw_url:
            canva_cfg["embed_url"] = to_canva_embed_url(raw_url)
            CANVA_URL_FILE.write_text(raw_url + "\n", encoding="utf-8")

        notion_view = data.get("notion_view")
        if isinstance(notion_view, dict) and notion_view.get("url"):
            sub = notion_view.get("subdomain") or "icfhn"
            notion_view["embed_url"] = to_notion_embed_url(notion_view["url"], sub)

        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        return data
