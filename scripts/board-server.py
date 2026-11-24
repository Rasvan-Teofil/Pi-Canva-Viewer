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
import subprocess
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BOARD_DIR = REPO / "board"
CEC_SCRIPT = REPO / "scripts" / "cec-control.sh"
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

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/board-config.js":
            body = ("window.PI_SCREEN_BOARD_CONFIG = %s;\n"
                    % json.dumps({"showTestButtons": show_test_buttons()})).encode("utf-8")
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
