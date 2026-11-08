"""
web.py - The check & label page: a tiny local web server (127.0.0.1 only) plus page.html.

Everything stays on this computer. Every request needs the one-time token printed in the
URL, so another web page open in your browser cannot talk to it.
"""
import json
import os
import re
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from . import config
from .accept import TrainingBusy, accept, training_models
from .cars import car_counts, car_detail, car_list, check_car, fill_cars
from .collect import COLLECT_VERSION, collect, refresh_suggestions
from .config import AUTOMATIC, CLASS_COLORS, CLASS_HELP, MODELS, Paths, active_onnx, class_names
from .frames import task_video
from .pairs import answer_pair
from .sources import load_protected, review_counts
from .store import Store, clean_boxes

API_VERSION = 4        # the dashboard asks /api/ping and restarts a helper that is older than it needs

PAGE = Path(__file__).with_name("page.html")
ID_RE = re.compile(r"^[0-9a-f]{16}$")
TASK_RE = re.compile(r"^[0-9A-Za-z_-]{1,64}$")      # an analysis id; it becomes a folder name, so nothing else is allowed
_COUNT_CACHE: dict = {}


def _count_files(folder: Path, ttl: float = 120.0) -> int:
    hit = _COUNT_CACHE.get(str(folder))
    if hit and time.time() - hit[0] < ttl:
        return hit[1]
    n = 0
    if folder.exists():
        with os.scandir(folder) as it:
            n = sum(1 for e in it if e.is_file())
    _COUNT_CACHE[str(folder)] = (time.time(), n)
    return n


def dataset_size(paths: Paths, model: str) -> int:
    import yaml
    try:
        cfg = yaml.safe_load((paths.datasets / model / "data.yaml").read_text(encoding="utf-8"))
        total = 0
        for key in ("train", "val"):
            if cfg.get(key):
                total += _count_files(paths.datasets / model / cfg[key])
        return total
    except Exception:
        return 0


def reid_cars(paths: Paths) -> int:
    """Cars with at least 2 photos (the matcher needs 5+)."""
    root = paths.datasets / "reid" / "images"
    n = 0
    if not root.exists():
        return 0
    for task in root.iterdir():
        if task.is_dir():
            n += sum(1 for car in task.iterdir() if car.is_dir() and sum(1 for _ in car.iterdir()) >= 2)
    return n


def safe_classes(paths: Paths, model: str) -> list[str]:
    try:
        return class_names(paths, model)
    except Exception:
        return []


class HarvestApp:
    """All the logic behind the page; the HTTP layer only routes to these methods."""

    def __init__(self, paths: Paths | None = None, store: Store | None = None):
        self.paths = paths or Paths()
        self.store = store or Store(self.paths)
        self._collect = {"running": False, "summary": None, "error": None, "task": None}
        self._lock = threading.Lock()

    def _publish(self, busy: set | None = None) -> None:
        """Keep harvest_inbox/gallery.json (what the Forensic Analyzer's Harvest tab shows) current.
        It is a derived file, so a failure here must never break the page or the Training Lab."""
        try:
            from .gallery import write_gallery
            write_gallery(self.paths, self.store, busy=busy)
        except Exception:
            pass

    def board(self) -> dict:
        busy = training_models()
        models = []
        for key, spec in MODELS.items():
            c = self.store.counts(key)
            if c["needs_eyes"]:
                nxt = f"{c['needs_eyes']} pictures need your eyes."
            elif c["ready"]:
                nxt = f"{c['ready']} pictures are ready to add to the dataset."
            else:
                nxt = "Nothing waiting. Analyze more clips, then press Collect."
            onnx = active_onnx(self.paths, key)
            models.append({
                "key": key, "title": spec["title"], "does": spec["does"], "counts": c, "next": nxt,
                "training": key in busy, "model_file": onnx.name if onnx else None,
                "dataset_images": dataset_size(self.paths, key),
                "classes": safe_classes(self.paths, key), "help": CLASS_HELP.get(key, {}),
            })
        automatic = []
        for a in AUTOMATIC:
            count = (reid_cars(self.paths) if a["key"] == "reid"
                     else _count_files(self.paths.datasets / a["folder"]))
            automatic.append({"title": a["title"], "how": a["how"], "count": count, "need": a["need"],
                              "unit": a.get("unit", "pictures")})
        rules = [{"violation": v, **c} for v, c in sorted(review_counts(self.paths.db).items())]
        return {"models": models, "automatic": automatic, "rules": rules, "colors": CLASS_COLORS,
                "protected": len(load_protected(self.paths)), "collect": dict(self._collect)}

    @staticmethod
    def _task(task: str | None) -> str | None:
        if task in (None, ""):
            return None
        if not TASK_RE.match(task):
            raise ValueError(f"not an analysis id: {task!r}")
        return task

    def queue(self, model: str, limit: int = 200, task: str | None = None) -> dict:
        """The pictures waiting for a human, most likely wrong first. `task` = only that one analysis."""
        if model not in MODELS:
            raise KeyError(model)
        task = self._task(task)
        items = self.store.queue(model, limit, task)
        return {"model": model, "classes": safe_classes(self.paths, model), "help": CLASS_HELP.get(model, {}),
                "total": self.store.counts(model, task)["needs_eyes"],
                "items": [{"id": i.id, "state": i.state, "reason": i.reason, "boxes": i.boxes,
                           "suggested": i.suggested, "violation": i.violation, "decision": i.decision,
                           "source": i.source, "width": i.width, "height": i.height, "priority": i.priority,
                           "task": i.task_id, "ticket": i.ticket_uid}
                          for i in items]}

    def session(self, task: str | None = None) -> dict:
        """What can be harvested from one analysis (or from all of them when `task` is empty)."""
        task = self._task(task)
        models = []
        for key, spec in MODELS.items():
            models.append({"key": key, "title": spec["title"], "does": spec["does"], "counts": self.store.counts(key, task),
                           "classes": safe_classes(self.paths, key), "help": CLASS_HELP.get(key, {})})
        return {"task": task, "collected": True if task is None else self.store.is_collected(task, COLLECT_VERSION),
                "protected": bool(task and task in load_protected(self.paths)),
                "has_video": None if task is None else task_video(self.paths, task) is not None,
                "pairs": self.store.pair_counts(task),
                "cars": car_counts(self.paths, self.store, task) if task else {"open": 0, "checked": 0, "split": 0},
                "collect": dict(self._collect), "models": models}

    def pairs(self, task: str | None = None) -> dict:
        """The "same car?" questions still open, likeliest first."""
        task = self._task(task)
        items = self.store.open_pairs(task)
        return {"task": task, "total": len(items),
                "items": [{"id": p.id, "kind": p.kind, "reason": p.reason, "score": p.score, "task": p.task_id}
                          for p in items]}

    def cars(self, task: str | None) -> dict:
        """Every ticketed car of one analysis that has photos to walk along."""
        task = self._task(task)
        if task is None:
            raise ValueError("an analysis is needed")
        return car_list(self.paths, self.store, task)

    def car(self, task: str | None, uid: str) -> dict:
        task = self._task(task)
        if task is None or not TASK_RE.match(uid or ""):
            raise ValueError("an analysis and a car are needed")
        return car_detail(self.paths, self.store, task, uid)

    def check(self, task: str | None, uid: str, different: list) -> dict:
        task = self._task(task)
        if task is None or not TASK_RE.match(uid or "") or not isinstance(different, list):
            raise ValueError("an analysis, a car and the photos of another car are needed")
        done = check_car(self.paths, self.store, task, uid, different)
        self._publish()
        return done

    def fill(self, task: str | None) -> dict:
        """"The rest are fine": every car nobody opened is filed as one car."""
        task = self._task(task)
        if task is None:
            raise ValueError("an analysis is needed")
        done = fill_cars(self.paths, self.store, task)
        self._publish()
        return done

    def answer(self, pair_id: str, answer: str) -> dict:
        pair = answer_pair(self.paths, self.store, pair_id, answer)
        self._publish()
        return {"counts": self.store.pair_counts(pair.task_id)}

    def save(self, item_id: str, boxes: list) -> dict:
        item = self.store.get(item_id)
        if item is None:
            raise KeyError(item_id)
        n_classes = len(safe_classes(self.paths, item.model))
        if not n_classes:
            raise ValueError(f"no dataset definition for {item.model}")
        self.store.save_boxes(item_id, clean_boxes(boxes, n_classes))
        self._publish()
        return {"counts": self.store.counts(item.model)}

    def skip(self, item_id: str) -> dict:
        item = self.store.get(item_id)
        if item is None:
            raise KeyError(item_id)
        self.store.skip(item_id)
        self._publish()
        return {"counts": self.store.counts(item.model)}

    def accept(self, model: str) -> dict:
        result = accept(self.paths, self.store, model)
        self._publish(busy=training_models())
        return result

    def start_collect(self, task: str | None = None) -> dict:
        """Gather pictures from the saved analyses in the background: one analysis, or all of them."""
        task = self._task(task)
        with self._lock:
            if self._collect["running"]:
                return dict(self._collect)
            self._collect.update(running=True, summary=None, error=None, task=task)

        def work():
            try:
                summary = collect(self.paths, self.store, task_ids=[task] if task else None)
                refresh_suggestions(self.paths, self.store)
                self._collect.update(summary=summary)
                self._publish(busy=training_models())
            except Exception as e:                                  # shown on the page, never crashes the server
                self._collect.update(error=f"{type(e).__name__}: {e}")
            finally:
                self._collect["running"] = False

        threading.Thread(target=work, daemon=True).start()
        return dict(self._collect)


def make_server(app: HarvestApp, port: int = 8765, token: str | None = None) -> ThreadingHTTPServer:
    token = token or secrets.token_urlsafe(16)

    class Handler(BaseHTTPRequestHandler):
        server_version = "Harvest"

        def log_message(self, *args):          # quiet
            pass

        def _send(self, status: int, body: bytes, ctype: str = "application/json") -> None:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _json(self, status: int, data) -> None:
            self._send(status, json.dumps(data).encode("utf-8"))

        def _allowed(self, q: dict) -> bool:
            host = (self.headers.get("Host") or "").split(":")[0]
            tok = (q.get("t") or [self.headers.get("X-Harvest-Token", "")])[0]
            return host in ("127.0.0.1", "localhost") and secrets.compare_digest(tok, token)

        def _route(self, method: str) -> None:
            self.server.last_request = time.time()
            url = urlparse(self.path)
            q = parse_qs(url.query)
            if not self._allowed(q):
                return self._json(403, {"error": "forbidden"})
            try:
                body = {}
                if method == "POST":
                    length = int(self.headers.get("Content-Length") or 0)
                    body = json.loads(self.rfile.read(length) or b"{}")
                path = url.path
                if method == "GET" and path == "/":
                    return self._send(200, PAGE.read_text(encoding="utf-8").encode("utf-8"), "text/html; charset=utf-8")
                if method == "GET" and path == "/api/board":
                    return self._json(200, app.board())
                if method == "GET" and path == "/api/queue":
                    return self._json(200, app.queue((q.get("model") or [""])[0], task=(q.get("task") or [None])[0]))
                if method == "GET" and path == "/api/session":
                    return self._json(200, app.session((q.get("task") or [None])[0]))
                if method == "GET" and path == "/api/cars":
                    return self._json(200, app.cars((q.get("task") or [None])[0]))
                if method == "GET" and path == "/api/car":
                    return self._json(200, app.car((q.get("task") or [None])[0], (q.get("uid") or [""])[0]))
                if method == "GET" and path == "/api/pairs":
                    return self._json(200, app.pairs((q.get("task") or [None])[0]))
                if method == "GET" and path.startswith("/img/"):
                    _, _, model, name = path.split("/", 3)
                    item_id = name.removesuffix(".jpg")
                    if model not in MODELS or not ID_RE.match(item_id):
                        return self._json(404, {"error": "not found"})
                    f = app.store.image_path(model, item_id)
                    if not f.exists():
                        return self._json(404, {"error": "not found"})
                    return self._send(200, f.read_bytes(), "image/jpeg")
                if method == "POST" and path == "/api/save":
                    return self._json(200, app.save(body["id"], body.get("boxes", [])))
                if method == "POST" and path == "/api/skip":
                    return self._json(200, app.skip(body["id"]))
                if method == "POST" and path == "/api/cars/fill":
                    return self._json(200, app.fill(body.get("task")))
                if method == "POST" and path == "/api/car":
                    return self._json(200, app.check(body.get("task"), str(body.get("uid", "")), body.get("different", [])))
                if method == "POST" and path == "/api/pair":
                    if not ID_RE.match(str(body.get("id", ""))):
                        return self._json(400, {"error": "bad request: not a pair id"})
                    return self._json(200, app.answer(body["id"], str(body.get("answer", ""))))
                if method == "POST" and path == "/api/accept":
                    return self._json(200, app.accept(body["model"]))
                if method == "POST" and path == "/api/collect":
                    return self._json(200, app.start_collect(body.get("task")))
                if method == "GET" and path == "/api/ping":
                    return self._json(200, {"ok": True, "api": API_VERSION})
                return self._json(404, {"error": "not found"})
            except TrainingBusy as e:
                self._json(409, {"error": str(e)})
            except (KeyError, ValueError) as e:
                self._json(400, {"error": f"bad request: {e}"})
            except Exception as e:
                self._json(500, {"error": f"{type(e).__name__}: {e}"})

        def do_GET(self):
            self._route("GET")

        def do_POST(self):
            self._route("POST")

    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.token = token
    server.last_request = time.time()
    return server


def serve(paths: Paths | None = None, port: int = 8765, open_browser: bool = True, idle_exit_min: float = 0) -> None:
    """Run until Ctrl+C. Writes harvest_inbox/server.json so the Training Lab and the dashboard can find / reuse it.
    `idle_exit_min` > 0 = stop by itself after that many minutes without a request (the dashboard starts it that way)."""
    paths = paths or Paths()
    app = HarvestApp(paths)
    try:
        server = make_server(app, port)
    except OSError:
        server = make_server(app, 0)                    # port taken: any free port
    host, real_port = server.server_address
    url = f"http://127.0.0.1:{real_port}/?t={server.token}"
    info = paths.inbox / "server.json"
    info.write_text(json.dumps({"url": url, "port": real_port, "pid": os.getpid()}))
    print(f"Harvest page: {url}\n(Ctrl+C to stop. Everything stays on this computer.)")
    if open_browser:
        import webbrowser
        webbrowser.open(url)
    if idle_exit_min > 0:
        def watch():
            while True:
                time.sleep(15)
                if time.time() - server.last_request > idle_exit_min * 60:
                    server.shutdown()
                    return
        threading.Thread(target=watch, daemon=True).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        info.unlink(missing_ok=True)
        server.server_close()
