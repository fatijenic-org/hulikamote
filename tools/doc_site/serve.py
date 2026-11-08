"""
serve.py - show the documentation site on this computer and let its Q&A page save to a local JSON file.

    hulikamote_backend/venv/Scripts/python.exe tools/doc_site/serve.py            # then open http://127.0.0.1:8770/5-qa.html
    hulikamote_backend/venv/Scripts/python.exe tools/doc_site/serve.py --open     # also opens the browser
    hulikamote_backend/venv/Scripts/python.exe tools/doc_site/serve.py --port 9000

Why a server: a web page cannot write files by itself. This tiny server (standard library only) serves docs/documentation_site/
and offers ONE job: GET / PUT /api/qa, which reads / writes tools/doc_site/data/qa.json.

Safety:
  - it listens on 127.0.0.1 only (this computer; nothing is reachable from the network)
  - it writes only qa.json, after checking the shape of the data, and keeps the previous version as qa.json.bak
  - a write needs a custom header and a same-origin request, so another website open in your browser cannot write to it
  - nothing is uploaded anywhere. The data folder is git-ignored; copy qa.json yourself if you want a backup.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
import threading
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
SITE = HERE.parents[1] / "docs" / "documentation_site"
DATA = HERE / "data" / "qa.json"
SEED = HERE / "qa_seed.json"
MAX_BYTES = 2_000_000
API = "/api/qa"
LOCK = threading.Lock()


def check(doc) -> str | None:
    """None when the data has the shape the Q&A page writes, otherwise a short reason."""
    if not isinstance(doc, dict) or doc.get("version") != 1 or not isinstance(doc.get("items"), list):
        return "expected {version: 1, items: [...]}"
    if len(doc["items"]) > 2000:
        return "too many items"
    seen = set()
    for item in doc["items"]:
        if not isinstance(item, dict):
            return "an item is not an object"
        for key in ("id", "q", "a", "created", "updated"):
            if not isinstance(item.get(key), str):
                return f"item field '{key}' must be text"
        tags = item.get("tags")
        if not isinstance(tags, list) or not all(isinstance(t, str) for t in tags):
            return "item field 'tags' must be a list of text"
        if item["id"] in seen:
            return "duplicate id"
        seen.add(item["id"])
        if len(item["q"]) > 5000 or len(item["a"]) > 100_000:
            return "a question or answer is too long"
    return None


def ensure_data() -> None:
    DATA.parent.mkdir(parents=True, exist_ok=True)
    if not DATA.exists():
        shutil.copyfile(SEED, DATA)
        print(f"Created {DATA} from the starter questions.")


def write_atomic(text: str) -> None:
    """Write to a temp file in the same folder, keep the old file as .bak, then swap it in."""
    fd, tmp = tempfile.mkstemp(dir=DATA.parent, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        if DATA.exists():
            shutil.copyfile(DATA, DATA.with_suffix(".json.bak"))
        os.replace(tmp, DATA)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(SITE), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")      # a rebuilt page shows up at once
        super().end_headers()

    def _send(self, code: int, payload: dict | bytes, content_type: str = "application/json") -> None:
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", content_type + "; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.split("?")[0] == API:
            with LOCK:
                self._send(200, DATA.read_bytes())
            return
        super().do_GET()

    def do_PUT(self):
        if self.path.split("?")[0] != API:
            self._send(404, {"error": "not found"})
            return
        port = self.server.server_port
        origin = self.headers.get("Origin")
        if self.headers.get("X-HK-QA") != "1" or (origin and origin not in (f"http://127.0.0.1:{port}", f"http://localhost:{port}")):
            self._send(403, {"error": "forbidden"})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BYTES:
            self._send(413, {"error": f"body must be 1..{MAX_BYTES} bytes"})
            return
        try:
            doc = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send(400, {"error": "not valid JSON"})
            return
        problem = check(doc)
        if problem:
            self._send(400, {"error": problem})
            return
        with LOCK:
            write_atomic(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
        self._send(200, {"ok": True, "items": len(doc["items"])})

    def log_message(self, fmt, *args):                     # one short line per request, no client address noise
        sys.stderr.write("  " + (fmt % args) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8770)
    ap.add_argument("--open", action="store_true", help="open the Q&A page in the browser")
    args = ap.parse_args()
    if not SITE.exists():
        print(f"{SITE} does not exist. Build the site first: python tools/doc_site/build_site.py")
        return 1
    ensure_data()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/5-qa.html"
    print(f"Documentation site: {url}\nQ&A data file:      {DATA}\nPress Ctrl+C to stop.")
    if args.open:
        webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
