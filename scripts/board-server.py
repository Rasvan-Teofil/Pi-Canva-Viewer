#!/usr/bin/env python3
"""Pi-Screen Board-Server (Stufe 1).

Liefert board/ auf http://127.0.0.1:8787/ aus und bietet für die
temporären Testbuttons:
  POST /tv/on   -> cec-control.sh on
  POST /tv/off  -> cec-control.sh off
  GET  /tv/status
Nur stdlib, lauscht ausschließlich auf 127.0.0.1.
"""
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BOARD_DIR = REPO / "board"
CEC_SCRIPT = REPO / "scripts" / "cec-control.sh"
FONT_DIR = Path(os.environ.get("PI_SCREEN_FONT_DIR",
                               Path.home() / ".config" / "pi-screen" / "fonts"))
FONT_TYPES = {".otf": "font/otf", ".ttf": "font/ttf", ".woff": "font/woff", ".woff2": "font/woff2"}
CONFIG_FILE = Path(os.environ.get("PI_SCREEN_BOARD_CONFIG",
                                  Path.home() / ".config" / "pi-screen" / "board.env"))


def read_env(path):
    values = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            values[key.strip()] = val.strip().strip("'\"")
    except OSError:
        pass
    return values


def show_test_buttons():
    return read_env(CONFIG_FILE).get("SHOW_TEST_BUTTONS", "false").lower() in ("1", "true", "yes", "on")


DEFAULT_CANVA_URL = "https://www.canva.com/design/DAGeJOlW_fg/dcvDxGynTmQVinQOyVVR2Q/view"
_canva_cache = {"url": None, "at": 0.0, "pages": 0}


def canva_embed_url(env):
    """Beliebigen Canva-Link (edit/view/watch) oder ID+Token in die ?embed-Form bringen."""
    url = env.get("CANVA_URL", "").strip()
    if not url and env.get("CANVA_DESIGN_ID"):
        url = "https://www.canva.com/design/%s/%s/view" % (
            env["CANVA_DESIGN_ID"].strip(), env.get("CANVA_VIEW_TOKEN", "").strip())
    url = url or DEFAULT_CANVA_URL
    m = re.search(r"canva\.com/design/([^/?#]+)(?:/([^/?#]+))?", url)
    if not m:
        return url
    parts = ["https://www.canva.com/design", m.group(1)]
    if m.group(2) and m.group(2) not in ("view", "edit", "watch"):
        parts.append(m.group(2))
    return "/".join(parts) + "/view?embed"


def canva_pages(url):
    """Seitenzahl aus dem öffentlichen Embed-HTML lesen (10 min Cache, 0 = unbekannt)."""
    now = time.time()
    if _canva_cache["url"] == url and now - _canva_cache["at"] < 600 and _canva_cache["pages"]:
        return _canva_cache["pages"]
    pages = 0
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux aarch64) Chrome/130"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            html = resp.read().decode("utf-8", "replace")
        ids = re.findall(r'"A\?":"i","a":"(P[A-Za-z0-9_-]{15})"', html)
        pages = len(dict.fromkeys(ids))
    except Exception as exc:  # offline, Canva-Änderung o. Ä.
        sys.stderr.write("board-server: Canva-Seitenzahl nicht lesbar: %s\n" % exc)
    _canva_cache.update(url=url, at=now, pages=pages)
    return pages


def looker_embed_url(env):
    """Looker-Studio-Link (reporting/embed, alte datastudio-Domain) in die /embed/-Form bringen."""
    url = env.get("LOOKER_URL", "").strip()
    if not url:
        return ""
    m = re.search(r"/reporting/([0-9a-fA-F-]{20,})(?:/page/([^/?#]+))?", url)
    if not m:
        return url
    out = "https://lookerstudio.google.com/embed/reporting/" + m.group(1)
    if m.group(2):
        out += "/page/" + m.group(2)
    return out


_looker_cache = {"url": None, "at": 0.0, "ok": None}


def looker_access(url):
    """Grobe Prüfung: lädt der Embed-Link ohne Google-Login? (10 min Cache, None = unbekannt)"""
    now = time.time()
    if _looker_cache["url"] == url and now - _looker_cache["at"] < 600:
        return _looker_cache["ok"]
    ok = None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux aarch64) Chrome/130"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            final = resp.geturl()
            ok = resp.status == 200 and "accounts.google.com" not in final
    except urllib.error.HTTPError:
        ok = False
    except Exception as exc:
        sys.stderr.write("board-server: Looker nicht prüfbar: %s\n" % exc)
    _looker_cache.update(url=url, at=now, ok=ok)
    return ok


def board_config():
    env = read_env(CONFIG_FILE)
    def num(key, default):
        try:
            return float(env.get(key, default))
        except ValueError:
            return default
    return {
        "showTestButtons": env.get("SHOW_TEST_BUTTONS", "false").lower() in ("1", "true", "yes", "on"),
        "startView": env.get("START_VIEW", "board").strip() or "board",
        "canvaEmbedUrl": canva_embed_url(env),
        "canvaSlideSeconds": num("CANVA_SLIDE_SECONDS", 10),
        "canvaPages": int(num("CANVA_PAGES", 0)),
        "canvaReloadMinutes": num("CANVA_RELOAD_MINUTES", 30),
        "views": [v.strip() for v in env.get("VIEWS", "board,canva,looker").split(",") if v.strip()],
        "lookerEmbedUrl": looker_embed_url(env),
        "lookerPages": [p.strip() for p in env.get("LOOKER_PAGES", "").split(",") if p.strip()],
        "lookerPageSeconds": num("LOOKER_PAGE_SECONDS", 30),
        "lookerReloadMinutes": num("LOOKER_RELOAD_MINUTES", 10),
    }


def run_cec(action):
    try:
        proc = subprocess.run([str(CEC_SCRIPT), action], capture_output=True, text=True, timeout=20)
        out = (proc.stdout + proc.stderr).strip()
        return proc.returncode == 0, out[-2000:]
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, str(exc)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BOARD_DIR), **kwargs)

    def log_message(self, fmt, *args):
        sys.stderr.write("board-server: " + (fmt % args) + "\n")

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _font(self, name):
        """Lizenzierte Schriften aus ~/.config/pi-screen/fonts (nicht im Repo). Nur reine Dateinamen."""
        ctype = FONT_TYPES.get(os.path.splitext(name)[1].lower())
        if not ctype or not re.fullmatch(r"[A-Za-z0-9._-]+", name) or name.startswith("."):
            self._json(404, {"ok": False})
            return
        try:
            data = (FONT_DIR / name).read_bytes()
        except OSError:
            self._json(404, {"ok": False})
            return
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/board-config.js":
            body = ("window.PI_SCREEN_BOARD_CONFIG = %s;\n"
                    % json.dumps(board_config())).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/javascript; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path == "/tv/status":
            ok, out = run_cec("status")
            self._json(200 if ok else 500, {"ok": ok, "output": out})
            return
        if path == "/canva/info":
            url = board_config()["canvaEmbedUrl"]
            self._json(200, {"url": url, "pages": canva_pages(url)})
            return
        if path == "/looker/info":
            url = board_config()["lookerEmbedUrl"]
            self._json(200, {"url": url, "ok": looker_access(url) if url else None})
            return
        if path.startswith("/fonts/"):
            self._font(path[len("/fonts/"):])
            return
        if path == "/health":
            self._json(200, {"ok": True})
            return
        super().do_GET()

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path in ("/tv/on", "/tv/off"):
            if not show_test_buttons():
                self._json(403, {"ok": False, "error": "SHOW_TEST_BUTTONS ist aus"})
                return
            ok, out = run_cec(path.rsplit("/", 1)[1])
            self._json(200 if ok else 500, {"ok": ok, "output": out})
            return
        self._json(404, {"ok": False, "error": "unbekannt"})


def main():
    port = int(os.environ.get("PI_SCREEN_BOARD_PORT") or read_env(CONFIG_FILE).get("BOARD_PORT", "8787"))
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    sys.stderr.write("board-server: http://127.0.0.1:%d/ (%s)\n" % (port, BOARD_DIR))
    server.serve_forever()


if __name__ == "__main__":
    main()
