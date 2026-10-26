import json
import re
import threading
from pathlib import Path
from typing import Any, Dict

BASE_DIR = Path(__file__).resolve().parent.parent
CONFIG_FILE = BASE_DIR / "config" / "dashboard_data.json"
CANVA_URL_FILE = BASE_DIR / "canva_url.txt"

_LOCK = threading.RLock()


def to_canva_embed_url(raw_url: str) -> str:
    """Convert a standard Canva design link (/edit or /view) into an embeddable /view?embed URL."""
    url = (raw_url or "").strip()
    if not url:
        return ""
    if "canva.com/design/" in url:
        base = re.sub(r"/(edit|view|watch)(\?.*)?$", "", url)
        return f"{base}/view?embed"
    return url


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
        return data


def save_config(data: Dict[str, Any]) -> Dict[str, Any]:
    with _LOCK:
        canva_cfg = data.get("canva", {})
        raw_url = (canva_cfg.get("url") or "").strip()
        if raw_url:
            canva_cfg["embed_url"] = to_canva_embed_url(raw_url)
            CANVA_URL_FILE.write_text(raw_url + "\n", encoding="utf-8")

        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        return data
