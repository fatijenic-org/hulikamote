"""
server.py - HTTP layer of the Dataset Viewer (stdlib only, 127.0.0.1 only, random per-run token).

Same pattern as harvest_tool/web.py: Host must be loopback, every /api call needs the token
(?t=... or the X-Viewer-Token header), /api/ping tells the dashboard the helper is alive and which API it speaks.
"""
from __future__ import annotations

import json
import mimetypes
import os
import secrets
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from . import app as logic
from .app import API_VERSION, IndexNotReady, NeedsConfirm, NotFound, TrainingBusy, ViewerApp, ViewerError

PAGE = Path(__file__).with_name("page.html")
MAX_BODY = 4_000_000
HEADER = "X-Viewer-Token"


def make_handler(viewer: ViewerApp, token: str, touch):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        timeout = 60

        def log_message(self, *a):
            pass

        # ---- plumbing
        def _allowed(self, q: dict) -> bool:
            host = (self.headers.get("Host") or "").rsplit(":", 1)[0].strip("[]")
            if host not in ("127.0.0.1", "localhost"):
                return False
            given = (q.get("t") or [""])[0] or self.headers.get(HEADER, "")
            return secrets.compare_digest(given.encode(), token.encode())

        def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None):
            try:
                self.send_response(code)
                self.send_header("Content-Type", ctype)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store" if ctype.startswith(("application/json", "text/html")) else "private, max-age=3600")
                self.send_header("X-Content-Type-Options", "nosniff")
                for k, v in (extra or {}).items():
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                self.close_connection = True

        def _json(self, code: int, obj):
            self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"), "application/json; charset=utf-8")

        def _file(self, path: Path):
            ctype = logic.MIME.get(path.suffix.lower()) or mimetypes.guess_type(path.name)[0] or "application/octet-stream"
            try:
                self._send(200, path.read_bytes(), ctype)
            except OSError:
                self._json(404, {"error": "file not found"})

        def _fail(self, e: Exception):
            if isinstance(e, NeedsConfirm):
                self._json(409, {"error": str(e), "needs_confirm": e.kind, "detail": e.detail})
            elif isinstance(e, TrainingBusy):
                self._json(409, {"error": str(e), "training": True})
            elif isinstance(e, IndexNotReady):
                self._json(503, {"error": str(e), "indexing": True, "progress": e.progress})
            elif isinstance(e, NotFound):
                self._json(404, {"error": str(e)})
            elif isinstance(e, ViewerError):
                self._json(400, {"error": str(e)})
            else:
                self._json(500, {"error": f"{type(e).__name__}: {e}"})

        # ---- routing
        def do_GET(self):
            u = urlparse(self.path)
            q = parse_qs(u.query)
            touch()
            if u.path in ("/", "/index.html"):
                if not self._allowed(q):
                    return self._send(403, b"Open this page from the link the helper printed (it carries the token).", "text/plain")
                html = PAGE.read_text(encoding="utf-8").replace("__TOKEN__", token)
                return self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
            if not u.path.startswith("/api/") or not self._allowed(q):
                return self._json(403, {"error": "forbidden"})
            p = {k: v[0] for k, v in q.items()}
            try:
                self._get(u.path, p)
            except Exception as e:
                self._fail(e)

        def _get(self, path: str, p: dict):
            v = viewer
            if path == "/api/ping":
                return self._json(200, {"ok": True, "api": API_VERSION})
            if path == "/api/datasets":
                rows = v.list_datasets()
                if v.reid.images.is_dir():
                    rows.append(v.reid.entry())
                return self._json(200, {"datasets": rows})
            if path.startswith("/api/reid/"):
                return self._get_reid(path[len("/api/reid/"):], p)
            if path == "/api/overview":
                return self._json(200, v.overview(p.get("dataset")))
            if path == "/api/sizes":
                return self._json(200, v.start_sizes(v.model(p.get("dataset"))))
            if path == "/api/facets":
                return self._json(200, v.facets(p.get("dataset"), p.get("split")))
            if path == "/api/items":
                return self._json(200, {**v.items(p.get("dataset"), p), "can_undo": v.can_undo(p.get("dataset"))})
            if path == "/api/keys":
                return self._json(200, v.keys(p.get("dataset"), p))
            if path == "/api/item":
                return self._json(200, v.item(p.get("dataset"), p.get("split"), p.get("name")))
            if path == "/api/labels":
                return self._json(200, v.label_items(p.get("dataset"), p))
            if path == "/api/thumb":
                return self._file(v.thumb_of_item(p.get("dataset"), p.get("split"), p.get("name")))
            if path == "/api/crop":
                return self._file(v.crop_of_item(p.get("dataset"), p.get("split"), p.get("name"), p.get("i")))
            if path == "/api/image":
                return self._file(v.image_file(p.get("dataset"), p.get("split"), p.get("name")))
            if path == "/api/qthumb":
                return self._file(v.thumb_of_quarantined(p.get("dataset"), p.get("reason"), p.get("name")))
            if path == "/api/qimage":
                return self._file(v.quarantine_file(p.get("dataset"), p.get("reason"), p.get("name")))
            if path == "/api/about":
                return self._json(200, v.about(p.get("dataset")))
            if path == "/api/quarantine":
                return self._json(200, v.quarantine_list(p.get("dataset"), p.get("reason"),
                                                         int(p.get("offset") or 0), int(p.get("limit") or 150)))
            if path == "/api/job":
                return self._json(200, v.job(p.get("id", "")))
            if path == "/api/progress":
                return self._json(200, v.progress(v.model(p.get("dataset"))))
            self._json(404, {"error": "no such endpoint"})

        def _get_reid(self, what: str, p: dict):
            r = viewer.reid
            if what == "summary":
                return self._json(200, r.summary())
            if what == "cars":
                return self._json(200, r.cars(p.get("analysis") or None, p.get("filter") or "all", p.get("q") or ""))
            if what == "car":
                return self._json(200, r.car(p.get("key")))
            if what == "photo":
                return self._file(r.photo_file(p.get("key"), p.get("name"), p.get("thumb") == "1"))
            if what == "removed":
                return self._json(200, r.removed())
            if what == "removed_photo":
                return self._file(r.removed_file(p.get("reason"), p.get("analysis"), p.get("car"), p.get("name"), p.get("thumb") == "1"))
            if what == "job":
                return self._json(200, r.job(p.get("id", "")))
            self._json(404, {"error": "no such endpoint"})

        def do_POST(self):
            u = urlparse(self.path)
            q = parse_qs(u.query)
            touch()
            if not u.path.startswith("/api/") or not self._allowed(q):
                return self._json(403, {"error": "forbidden"})
            try:
                length = int(self.headers.get("Content-Length") or 0)
                if length > MAX_BODY:
                    return self._json(413, {"error": "body too large"})
                body = json.loads(self.rfile.read(length) or b"{}")
                if not isinstance(body, dict):
                    raise ViewerError("body must be a JSON object")
                self._post(u.path, body)
            except ValueError as e:
                self._fail(e if isinstance(e, ViewerError) else ViewerError(f"bad JSON: {e}"))
            except Exception as e:
                self._fail(e)

        def _post_reid(self, what: str, b: dict):
            r = viewer.reid
            if what == "move":
                return self._json(200, r.move(b.get("photos"), b.get("to")))
            if what == "merge":
                return self._json(200, r.merge(b.get("cars"), b.get("into")))
            if what == "remove":
                return self._json(200, r.remove(b.get("photos"), b.get("reason") or "removed_in_manager"))
            if what == "remove_cars":
                return self._json(200, r.remove_cars(b.get("cars"), b.get("reason") or "removed_in_manager"))
            if what == "restore":
                return self._json(200, r.restore(b.get("items")))
            if what == "dismiss":
                return self._json(200, r.dismiss(b.get("a"), b.get("b")))
            if what == "undo":
                return self._json(200, r.undo())
            if what == "scan":
                return self._json(200, r.start_scan())
            self._json(404, {"error": "no such endpoint"})

        def _post(self, path: str, b: dict):
            if path.startswith("/api/reid/"):
                return self._post_reid(path[len("/api/reid/"):], b)
            v, ds = viewer, b.get("dataset")
            ch = bool(b.get("confirm_harvest"))
            if path == "/api/quarantine":
                return self._json(200, v.quarantine(ds, b.get("items"), ch))
            if path == "/api/restore":
                return self._json(200, v.restore(ds, b.get("reason"), b.get("items"), ch, bool(b.get("confirm_leak"))))
            if path == "/api/flag":
                return self._json(200, v.set_flag(ds, b.get("items"), bool(b.get("value", True))))
            if path == "/api/box":
                return self._json(200, v.edit_box(ds, b.get("split"), b.get("name"), b.get("i"), b.get("cls"),
                                                  bool(b.get("remove")), ch))
            if path == "/api/relabel/preview":
                return self._json(200, v.preview_relabel(ds, b.get("items"), b.get("rule"), b.get("class_id")))
            if path == "/api/relabel":
                return self._json(200, v.relabel(ds, b.get("class_id"), b.get("items"), b.get("rule"), ch))
            if path == "/api/undo":
                return self._json(200, v.undo(ds))
            if path == "/api/report":
                return self._json(200, v.start_report(ds))
            if path == "/api/notes":
                return self._json(200, v.save_notes(ds, b.get("text")))
            if path == "/api/reveal":
                return self._json(200, v.reveal(ds, b.get("split"), b.get("name")))
            if path == "/api/refresh":
                return self._json(200, v.refresh(ds))
            if path == "/api/clean":
                return self._json(200, v.start_clean(ds))
            if path == "/api/clean/apply":
                return self._json(200, v.apply_clean(ds, b.get("confirm") is True))
            self._json(404, {"error": "no such endpoint"})

    return Handler


def make_server(viewer: ViewerApp, port: int = 0, token: str | None = None):
    token = token or secrets.token_urlsafe(24)
    last = [time.time()]
    srv = ThreadingHTTPServer(("127.0.0.1", port), make_handler(viewer, token, lambda: last.__setitem__(0, time.time())))
    srv.daemon_threads = True
    srv.token, srv.last_touch = token, last
    return srv


def serve(port: int = 8766, open_browser: bool = True, idle_exit_min: float = 0) -> None:
    viewer = ViewerApp()
    try:
        srv = make_server(viewer, port)
    except OSError:                                              # port taken: let the OS pick one
        srv = make_server(viewer, 0)
    port = srv.server_address[1]
    url = f"http://127.0.0.1:{port}/?t={srv.token}"
    info = viewer.cache / "server.json"
    info.write_text(json.dumps({"url": url, "port": port, "pid": os.getpid(), "api": API_VERSION}), encoding="utf-8")
    print(f"Dataset Viewer: {url}", flush=True)
    for m in viewer.models():                                    # warm the indexes while the browser opens
        viewer.start_indexing(m)

    if idle_exit_min:
        def watch():
            while True:
                time.sleep(30)
                if time.time() - srv.last_touch[0] > idle_exit_min * 60:
                    srv.shutdown()
                    return
        threading.Thread(target=watch, daemon=True).start()
    if open_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        viewer.flush()
        try:
            info.unlink()
        except OSError:
            pass
        srv.server_close()
