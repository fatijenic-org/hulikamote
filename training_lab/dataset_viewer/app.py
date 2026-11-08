"""
app.py - All the logic of the Dataset Viewer (the HTTP layer in server.py only routes to these methods).

Rules this file keeps (they are locked project rules):
  * nothing is ever deleted: pictures go to datasets/_quarantine/<model>/<reason>/ and can be restored;
  * every change is written to dataset_viewer_cache/actions.jsonl with what is needed to undo it;
  * no write to a dataset while a training of that model runs (same check as the harvest tool);
  * files named harvest__* are the user's own work: changed only after an explicit extra confirmation;
  * restoring something that could put the same photo on both sides of the train / val split needs a confirmation;
  * nothing slow runs per request: the index of a dataset is built once in a background thread and cached as JSON,
    the cache is checked with the timestamps of the image / label folders.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
import zlib
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from pathlib import Path
from unittest import mock

LAB = Path(__file__).resolve().parents[1]                 # training_lab/
if str(LAB) not in sys.path:
    sys.path.insert(0, str(LAB))

from data_tools import common, curate                      # noqa: E402
from data_tools.common import IMAGE_EXT, SPLITS, group_key, read_yolo, source_of, write_yolo   # noqa: E402

API_VERSION = 1
CACHE = LAB / "dataset_viewer_cache"
MANIFEST = LAB / "configs" / "datasets_manifest.yaml"
HARVEST_PREFIX = curate.PROTECTED_PREFIX                   # "harvest__"
VIEWER_REASON = "removed_in_viewer"
PAGE_MAX = 200
MANY_BOXES = 10                                            # "many boxes" filter
TINY_AREA = 0.001                                          # "tiny box": covers under 0.1 % of the picture
MIN_EVAL_BOXES = 50                                        # fewer val / test boxes than this = the score is unreliable
THUMB_SIDE = 320
ORDER = ("primary_anchor", "helmet_specialist", "plate_specialist", "cabin_specialist")
MIME = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".bmp": "image/bmp", ".webp": "image/webp"}
SOURCE_NOTES = {"legacy": "Original committed data (file names without a '<source>__' prefix).",
                HARVEST_PREFIX.rstrip("_"): "Your own reviewed pictures from the harvest tool (protected)."}

_BAD_NAME = re.compile(r'[\\/:*?"<>|\x00-\x1f]')
_REASON = re.compile(r"^[a-z][a-z0-9_]{0,39}$")


class ViewerError(ValueError):
    """The request is wrong (HTTP 400)."""


class NotFound(KeyError):
    """No such dataset / picture (HTTP 404)."""


class TrainingBusy(RuntimeError):
    """A training of this model is running: its dataset must not change underneath it (HTTP 409)."""


class NeedsConfirm(RuntimeError):
    """The action is allowed but only after the user confirms (HTTP 409 with needs_confirm)."""

    def __init__(self, kind: str, message: str, detail=None):
        super().__init__(message)
        self.kind, self.detail = kind, detail


class IndexNotReady(RuntimeError):
    """The index is still being built (HTTP 503; the page polls)."""

    def __init__(self, progress: dict):
        super().__init__("the dataset index is being built")
        self.progress = progress


# --------------------------------------------------------------------------- validation

def safe_name(name) -> str:
    """A bare file name: no folders, no drive, no tricks. The only way a name from the page reaches the disk."""
    if (not isinstance(name, str) or not name or len(name) > 255 or _BAD_NAME.search(name)
            or name.startswith(".") or name.endswith((".", " "))):
        raise ViewerError(f"not a valid file name: {name!r}")
    return name


def safe_image_name(name) -> str:
    safe_name(name)
    if Path(name).suffix.lower() not in IMAGE_EXT:
        raise ViewerError(f"not a picture: {name!r}")
    return name


def safe_reason(reason) -> str:
    if not isinstance(reason, str) or not _REASON.match(reason):
        raise ViewerError(f"not a quarantine reason: {reason!r}")
    return reason


def _ints(text: str | None) -> set[int]:
    out = set()
    for part in (text or "").split(","):
        if part.strip().lstrip("-").isdigit():
            out.add(int(part))
    return out


def _words(text: str | None) -> set[str]:
    return {p for p in (text or "").split(",") if p}


def default_training_check(model: str) -> bool:
    from harvest_tool.accept import training_models        # one scan of the process list
    return model in training_models()


# --------------------------------------------------------------------------- the index of one dataset

def derive(row: dict) -> dict:
    """Fields the filters need, computed once per row from its stored fields (s, n, z, b, ml)."""
    boxes = row["b"]
    row["src"] = source_of(row["n"])
    row["mine"] = row["n"].startswith(HARVEST_PREFIX)
    row["nb"] = len(boxes)
    row["tiny"] = any(b[3] * b[4] < TINY_AREA for b in boxes)
    row["cls"] = {b[0] for b in boxes}
    return row


class Index:
    def __init__(self, model: str, nc: int, rows: list[dict], stamps: dict):
        self.model, self.nc, self.rows, self.stamps = model, nc, rows, stamps
        self.by_key: dict[tuple[str, str], dict] = {}
        self._groups: dict[str, set[str]] | None = None
        self.remap()

    def remap(self) -> None:
        self.by_key = {(r["s"], r["n"]): r for r in self.rows}
        self._groups = None

    def groups(self) -> dict[str, set[str]]:
        """photo id -> splits it is in (augmented copies share the id)."""
        if self._groups is None:
            g: dict[str, set[str]] = defaultdict(set)
            for r in self.rows:
                g[group_key(r["n"])].add(r["s"])
            self._groups = g
        return self._groups

    def remove(self, keys) -> None:
        gone = set(keys)
        self.rows = [r for r in self.rows if (r["s"], r["n"]) not in gone]
        self.remap()

    def add(self, row: dict) -> None:
        self.rows.append(derive(row))
        self.remap()

    def select(self, split=None, classes=None, sources=None, nobox=False, many=False, tiny=False,
               mine=False, flagged: set | None = None, q: str = "") -> list[dict]:
        ql = q.lower().strip()
        out = []
        for r in self.rows:
            if split and r["s"] not in split:
                continue
            if classes and not (r["cls"] & classes):
                continue
            if sources and r["src"] not in sources:
                continue
            if nobox and r["nb"]:
                continue
            if many and r["nb"] < MANY_BOXES:
                continue
            if tiny and not r["tiny"]:
                continue
            if mine and not r["mine"]:
                continue
            if flagged is not None and f"{r['s']}/{r['n']}" not in flagged:
                continue
            if ql and ql not in r["n"].lower():
                continue
            out.append(r)
        return out


# --------------------------------------------------------------------------- the app

class ViewerApp:
    def __init__(self, datasets: Path | None = None, cache: Path | None = None, manifest: Path | None = None,
                 training_check=None):
        self.datasets = Path(datasets or common.DATASETS)
        self.cache = Path(cache or CACHE)
        self.manifest_path = Path(manifest or MANIFEST)
        self.is_training = training_check or default_training_check
        self.qroot = common.QUARANTINE
        if self.qroot.parent.resolve() != self.datasets.resolve():
            raise RuntimeError("the quarantine folder must sit inside the datasets folder it serves")
        self.cache.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()                      # index / state
        self._wlock = threading.Lock()                      # one write at a time
        self._idx: dict[str, Index] = {}
        self._state: dict[str, dict] = {}                   # model -> {"state", "done", "total", "error"}
        self._sizes: dict[str, dict] = {}
        self._sizes_state: dict[str, dict] = {}
        self._flags: dict[str, set] = {}
        self._jobs: dict[str, dict] = {}
        self._busy_cache: tuple[float, set] = (0.0, set())
        self._applying: set[str] = set()
        self._save_timers: dict[str, threading.Timer] = {}
        self._relabeled: dict[str, set[str]] = {}
        self._card_stale: dict[str, bool] = {}
        self._manifest = None
        self.actions_path = self.cache / "actions.jsonl"
        self._stack: list[dict] = []
        self._qsplit: dict[str, str] = {}                   # quarantine path (relative) -> split it came from
        self._qname: dict[str, str] = {}                    # quarantine path (relative) -> original file name
        self._reid = None
        self._load_actions()

    @property
    def reid(self):
        """The Car matcher (ReID) manager (reid.py): datasets/reid is folders of car photos, not YOLO boxes, so it has its own logic."""
        if self._reid is None:
            from .reid import ReidManager
            self._reid = ReidManager(self.datasets, self.cache, thumb=self.thumb)
        return self._reid

    # ----------------------------------------------------------------- lookups

    def models(self) -> list[str]:
        found = []
        for p in self.datasets.iterdir() if self.datasets.exists() else []:
            if not p.name.startswith("_") and (p / "data.yaml").is_file() and (p / "images").is_dir():
                found.append(p.name)
        return sorted(found, key=lambda m: (ORDER.index(m) if m in ORDER else len(ORDER), m))

    def model(self, name) -> str:
        if not isinstance(name, str) or name not in self.models():
            raise NotFound(f"unknown dataset: {name!r}")
        return name

    @staticmethod
    def split(name) -> str:
        if name not in SPLITS:
            raise ViewerError(f"unknown split: {name!r}")
        return name

    def class_names(self, model: str) -> list[str]:
        names = common.load_yaml(self.datasets / model / "data.yaml").get("names") or []
        if isinstance(names, dict):
            return [str(names[k]) for k in sorted(names)]
        return [str(n) for n in names]

    def manifest(self) -> dict:
        if self._manifest is None:
            try:
                self._manifest = common.load_yaml(self.manifest_path)
            except Exception:
                self._manifest = {}
        return self._manifest

    def source_info(self, src: str) -> dict:
        for entries in self.manifest().values():
            for e in entries if isinstance(entries, list) else []:
                if isinstance(e, dict) and e.get("id") == src:
                    return {"id": src, "license": e.get("license"), "country": e.get("country"), "ph": e.get("ph"),
                            "trust": e.get("trust"), "notes": e.get("notes"), "citation": e.get("citation")}
        if src == "legacy":
            return {"id": src, "license": None, "country": None, "ph": None, "trust": None, "notes": SOURCE_NOTES[src]}
        if src == HARVEST_PREFIX.rstrip("_"):
            return {"id": src, "license": "own work", "country": "Philippines", "ph": True, "trust": "A",
                    "notes": SOURCE_NOTES[src]}
        return {"id": src, "license": None, "country": None, "ph": None, "trust": None, "notes": None}

    def path_of(self, model: str, split: str, name: str, kind: str = "images") -> Path:
        name = safe_name(name)
        return self.datasets / self.model(model) / kind / self.split(split) / name

    def busy(self, fresh: bool = False) -> set[str]:
        """Models being trained now (cached for a few seconds when only a badge needs it)."""
        t, models = self._busy_cache
        if fresh or time.time() - t > 5:
            models = {m for m in self.models() if self.is_training(m)}
            self._busy_cache = (time.time(), models)
        return models

    # ----------------------------------------------------------------- index: build, cache, check

    def _stamps(self, model: str) -> dict:
        out = {}
        base = self.datasets / model
        for kind in ("images", "labels"):
            for split in SPLITS:
                try:
                    out[f"{kind}/{split}"] = os.stat(base / kind / split).st_mtime_ns
                except OSError:
                    out[f"{kind}/{split}"] = 0
        try:
            out["data.yaml"] = os.stat(base / "data.yaml").st_mtime_ns
        except OSError:
            out["data.yaml"] = 0
        return out

    def _cache_file(self, model: str) -> Path:
        return self.cache / f"index_{model}.json"

    def start_indexing(self, model: str, force: bool = False) -> None:
        """Make sure an index exists or is being built (idempotent). Loads the JSON cache when it is still valid."""
        model = self.model(model)
        with self._lock:
            st = self._state.get(model)
            if st and st["state"] == "building":
                return
            if not force and model in self._idx and self._idx[model].stamps == self._stamps(model):
                return
            self._state[model] = {"state": "building", "done": 0, "total": 0, "error": None}
        threading.Thread(target=self._index_worker, args=(model, force), daemon=True).start()

    def _index_worker(self, model: str, force: bool) -> None:
        try:
            idx = None if force else self._load_cache(model)
            if idx is None:
                idx = self._build(model)
                self._write_cache(idx)
            with self._lock:
                self._idx[model] = idx
                self._state[model] = {"state": "ready", "done": len(idx.rows), "total": len(idx.rows), "error": None}
        except Exception as e:                                      # shown on the page, never crashes the server
            with self._lock:
                self._state[model] = {"state": "error", "done": 0, "total": 0, "error": f"{type(e).__name__}: {e}"}

    def _load_cache(self, model: str) -> Index | None:
        try:
            data = json.loads(self._cache_file(model).read_text(encoding="utf-8"))
            nc = len(self.class_names(model))
            if data.get("v") != 1 or data.get("stamps") != self._stamps(model) or data.get("nc") != nc:
                return None
            rows = [derive({"s": s, "n": n, "z": z, "b": b, "ml": ml}) for s, n, z, b, ml in data["rows"]]
            return Index(model, nc, rows, data["stamps"])
        except Exception:
            return None

    def _write_cache(self, idx: Index) -> None:
        data = {"v": 1, "nc": idx.nc, "stamps": idx.stamps,
                "rows": [[r["s"], r["n"], r["z"], r["b"], r["ml"]] for r in idx.rows]}
        tmp = self._cache_file(idx.model).with_suffix(".tmp")
        tmp.write_text(json.dumps(data, separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, self._cache_file(idx.model))

    def _schedule_save(self, model: str) -> None:
        """Coalesce the cache writes of a burst of edits into one."""
        with self._lock:
            old = self._save_timers.get(model)
            if old:
                old.cancel()

            def save():
                with self._lock:
                    idx = self._idx.get(model)
                    if idx:
                        self._write_cache(idx)
            t = threading.Timer(2.0, save)
            t.daemon = True
            self._save_timers[model] = t
            t.start()

    def flush(self) -> None:
        for model in list(self._save_timers):
            t = self._save_timers.pop(model)
            if t.is_alive():
                t.cancel()
                with self._lock:
                    if model in self._idx:
                        self._write_cache(self._idx[model])

    def _build(self, model: str) -> Index:
        base = self.datasets / model
        nc = len(self.class_names(model))
        stamps = self._stamps(model)
        listing = []
        for split in SPLITS:
            names, labels = [], set()
            try:
                with os.scandir(base / "images" / split) as it:
                    for e in it:
                        if e.is_file() and os.path.splitext(e.name)[1].lower() in IMAGE_EXT:
                            names.append((e.name, e.stat().st_size))
            except OSError:
                pass
            try:
                with os.scandir(base / "labels" / split) as it:
                    labels = {e.name for e in it if e.name.endswith(".txt")}
            except OSError:
                pass
            names.sort()
            listing.append((split, names, labels))
        total = sum(len(n) for _, n, _ in listing)
        self._state[model].update(total=total, done=0)
        rows = []

        def load(split, name, size, labels):
            stem = os.path.splitext(name)[0]
            has = f"{stem}.txt" in labels
            boxes = []
            if has:
                boxes = [[c, round(cx, 5), round(cy, 5), round(w, 5), round(h, 5)]
                         for c, cx, cy, w, h in read_yolo(base / "labels" / split / f"{stem}.txt")]
            return derive({"s": split, "n": name, "z": size, "b": boxes, "ml": 0 if has else 1})

        with ThreadPoolExecutor(max_workers=12) as pool:
            for split, names, labels in listing:
                for n, row in enumerate(pool.map(lambda t: load(split, t[0], t[1], labels), names), 1):
                    rows.append(row)
                    if len(rows) % 1000 == 0:
                        self._state[model]["done"] = len(rows)
        return Index(model, nc, rows, stamps)

    def progress(self, model: str) -> dict:
        with self._lock:
            return dict(self._state.get(model) or {"state": "idle", "done": 0, "total": 0, "error": None})

    def index(self, model: str) -> Index:
        model = self.model(model)
        with self._lock:
            idx = self._idx.get(model)
        if idx is None:
            self.start_indexing(model)
            raise IndexNotReady(self.progress(model))
        return idx

    def refresh(self, model: str) -> dict:
        """Forget the cache and read the folders again (after something outside the viewer changed them)."""
        self.start_indexing(model, force=True)
        return self.progress(model)

    def _restamp(self, model: str) -> None:
        with self._lock:
            if model in self._idx:
                self._idx[model].stamps = self._stamps(model)
        self._schedule_save(model)

    def _row_from_disk(self, model: str, split: str, name: str) -> dict:
        base = self.datasets / model
        lbl = base / "labels" / split / (Path(name).stem + ".txt")
        has = lbl.exists()
        boxes = [[c, round(cx, 5), round(cy, 5), round(w, 5), round(h, 5)] for c, cx, cy, w, h in read_yolo(lbl)] if has else []
        return {"s": split, "n": name, "z": (base / "images" / split / name).stat().st_size, "b": boxes,
                "ml": 0 if has else 1}

    # ----------------------------------------------------------------- flags and image sizes

    def _flag_file(self, model: str) -> Path:
        return self.cache / f"flags_{model}.json"

    def flags(self, model: str) -> set:
        with self._lock:
            if model not in self._flags:
                try:
                    self._flags[model] = set(json.loads(self._flag_file(model).read_text(encoding="utf-8")))
                except Exception:
                    self._flags[model] = set()
            return self._flags[model]

    def _save_flags(self, model: str) -> None:
        self._flag_file(model).write_text(json.dumps(sorted(self.flags(model))), encoding="utf-8")

    def relabeled(self, model: str) -> set[str]:
        with self._lock:
            if model not in self._relabeled:
                try:
                    value = json.loads((self.cache / f"relabeled_{model}.json").read_text(encoding="utf-8"))
                    self._relabeled[model] = set(value)
                except FileNotFoundError:
                    self._relabeled[model] = set()
            return self._relabeled[model]

    def _save_relabeled(self, model: str) -> None:
        path = self.cache / f"relabeled_{model}.json"
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(sorted(self.relabeled(model))), encoding="utf-8")
        os.replace(tmp, path)

    def _card_stale_file(self, model: str) -> Path:
        return self.cache / f"card_stale_{model}.json"

    def card_stale(self, model: str) -> bool:
        if model not in self._card_stale:
            self._card_stale[model] = self._card_stale_file(model).exists()
        return self._card_stale[model]

    def _mark_card_stale(self, model: str) -> None:
        self._card_stale[model] = True
        self._atomic_text(self._card_stale_file(model), "true")

    def _clear_card_stale(self, model: str) -> None:
        self._card_stale[model] = False
        self._card_stale_file(model).unlink(missing_ok=True)

    def sizes(self, model: str) -> dict:
        with self._lock:
            if model not in self._sizes:
                try:
                    self._sizes[model] = json.loads((self.cache / f"sizes_{model}.json").read_text(encoding="utf-8"))
                except Exception:
                    self._sizes[model] = {}
            return self._sizes[model]

    @staticmethod
    def read_size(path: Path) -> list[int] | None:
        """Picture size as the model sees it (EXIF rotation applied), from the file header only."""
        from PIL import Image
        try:
            with Image.open(path) as im:
                w, h = im.size
                if im.getexif().get(274, 1) in (5, 6, 7, 8):
                    w, h = h, w
                return [w, h]
        except Exception:
            return None

    def start_sizes(self, model: str) -> dict:
        """Read the pixel size of every picture in the background (headers only); the Overview fills in as it goes."""
        idx = self.index(model)
        with self._lock:
            st = self._sizes_state.get(model)
            if st and st["state"] == "running":
                return dict(st)
            known = self.sizes(model)
            todo = [(r["s"], r["n"]) for r in idx.rows if f"{r['s']}/{r['n']}" not in known]
            self._sizes_state[model] = st = {"state": "running" if todo else "ready", "done": 0, "total": len(todo)}
        if not todo:
            return dict(st)

        def work():
            known = self.sizes(model)
            try:
                with ThreadPoolExecutor(max_workers=8) as pool:
                    for n, (key, size) in enumerate(pool.map(
                            lambda t: (f"{t[0]}/{t[1]}", self.read_size(self.datasets / model / "images" / t[0] / t[1])), todo), 1):
                        if size:
                            known[key] = size
                        st["done"] = n
                        if n % 3000 == 0:
                            self._write_sizes(model)
                self._write_sizes(model)
                st["state"] = "ready"
            except Exception as e:
                st.update(state="error", error=f"{type(e).__name__}: {e}")

        threading.Thread(target=work, daemon=True).start()
        return dict(st)

    def _write_sizes(self, model: str) -> None:
        tmp = self.cache / f"sizes_{model}.tmp"
        tmp.write_text(json.dumps(self.sizes(model), separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, self.cache / f"sizes_{model}.json")

    # ----------------------------------------------------------------- reading: datasets, items, facets

    def list_datasets(self) -> list[dict]:
        busy = self.busy()
        out = []
        for model in self.models():
            names = self.class_names(model)
            self.start_indexing(model)
            prog = self.progress(model)
            entry = {"name": model, "classes": names, "training": model in busy, "index": prog, "images": None,
                     "ph_share": None, "warnings": [], "card_stale": self.card_stale(model)}
            idx = self._idx.get(model)
            if idx:
                if idx.stamps != self._stamps(model) and prog["state"] != "building" and model not in self._applying:
                    self.start_indexing(model)               # something outside the viewer changed the folders
                per = Counter(r["s"] for r in idx.rows)
                entry["images"] = {s: per.get(s, 0) for s in SPLITS}
                entry["total"] = len(idx.rows)
                ph = sum(1 for r in idx.rows if self.source_info(r["src"]).get("ph") is True)
                entry["ph_share"] = round(ph / len(idx.rows), 4) if idx.rows else 0
                entry["warnings"] = self.class_warnings(idx, names)
            out.append(entry)
        return out

    @staticmethod
    def class_warnings(idx: Index, names: list[str]) -> list[dict]:
        counts = {s: Counter() for s in ("val", "test")}
        for r in idx.rows:
            if r["s"] in counts:
                for b in r["b"]:
                    counts[r["s"]][b[0]] += 1
        return [{"class": names[c], "split": s, "boxes": counts[s][c]}
                for s in ("val", "test") for c in range(len(names)) if counts[s][c] < MIN_EVAL_BOXES]

    def facets(self, model: str, split: str | None) -> dict:
        idx = self.index(model)
        splits = {split} if split in SPLITS else None
        rows = idx.select(split=splits)
        flags = self.flags(model)
        classes = Counter()
        sources = Counter()
        for r in rows:
            for c in r["cls"]:
                classes[c] += 1
            sources[r["src"]] += 1
        return {"classes": {str(k): v for k, v in sorted(classes.items())},
                "sources": dict(sorted(sources.items())),
                "counts": {"all": len(rows), "nobox": sum(1 for r in rows if not r["nb"]),
                           "many": sum(1 for r in rows if r["nb"] >= MANY_BOXES),
                           "tiny": sum(1 for r in rows if r["tiny"]), "mine": sum(1 for r in rows if r["mine"]),
                           "flagged": sum(1 for r in rows if f"{r['s']}/{r['n']}" in flags),
                           "relabeled": sum(1 for r in rows if f"{r['s']}/{r['n']}" in self.relabeled(model))}}

    def _filtered(self, model: str, q: dict) -> list[dict]:
        idx = self.index(model)
        split = _words(q.get("split"))
        if split - set(SPLITS):
            raise ViewerError("unknown split")
        rows = idx.select(
            split=split or None, classes=_ints(q.get("classes")) or None, sources=_words(q.get("source")) or None,
            nobox=q.get("nobox") == "1", many=q.get("many") == "1", tiny=q.get("tiny") == "1",
            mine=q.get("mine") == "1", flagged=self.flags(model) if q.get("flag") == "1" else None,
            q=q.get("q") or "")
        if q.get("relabeled") == "1":
            marked = self.relabeled(model)
            rows = [r for r in rows if f"{r['s']}/{r['n']}" in marked]
        sort = q.get("sort") or "name"
        if sort == "boxes":
            rows.sort(key=lambda r: (-r["nb"], r["n"]))
        elif sort == "size":
            sz = self.sizes(model)
            rows.sort(key=lambda r: (-(lambda s: s[0] * s[1] if s else 0)(sz.get(f"{r['s']}/{r['n']}")), r["n"]))
        elif sort == "random":
            seed = str(q.get("seed") or "1")
            rows.sort(key=lambda r: zlib.crc32(f"{seed}{r['s']}{r['n']}".encode()))
        elif sort == "name":
            rows.sort(key=lambda r: (r["n"], r["s"]))
        else:
            raise ViewerError(f"unknown sort: {sort}")
        return rows

    def items(self, model: str, q: dict) -> dict:
        model = self.model(model)
        rows = self._filtered(model, q)
        try:
            offset = max(0, int(q.get("offset") or 0))
            limit = min(PAGE_MAX, max(1, int(q.get("limit") or 150)))
        except ValueError:
            raise ViewerError("offset and limit must be numbers")
        sz, flags = self.sizes(model), self.flags(model)
        page = []
        for r in rows[offset:offset + limit]:
            key = f"{r['s']}/{r['n']}"
            s = sz.get(key)
            page.append({"s": r["s"], "n": r["n"], "b": r["b"], "z": r["z"], "ml": r["ml"], "src": r["src"],
                         "w": s[0] if s else None, "h": s[1] if s else None, "flag": key in flags,
                         "rl": key in self.relabeled(model)})
        return {"total": len(rows), "offset": offset, "items": page}

    def keys(self, model: str, q: dict) -> dict:
        """Every [split, name] of a filtered list (select-all, shift ranges)."""
        rows = self._filtered(self.model(model), q)
        return {"total": len(rows), "keys": [[r["s"], r["n"]] for r in rows[:60000]]}

    def label_items(self, model: str, q: dict) -> dict:
        model = self.model(model)
        idx = self.index(model)
        split = q.get("split") or "all"
        if split != "all" and split not in SPLITS:
            raise ViewerError(f"unknown split: {split!r}")
        source = q.get("source") or "all"
        try:
            class_id = None if q.get("class") in (None, "", "all") else int(q["class"])
            min_box_px = max(0, int(q.get("min_box_px") or 0))
            offset = max(0, int(q.get("offset") or 0))
            limit = min(PAGE_MAX, max(1, int(q.get("limit") or 100)))
        except (TypeError, ValueError):
            raise ViewerError("class, minimum box size, offset and limit must be numbers")
        if class_id is not None and not 0 <= class_id < idx.nc:
            raise ViewerError(f"class must be 0..{idx.nc - 1}")
        if min_box_px > 4096:
            raise ViewerError("minimum box size cannot exceed 4096 pixels")
        sizes = self.sizes(model)
        if min_box_px and (self._sizes_state.get(model, {}).get("state") != "ready"):
            return {"items": [], "total": 0, "offset": offset, "size_pending": True,
                    "sizes": self.start_sizes(model)}
        classes = self.class_names(model)
        marked = self.relabeled(model)
        rows = []
        for row in idx.rows:
            if split != "all" and row["s"] != split:
                continue
            if source != "all" and row["src"] != source:
                continue
            size = sizes.get(f"{row['s']}/{row['n']}")
            for box_index, box in enumerate(row["b"]):
                if class_id is not None and box[0] != class_id:
                    continue
                width = round(box[3] * size[0]) if size else None
                height = round(box[4] * size[1]) if size else None
                if min_box_px and (width is None or height is None or min(width, height) < min_box_px):
                    continue
                rows.append({"split": row["s"], "name": row["n"], "index": box_index,
                             "class_id": box[0], "class_name": classes[box[0]], "box": box[1:],
                             "source": row["src"], "width": width, "height": height,
                             "harvest": row["mine"], "relabeled": f"{row['s']}/{row['n']}" in marked})
        rows.sort(key=lambda item: (item["name"], item["split"], item["index"]))
        return {"items": rows[offset:offset + limit], "total": len(rows), "offset": offset,
                "size_pending": False, "sources": sorted({r["src"] for r in idx.rows})}

    def item(self, model: str, split: str, name: str) -> dict:
        model = self.model(model)
        row = self.index(model).by_key.get((self.split(split), safe_name(name)))
        if row is None:
            raise NotFound(f"{split}/{name} is not in {model}")
        names = self.class_names(model)
        path = self.path_of(model, split, name)
        size = self.sizes(model).get(f"{split}/{name}") or self.read_size(path)
        boxes = []
        for i, b in enumerate(row["b"]):
            boxes.append({"i": i, "cls": b[0], "name": names[b[0]] if 0 <= b[0] < len(names) else "?",
                          "box": b[1:], "px": [round(b[3] * size[0]), round(b[4] * size[1])] if size else None})
        return {"dataset": model, "split": split, "name": name, "file": str(path), "bytes": row["z"], "size": size,
                "source": self.source_info(row["src"]), "boxes": boxes, "label_missing": bool(row["ml"]),
                "flag": f"{split}/{name}" in self.flags(model), "harvest": row["mine"],
                "relabeled": f"{split}/{name}" in self.relabeled(model)}

    # ----------------------------------------------------------------- pictures and thumbnails

    def image_file(self, model: str, split: str, name: str) -> Path:
        path = self.path_of(model, split, safe_image_name(name))
        if not path.is_file():
            raise NotFound(f"{split}/{name}")
        return path

    def quarantine_file(self, model: str, reason: str, name: str) -> Path:
        path = self.qroot / self.model(model) / safe_reason(reason) / safe_image_name(name)
        if not path.is_file():
            raise NotFound(f"{reason}/{name}")
        return path

    def thumb(self, source: Path, key: str) -> Path:
        """320 px JPEG of a picture, made once and kept on disk (rebuilt when the picture is newer)."""
        out = self.cache / "thumbs" / key
        out = out.with_name(out.name + ".jpg")
        try:
            if out.stat().st_mtime >= source.stat().st_mtime:
                return out
        except OSError:
            pass
        from PIL import Image, ImageOps
        with Image.open(source) as im:
            if im.format == "JPEG":
                im.draft("RGB", (THUMB_SIDE * 2, THUMB_SIDE * 2))
            im = ImageOps.exif_transpose(im)
            im.thumbnail((THUMB_SIDE, THUMB_SIDE))
            im = im.convert("RGB")
            out.parent.mkdir(parents=True, exist_ok=True)
            tmp = out.with_name(f"{out.name}.{threading.get_ident()}.tmp")
            im.save(tmp, "JPEG", quality=80)
        os.replace(tmp, out)
        return out

    def thumb_of_item(self, model: str, split: str, name: str) -> Path:
        return self.thumb(self.image_file(model, split, name), f"{model}/{split}/{name}")

    def crop_of_item(self, model: str, split: str, name: str, box_index) -> Path:
        model = self.model(model)
        split, name = self.split(split), safe_image_name(name)
        if isinstance(box_index, str) and box_index.isdigit():
            box_index = int(box_index)
        row = self.index(model).by_key.get((split, name))
        if row is None:
            raise NotFound(f"{split}/{name} is not in {model}")
        if not isinstance(box_index, int) or isinstance(box_index, bool) or not 0 <= box_index < len(row["b"]):
            raise ViewerError("no such box")
        source = self.image_file(model, split, name)
        box = row["b"][box_index]
        signature = zlib.crc32(f"{source.stat().st_mtime_ns}:{box[1:]}".encode())
        out = self.cache / "crops" / model / split / f"{Path(name).stem}_{box_index}_{signature:08x}.jpg"
        try:
            if out.stat().st_mtime_ns >= source.stat().st_mtime_ns:
                return out
        except OSError:
            pass
        from PIL import Image, ImageOps
        with Image.open(source) as image:
            image = ImageOps.exif_transpose(image)
            width, height = image.size
            _, cx, cy, bw, bh = box
            x1, y1 = (cx - bw / 2) * width, (cy - bh / 2) * height
            x2, y2 = (cx + bw / 2) * width, (cy + bh / 2) * height
            px, py = max(3, (x2 - x1) * 0.12), max(3, (y2 - y1) * 0.12)
            bounds = (max(0, int(x1 - px)), max(0, int(y1 - py)),
                      min(width, int(x2 + px)), min(height, int(y2 + py)))
            crop = image.crop(bounds).convert("RGB")
            crop.thumbnail((THUMB_SIDE, THUMB_SIDE))
            out.parent.mkdir(parents=True, exist_ok=True)
            tmp = out.with_name(f"{out.name}.{threading.get_ident()}.tmp")
            crop.save(tmp, "JPEG", quality=84)
        os.replace(tmp, out)
        return out

    def thumb_of_quarantined(self, model: str, reason: str, name: str) -> Path:
        return self.thumb(self.quarantine_file(model, reason, name), f"_q/{model}/{reason}/{name}")

    def reveal(self, model: str, split: str, name: str) -> dict:
        path = self.image_file(model, split, name)
        if os.name != "nt":
            raise ViewerError("opening the file location is supported on Windows only")
        subprocess.Popen(["explorer", f"/select,{path}"])
        return {"ok": True}

    # ----------------------------------------------------------------- overview

    def overview(self, model: str) -> dict:
        model = self.model(model)
        idx = self.index(model)
        names = self.class_names(model)
        nc = len(names)
        per_split = Counter(r["s"] for r in idx.rows)
        boxes_split = {s: [0] * nc for s in SPLITS}
        per_source: dict[str, list] = {}
        src_images = Counter()
        per_img = Counter()
        area_edges = [0.0001, 0.0003, 0.001, 0.003, 0.01, 0.03, 0.1, 0.3]
        area_hist = [0] * (len(area_edges) + 1)
        sz = self.sizes(model)
        long_hist, aspect_hist, box_aspect = Counter(), Counter(), Counter()
        sized = 0
        empty = 0
        for r in idx.rows:
            src_images[r["src"]] += 1
            per_img[min(r["nb"], 20)] += 1
            if not r["nb"]:
                empty += 1
            row_src = per_source.setdefault(r["src"], [0] * nc)
            s = sz.get(f"{r['s']}/{r['n']}")
            if s:
                sized += 1
                long_hist[min(s[0] if s[0] > s[1] else s[1], 1920) // 160 * 160] += 1
                aspect_hist[_aspect_bin(s[0] / s[1])] += 1
            for c, cx, cy, w, h in r["b"]:
                if 0 <= c < nc:
                    boxes_split[r["s"]][c] += 1
                    row_src[c] += 1
                a = w * h
                area_hist[sum(1 for e in area_edges if a >= e)] += 1
                if s and h > 0:
                    box_aspect[_aspect_bin((w * s[0]) / (h * s[1]))] += 1
        ph = Counter()
        for src, n in src_images.items():
            p = self.source_info(src).get("ph")
            ph["ph" if p is True else "mixed" if p == "mixed" else "foreign" if p is False else "unknown"] += n
        edges = ["<0.01%", "0.01-0.03%", "0.03-0.1%", "0.1-0.3%", "0.3-1%", "1-3%", "3-10%", "10-30%", ">30%"]
        total = len(idx.rows)
        return {
            "dataset": model, "classes": names, "images": total, "images_per_split": {s: per_split.get(s, 0) for s in SPLITS},
            "boxes_per_class": boxes_split,
            "per_source": {k: {"images": src_images[k], "boxes": v} for k, v in sorted(per_source.items())},
            "ph": dict(ph), "empty": empty,
            "boxes_per_image": [{"label": str(i) if i < 20 else "20+", "n": per_img.get(i, 0)} for i in range(21)],
            "box_area": [{"label": l, "n": n} for l, n in zip(edges, area_hist)],
            "sizes": {"state": (self._sizes_state.get(model) or {}).get("state", "idle"), "have": sized, "of": total,
                      "progress": dict(self._sizes_state.get(model) or {}),
                      "long_side": [{"label": f"{k}-{k + 159}" if k < 1920 else "1920+", "n": long_hist[k]}
                                    for k in sorted(long_hist)],
                      "aspect": [{"label": l, "n": aspect_hist.get(l, 0)} for l in ASPECT_LABELS],
                      "box_aspect": [{"label": l, "n": box_aspect.get(l, 0)} for l in ASPECT_LABELS]},
            "warnings": self.balance_warnings(boxes_split, names, per_split),
            "report": self.compare_report(model, per_split, boxes_split, names),
        }

    @staticmethod
    def balance_warnings(boxes_split: dict, names: list[str], per_split: Counter) -> list[dict]:
        out = []
        for c, name in enumerate(names):
            for s in ("val", "test"):
                if boxes_split[s][c] < MIN_EVAL_BOXES:
                    out.append({"level": "bad", "text": f"{name}: only {boxes_split[s][c]} {s} boxes. "
                                                         f"Its {s} score is unreliable (under {MIN_EVAL_BOXES})."})
            if boxes_split["train"][c] == 0:
                out.append({"level": "bad", "text": f"{name}: no training boxes at all."})
        train = [x for x in boxes_split["train"] if x] or [0]
        if max(train) > 20 * min(train) and len(train) > 1:
            out.append({"level": "warn", "text": f"Training boxes are very unbalanced: the biggest class has "
                                                 f"{max(train) // max(min(train), 1)}x more boxes than the smallest."})
        for s in SPLITS:
            if not per_split.get(s):
                out.append({"level": "warn", "text": f"The {s} split has no pictures."})
        return out

    def compare_report(self, model: str, per_split: Counter, boxes_split: dict, names: list[str]) -> dict | None:
        """The curator's own numbers (report.json) next to ours; they match right after a cleaning."""
        path = self.datasets / model / "report.json"
        try:
            rep = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        diffs = []
        for s in SPLITS:
            want = (rep.get("images_per_split") or {}).get(s)
            if want is not None and want != per_split.get(s, 0):
                diffs.append(f"{s} pictures: report {want}, now {per_split.get(s, 0)}")
            for c, name in enumerate(names):
                want = ((rep.get("boxes_per_class") or {}).get(s) or {}).get(name, 0)
                if want != boxes_split[s][c]:
                    diffs.append(f"{s} {name} boxes: report {want}, now {boxes_split[s][c]}")
        return {"file": str(path), "applied": rep.get("applied"), "kept": rep.get("kept"), "dropped": rep.get("dropped"),
                "when": time.strftime("%Y-%m-%d %H:%M", time.localtime(path.stat().st_mtime)), "match": not diffs,
                "diffs": diffs[:20]}

    # ----------------------------------------------------------------- about and notes

    def about(self, model: str) -> dict:
        model = self.model(model)
        base = self.datasets / model

        def read(p: Path) -> str:
            try:
                return p.read_text(encoding="utf-8")
            except OSError:
                return ""

        counts = Counter(r["src"] for r in self._idx[model].rows) if model in self._idx else Counter()
        entries = [e for e in (self.manifest().get(model) or []) if isinstance(e, dict)]
        sources = [{"id": e.get("id"), "license": e.get("license"), "country": e.get("country"), "ph": e.get("ph"),
                    "trust": e.get("trust"), "notes": e.get("notes"), "images": counts.get(e.get("id"), 0)}
                   for e in entries]
        listed = {s["id"] for s in sources}
        for src, n in sorted(counts.items()):
            if src not in listed:
                info = self.source_info(src)
                sources.append({**info, "images": n})
        return {"dataset": model, "card": read(base / "DATASET_CARD.md"), "classes": self.class_names(model),
                "sources": sources, "catalog": self._catalog_row(model), "notes": read(base / "NOTES.md"),
                "card_stale": self.card_stale(model)}

    def _catalog_row(self, model: str) -> dict | None:
        header = None
        for line in (self.datasets / "CATALOG.md").read_text(encoding="utf-8").splitlines() if (self.datasets / "CATALOG.md").exists() else []:
            if not line.startswith("|"):
                continue
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if header is None:
                header = cells
            elif cells and cells[0] == model:
                return {"header": header, "row": cells}
        return None

    def save_notes(self, model: str, text) -> dict:
        model = self.model(model)
        if not isinstance(text, str) or len(text) > 200_000:
            raise ViewerError("notes must be text under 200 KB")
        path = self.datasets / model / "NOTES.md"
        before = path.read_text(encoding="utf-8") if path.exists() else None
        tmp = path.with_suffix(".tmp")
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, path)
        self._log({"type": "notes", "model": model, "before": before, "after": text})
        return {"ok": True}

    # ----------------------------------------------------------------- the action log and undo

    UNDOABLE = ("quarantine", "restore", "box", "flag", "relabel")

    def _load_actions(self) -> None:
        try:
            lines = self.actions_path.read_text(encoding="utf-8").splitlines()
        except OSError:
            return
        for line in lines:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            self._remember(e)

    def _remember(self, e: dict) -> None:
        if e.get("type") in self.UNDOABLE:
            self._stack.append(e)
        elif e.get("type") == "undo":
            self._stack = [a for a in self._stack if a.get("id") != e.get("of")]
        if e.get("type") == "quarantine":
            for it in e["items"]:
                for _, to in it["moved"]:
                    self._qsplit[to] = it["split"]
                    self._qname[to] = it["name"] if Path(to).suffix.lower() in IMAGE_EXT else Path(to).name

    def _log(self, entry: dict) -> dict:
        entry = {"id": uuid.uuid4().hex[:12], "ts": time.strftime("%Y-%m-%dT%H:%M:%S"), **entry}
        with self._lock, open(self.actions_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        self._remember(entry)
        return entry

    def _rel(self, path: Path) -> str:
        return path.resolve().relative_to(self.datasets.resolve()).as_posix()

    def _guard(self, model: str, names=(), confirm_harvest: bool = False) -> None:
        """Every dataset write goes through here."""
        if model in self._applying:
            raise ViewerError(f"{model} is being cleaned right now: wait until it is done")
        try:
            training = model in self.busy(fresh=True)
        except Exception as e:                                       # cannot tell: do not risk the training
            raise TrainingBusy(f"Could not check whether {model} is training ({type(e).__name__}); nothing was changed.")
        if training:
            raise TrainingBusy(f"{model} is training right now. Pause or wait for it to finish; nothing was changed.")
        mine = [n for n in names if n.startswith(HARVEST_PREFIX)]
        if mine and not confirm_harvest:
            raise NeedsConfirm("harvest", f"{len(mine)} of these are your own reviewed pictures (harvest__). "
                                          "Change them anyway?", mine[:20])

    def _pairs(self, model: str, items) -> list[tuple[str, str]]:
        if not isinstance(items, list) or not items:
            raise ViewerError("no pictures given")
        idx = self.index(model)
        out = []
        for it in items:
            if not isinstance(it, dict):
                raise ViewerError("bad item")
            split, name = self.split(it.get("split")), safe_name(it.get("name"))
            if (split, name) not in idx.by_key:
                raise NotFound(f"{split}/{name} is not in {model}")
            out.append((split, name))
        return out

    def quarantine(self, model: str, items, confirm_harvest: bool = False, reason: str = VIEWER_REASON) -> dict:
        model = self.model(model)
        reason = safe_reason(reason)
        with self._wlock:
            pairs = self._pairs(model, items)
            self._guard(model, [n for _, n in pairs], confirm_harvest)
            moved_items = []
            for split, name in pairs:
                img = self.path_of(model, split, name)
                lbl = self.path_of(model, split, Path(name).stem + ".txt", "labels")
                moved = []
                for p in (img, lbl):
                    if p.exists():
                        dst = common.quarantine(p, model, reason)
                        moved.append([self._rel(p), self._rel(dst)])
                moved_items.append({"split": split, "name": name, "moved": moved})
            self.index(model).remove(pairs)
            self._restamp(model)
            act = self._log({"type": "quarantine", "model": model, "reason": reason, "items": moved_items})
        return {"ok": True, "action": act["id"], "count": len(pairs)}

    def quarantine_split_of(self, model: str, reason: str, name: str) -> str | None:
        return self._qsplit.get(f"_quarantine/{model}/{reason}/{name}")

    def restore(self, model: str, reason: str, items, confirm_harvest: bool = False, confirm_leak: bool = False) -> dict:
        """Put quarantined pictures (with their labels) back. items = [{name, split}]; split may be omitted
        for pictures the viewer itself removed (it remembers where they came from)."""
        model = self.model(model)
        reason = safe_reason(reason)
        if not isinstance(items, list) or not items:
            raise ViewerError("no pictures given")
        with self._wlock:
            plan, need_split, leaks = [], [], []
            idx = self.index(model)
            for it in items:
                name = safe_image_name((it or {}).get("name"))
                src_img = self.quarantine_file(model, reason, name)
                rel = f"_quarantine/{model}/{reason}/{name}"
                split = it.get("split") or self._qsplit.get(rel)
                if split not in SPLITS:
                    need_split.append(name)
                    continue
                orig = self._qname.get(rel, name)
                if orig == name and re.search(r"\.\d+$", Path(name).stem):          # curator's "name.1.jpg" collision copy
                    orig = name
                dst_img = self.path_of(model, split, orig)
                if dst_img.exists():
                    raise ViewerError(f"{split}/{orig} already exists in {model}; nothing was restored")
                src_lbl = src_img.with_suffix(".txt")
                lbl_rel = f"_quarantine/{model}/{reason}/{src_lbl.name}"
                plan.append((split, orig, src_img, dst_img, src_lbl if src_lbl.exists() else None,
                             self.path_of(model, split, Path(orig).stem + ".txt", "labels")))
                others = idx.groups().get(group_key(orig), set()) - {split}
                if others or reason in ("leak", "duplicate"):
                    leaks.append({"name": orig, "split": split, "also_in": sorted(others), "reason": reason})
            if need_split:
                raise NeedsConfirm("split", "Choose the split to restore these pictures to.", need_split[:50])
            self._guard(model, [p[1] for p in plan], confirm_harvest)
            if leaks and not confirm_leak:
                raise NeedsConfirm("leak", "Restoring these could put the same photo in two splits (data leak: the "
                                           "validation score would look better than it is). Restore anyway?", leaks[:20])
            moved_items = []
            for split, orig, src_img, dst_img, src_lbl, dst_lbl in plan:
                moved = []
                for a, b in ((src_img, dst_img), (src_lbl, dst_lbl)):
                    if a is None:
                        continue
                    b.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(a), str(b))
                    moved.append([self._rel(a), self._rel(b)])
                moved_items.append({"split": split, "name": orig, "moved": moved})
                idx.add(self._row_from_disk(model, split, orig))
            self._restamp(model)
            act = self._log({"type": "restore", "model": model, "reason": reason, "items": moved_items})
        return {"ok": True, "action": act["id"], "count": len(plan)}

    def set_flag(self, model: str, items, value: bool) -> dict:
        model = self.model(model)
        with self._wlock:
            pairs = self._pairs(model, items)
            flags = self.flags(model)
            before = [f"{s}/{n}" for s, n in pairs if f"{s}/{n}" in flags]
            for s, n in pairs:
                (flags.add if value else flags.discard)(f"{s}/{n}")
            self._save_flags(model)
            act = self._log({"type": "flag", "model": model, "keys": [f"{s}/{n}" for s, n in pairs],
                             "before": before, "value": bool(value)})
        return {"ok": True, "action": act["id"], "count": len(pairs), "flag": bool(value)}

    def edit_box(self, model: str, split: str, name: str, i, cls=None, remove: bool = False,
                 confirm_harvest: bool = False) -> dict:
        """Change the class of box `i` or remove it. The label file is rewritten as clean YOLO text."""
        model = self.model(model)
        split, name = self.split(split), safe_name(name)
        nc = len(self.class_names(model))
        with self._wlock:
            row = self.index(model).by_key.get((split, name))
            if row is None:
                raise NotFound(f"{split}/{name} is not in {model}")
            self._guard(model, [name], confirm_harvest)
            path = self.path_of(model, split, Path(name).stem + ".txt", "labels")
            if not path.exists():
                raise ViewerError("this picture has no label file")
            boxes = read_yolo(path)
            if not isinstance(i, int) or isinstance(i, bool) or not 0 <= i < len(boxes):
                raise ViewerError("no such box")
            if remove:
                del boxes[i]
            else:
                if not isinstance(cls, int) or isinstance(cls, bool) or not 0 <= cls < nc:
                    raise ViewerError(f"class must be 0..{nc - 1}")
                boxes[i] = (cls, *boxes[i][1:])
            before = path.read_text(encoding="utf-8", errors="replace")
            write_yolo(path, boxes)
            after = path.read_text(encoding="utf-8")
            self.index(model).by_key[(split, name)].update(self._row_from_disk(model, split, name))
            derive(self.index(model).by_key[(split, name)])
            self._restamp(model)
            act = self._log({"type": "box", "model": model, "split": split, "name": name, "before": before, "after": after})
        return {"ok": True, "action": act["id"], "boxes": self.index(model).by_key[(split, name)]["b"]}

    def _relabel_refs(self, model: str, items=None, rule=None) -> list[tuple[str, str, int]]:
        idx = self.index(model)
        refs = set()
        if rule is not None:
            if not isinstance(rule, dict):
                raise ViewerError("relabel rule must be an object")
            source, split, from_class = rule.get("source"), rule.get("split", "all"), rule.get("from_class")
            if not isinstance(source, str) or not source or len(source) > 120:
                raise ViewerError("choose a valid source")
            if split != "all" and split not in SPLITS:
                raise ViewerError(f"unknown split: {split!r}")
            if not isinstance(from_class, int) or isinstance(from_class, bool) or not 0 <= from_class < idx.nc:
                raise ViewerError(f"source class must be 0..{idx.nc - 1}")
            for row in idx.rows:
                if row["src"] != source or (split != "all" and row["s"] != split):
                    continue
                refs.update((row["s"], row["n"], i) for i, box in enumerate(row["b"]) if box[0] == from_class)
        else:
            if not isinstance(items, list) or not items:
                raise ViewerError("select at least one box")
            if len(items) > 10000:
                raise ViewerError("select at most 10,000 boxes at a time")
            for item in items:
                if not isinstance(item, dict):
                    raise ViewerError("bad box selection")
                split = self.split(item.get("split"))
                name = safe_image_name(item.get("name"))
                i = item.get("index")
                if not isinstance(i, int) or isinstance(i, bool) or i < 0:
                    raise ViewerError("box index must be a non-negative integer")
                row = idx.by_key.get((split, name))
                if row is None:
                    raise NotFound(f"{split}/{name} is not in {model}")
                if i >= len(row["b"]):
                    raise ViewerError(f"no box {i} in {split}/{name}")
                refs.add((split, name, i))
        return sorted(refs)

    def preview_relabel(self, model: str, items=None, rule=None, class_id=None) -> dict:
        model = self.model(model)
        if not isinstance(class_id, int) or isinstance(class_id, bool) or not 0 <= class_id < self.index(model).nc:
            raise ViewerError(f"target class must be 0..{self.index(model).nc - 1}")
        refs = self._relabel_refs(model, items, rule)
        idx = self.index(model)
        refs = [ref for ref in refs if idx.by_key[(ref[0], ref[1])]["b"][ref[2]][0] != class_id]
        touched = sorted({(s, n) for s, n, _ in refs})
        return {"boxes": len(refs), "pictures": len(touched), "target_class": class_id,
                "target_name": self.class_names(model)[class_id],
                "harvest_count": sum(1 for _, name in touched if name.startswith(HARVEST_PREFIX)),
                "samples": [{"split": s, "name": n, "index": i} for s, n, i in refs[:12]]}

    @staticmethod
    def _atomic_text(path: Path, text: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
        try:
            with open(tmp, "w", encoding="utf-8", newline="") as stream:
                stream.write(text)
                stream.flush()
                os.fsync(stream.fileno())
            os.replace(tmp, path)
        finally:
            tmp.unlink(missing_ok=True)

    def _atomic_yolo(self, path: Path, boxes: list) -> str:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
        try:
            write_yolo(tmp, boxes)
            after = tmp.read_text(encoding="utf-8")
            with open(tmp, "r+b") as stream:
                os.fsync(stream.fileno())
            os.replace(tmp, path)
            return after
        finally:
            tmp.unlink(missing_ok=True)

    def relabel(self, model: str, class_id, items=None, rule=None, confirm_harvest=False) -> dict:
        model = self.model(model)
        preview = self.preview_relabel(model, items, rule, class_id)
        if preview["boxes"] == 0:
            raise ViewerError("the selection already has the target class")
        refs = self._relabel_refs(model, items, rule)
        idx = self.index(model)
        changes: dict[tuple[str, str], set[int]] = defaultdict(set)
        for split, name, i in refs:
            if idx.by_key[(split, name)]["b"][i][0] != class_id:
                changes[(split, name)].add(i)
        with self._wlock:
            self._guard(model, [name for _, name in changes], confirm_harvest)
            records, written = [], []
            relabeled = self.relabeled(model)
            relabeled_before = set(relabeled)
            card_stale_before = self.card_stale(model)
            rows_before = {key: deepcopy(idx.by_key[key]) for key in changes}
            try:
                for (split, name), selected in sorted(changes.items()):
                    path = self.path_of(model, split, Path(name).stem + ".txt", "labels")
                    if not path.is_file():
                        raise ViewerError(f"label file missing for {split}/{name}")
                    before = path.read_text(encoding="utf-8", errors="replace")
                    boxes = read_yolo(path)
                    indexed = idx.by_key[(split, name)]["b"]
                    if len(boxes) != len(indexed) or any(boxes[i][0] != indexed[i][0] for i in selected):
                        raise ViewerError(f"labels changed while preparing {split}/{name}; refresh and retry")
                    updated = list(boxes)
                    for i in selected:
                        updated[i] = (class_id, *updated[i][1:])
                    after = self._atomic_yolo(path, updated)
                    written.append((path, before))
                    records.append({"split": split, "name": name, "before": before, "after": after,
                                    "was_relabeled": f"{split}/{name}" in relabeled})
                relabeled.update(f"{s}/{n}" for s, n in changes)
                self._save_relabeled(model)
                for split, name in changes:
                    idx.by_key[(split, name)].update(self._row_from_disk(model, split, name))
                    derive(idx.by_key[(split, name)])
                self._restamp(model)
                self._write_cache(idx)
                self._mark_card_stale(model)
                act = self._log({"type": "relabel", "model": model, "class_id": class_id,
                                 "boxes": preview["boxes"], "items": records})
            except Exception as error:
                rollback_errors = []
                for path, before in reversed(written):
                    try:
                        self._atomic_text(path, before)
                    except Exception as rollback_error:
                        rollback_errors.append(f"{path}: {rollback_error}")
                changed_after_rollback = False
                records_by_key = {
                    (item["split"], item["name"]): item for item in records
                }
                for key, item in records_by_key.items():
                    path = self.path_of(model, key[0], Path(key[1]).stem + ".txt", "labels")
                    try:
                        unchanged = path.read_text(encoding="utf-8", errors="replace") == item["before"]
                    except OSError as rollback_error:
                        rollback_errors.append(f"{path}: {rollback_error}")
                        unchanged = False
                    if unchanged:
                        (relabeled.add if item["was_relabeled"] else relabeled.discard)(f"{key[0]}/{key[1]}")
                    else:
                        relabeled.add(f"{key[0]}/{key[1]}")
                        changed_after_rollback = True
                for key, row in rows_before.items():
                    idx.by_key[key].clear()
                    idx.by_key[key].update(deepcopy(row))
                for split, name in changes:
                    try:
                        row = self._row_from_disk(model, split, name)
                        idx.by_key[(split, name)].update(row)
                        derive(idx.by_key[(split, name)])
                    except Exception as rollback_error:
                        rollback_errors.append(f"{split}/{name} index: {rollback_error}")
                try:
                    if not records:
                        relabeled.clear()
                        relabeled.update(relabeled_before)
                    self._save_relabeled(model)
                except Exception as rollback_error:
                    rollback_errors.append(f"relabeled flags: {rollback_error}")
                try:
                    stale = card_stale_before or changed_after_rollback
                    self._card_stale[model] = stale
                    stale_path = self._card_stale_file(model)
                    if stale:
                        self._atomic_text(stale_path, "true")
                    else:
                        stale_path.unlink(missing_ok=True)
                except Exception as rollback_error:
                    rollback_errors.append(f"dataset card status: {rollback_error}")
                try:
                    self._restamp(model)
                    self._write_cache(idx)
                except Exception as rollback_error:
                    rollback_errors.append(f"dataset index cache: {rollback_error}")
                if rollback_errors:
                    details = "; ".join(rollback_errors)
                    raise RuntimeError(
                        f"relabel failed ({type(error).__name__}: {error}); "
                        f"rollback was incomplete: {details}"
                    ) from error
                raise
        return {"ok": True, "action": act["id"], "boxes": preview["boxes"], "pictures": len(records)}

    def undo(self, model: str) -> dict:
        model = self.model(model)
        with self._wlock:
            act = next((a for a in reversed(self._stack) if a.get("model") == model), None)
            if act is None:
                raise ViewerError("nothing to undo")
            kind = act["type"]
            if kind == "flag":
                flags = self.flags(model)
                for k in act["keys"]:
                    flags.discard(k)
                flags.update(act["before"])
                self._save_flags(model)
                summary = {"type": "flag", "count": len(act["keys"])}
            else:
                self._guard(model, [a for it in act.get("items", [act]) for a in [it.get("name", "")] if a], True)
                idx = self.index(model)
                if kind == "box":
                    path = self.path_of(model, act["split"], Path(act["name"]).stem + ".txt", "labels")
                    if path.read_text(encoding="utf-8", errors="replace") != act["after"]:
                        raise ViewerError("the label changed since: it cannot be undone safely")
                    path.write_text(act["before"], encoding="utf-8")
                    idx.by_key[(act["split"], act["name"])].update(self._row_from_disk(model, act["split"], act["name"]))
                    derive(idx.by_key[(act["split"], act["name"])])
                    summary = {"type": "box", "split": act["split"], "name": act["name"]}
                elif kind == "relabel":
                    plans = []
                    for it in act["items"]:
                        path = self.path_of(model, it["split"], Path(it["name"]).stem + ".txt", "labels")
                        if path.read_text(encoding="utf-8", errors="replace") != it["after"]:
                            raise ViewerError(f"the label changed since: {it['split']}/{it['name']} cannot be undone safely")
                        plans.append((it, path))
                    written = []
                    try:
                        for it, path in plans:
                            self._atomic_text(path, it["before"])
                            written.append((path, it["after"]))
                    except Exception:
                        for path, after in reversed(written):
                            self._atomic_text(path, after)
                        raise
                    marked = self.relabeled(model)
                    for it, _ in plans:
                        key = f"{it['split']}/{it['name']}"
                        (marked.add if it["was_relabeled"] else marked.discard)(key)
                        idx.by_key[(it["split"], it["name"])].update(
                            self._row_from_disk(model, it["split"], it["name"]))
                        derive(idx.by_key[(it["split"], it["name"])])
                    self._save_relabeled(model)
                    self._restamp(model)
                    self._write_cache(idx)
                    self._mark_card_stale(model)
                    summary = {"type": "relabel", "count": act["boxes"], "pictures": len(plans)}
                else:
                    for it in act["items"]:
                        for a, b in it["moved"]:
                            src, dst = self.datasets / b, self.datasets / a
                            if not src.exists() or dst.exists():
                                raise ViewerError(f"cannot move {b} back: it is missing or {a} exists")
                    for it in act["items"]:
                        for a, b in it["moved"]:
                            dst = self.datasets / a
                            dst.parent.mkdir(parents=True, exist_ok=True)
                            shutil.move(str(self.datasets / b), str(dst))
                        if kind == "quarantine":
                            idx.add(self._row_from_disk(model, it["split"], it["name"]))
                    if kind == "restore":
                        idx.remove([(it["split"], it["name"]) for it in act["items"]])
                    summary = {"type": kind, "count": len(act["items"])}
                self._restamp(model)
            self._log({"type": "undo", "model": model, "of": act["id"]})
        return {"ok": True, "undone": summary}

    def can_undo(self, model: str) -> bool:
        return any(a.get("model") == model for a in self._stack)

    # ----------------------------------------------------------------- quarantine browsing

    def quarantine_list(self, model: str, reason: str | None = None, offset: int = 0, limit: int = 150) -> dict:
        model = self.model(model)
        base = self.qroot / model
        if reason is None:
            reasons = []
            for p in sorted(base.iterdir()) if base.exists() else []:
                if p.is_dir() and _REASON.match(p.name):
                    n = sum(1 for e in os.scandir(p) if os.path.splitext(e.name)[1].lower() in IMAGE_EXT)
                    reasons.append({"reason": p.name, "count": n})
            return {"reasons": reasons}
        folder = base / safe_reason(reason)
        if not folder.is_dir():
            raise NotFound(reason)
        names = sorted((e.name, e.stat().st_size) for e in os.scandir(folder)
                       if os.path.splitext(e.name)[1].lower() in IMAGE_EXT)
        limit = min(PAGE_MAX, max(1, int(limit)))
        page = [{"name": n, "bytes": z, "split": self._qsplit.get(f"_quarantine/{model}/{reason}/{n}"),
                 "harvest": n.startswith(HARVEST_PREFIX)} for n, z in names[max(0, offset):offset + limit]]
        return {"reason": reason, "total": len(names), "offset": offset, "items": page}

    # ----------------------------------------------------------------- cleaning (the curator, as a background job)

    def _new_job(self, kind: str, model: str) -> dict:
        job = {"id": uuid.uuid4().hex[:12], "kind": kind, "model": model, "state": "running", "done": 0, "total": 0,
               "text": "starting", "result": None, "error": None, "started": time.time()}
        with self._lock:
            self._jobs[job["id"]] = job
        return job

    def job(self, job_id: str) -> dict:
        with self._lock:
            job = self._jobs.get(job_id)
        if job is None:
            raise NotFound(f"no job {job_id!r}")
        return dict(job)

    def _running_job(self, model: str) -> dict | None:
        with self._lock:
            return next((j for j in self._jobs.values() if j["model"] == model and j["state"] == "running"
                         and j["kind"] in ("clean", "apply", "report")), None)

    def start_report(self, model: str) -> dict:
        model = self.model(model)
        running = self._running_job(model)
        if running:
            return dict(running)
        with self._wlock:
            self._guard(model)
            try:
                active = self.busy(fresh=True)
            except Exception as e:
                raise TrainingBusy(f"Could not check running trainings ({type(e).__name__}); no report was started.")
            if active:
                raise TrainingBusy(f"Cannot regenerate dataset cards while training is running: {', '.join(sorted(active))}.")
            job = self._new_job("report", model)

        def work():
            try:
                result = subprocess.run(
                    [sys.executable, str(LAB / "data.py"), "report"],
                    cwd=str(LAB),
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    check=False,
                )
                output = (result.stdout + "\n" + result.stderr).strip()
                job["text"] = output[-2000:] or "Dataset cards regenerated."
                if result.returncode:
                    job.update(state="error", error=f"data.py report exited with code {result.returncode}")
                    return
                self._clear_card_stale(model)
                job.update(state="done", done=1, total=1, result={"ok": True})
            except Exception as e:
                job.update(state="error", error=f"{type(e).__name__}: {e}")

        threading.Thread(target=work, daemon=True).start()
        return dict(job)

    @staticmethod
    def _progress_logger(job: dict):
        def log(text: str) -> None:
            text = str(text).strip()
            job["text"] = text
            m = re.search(r"([\d,]+) / ([\d,]+)", text) or re.search(r"([\d,]+) (pictures)", text)
            if m:
                if m.group(2) == "pictures":
                    job["total"] = int(m.group(1).replace(",", ""))
                else:
                    job["done"], job["total"] = int(m.group(1).replace(",", "")), int(m.group(2).replace(",", ""))
        return log

    def start_clean(self, model: str, curate_fn=None) -> dict:
        """Dry run of the curator (data_tools.curate.curate_model): nothing changes; the findings are listed."""
        model = self.model(model)
        running = self._running_job(model)
        if running:
            return dict(running)
        job = self._new_job("clean", model)
        fn = curate_fn or curate.curate_model

        def work():
            captured: list = []
            real_scan = curate.scan

            def spy(m):                                  # the curator's own list of pictures, to show examples
                items = real_scan(m)
                captured.extend(items)
                return items
            try:
                with mock.patch.object(curate, "scan", spy):
                    report = fn(model, apply=False, log=self._progress_logger(job))
                job["result"] = {"report": report, "findings": self.findings(captured)}
                job["state"] = "done"
            except Exception as e:
                job.update(state="error", error=f"{type(e).__name__}: {e}")

        threading.Thread(target=work, daemon=True).start()
        return dict(job)

    @staticmethod
    def findings(items) -> dict:
        """Group the curator's verdicts by issue, with a few sample pictures each."""
        groups: dict[str, list] = defaultdict(list)
        for it in items:
            if it.action:
                groups[it.action].append(it)
            elif "no_boxes" in it.issues or "duplicate_of_protected" in it.issues or "duplicate_kept_protected" in it.issues:
                for issue in it.issues:
                    if issue in ("no_boxes", "duplicate_of_protected", "duplicate_kept_protected"):
                        groups[f"kept_{issue}"].append(it)
            if it.fixed_labels and not it.action:
                groups["fixed_boxes"].append(it)
            if "resave" in it.issues and not it.action:
                groups["resave"].append(it)
        return {k: {"count": len(v), "protected": sum(1 for i in v if i.protected),
                    "samples": [{"split": i.split, "name": i.img.name} for i in v[:12]]}
                for k, v in sorted(groups.items())}

    def apply_clean(self, model: str, confirm=False, curate_fn=None) -> dict:
        model = self.model(model)
        if confirm is not True:
            raise NeedsConfirm("apply", "Apply cleaning moves pictures to the quarantine and rewrites labels. Continue?")
        running = self._running_job(model)
        if running:
            raise ViewerError("a cleaning job is already running for this dataset")
        with self._wlock:
            self._guard(model)
            self._applying.add(model)
        job = self._new_job("apply", model)
        fn = curate_fn or curate.curate_model

        def work():
            try:
                report = fn(model, apply=True, log=self._progress_logger(job))
                self._log({"type": "clean_apply", "model": model, "dropped": report.get("dropped"),
                           "fixed_labels": report.get("fixed_labels"), "kept": report.get("kept")})
                job["result"] = {"report": report}
                job["state"] = "done"
            except Exception as e:
                job.update(state="error", error=f"{type(e).__name__}: {e}")
            finally:
                self._applying.discard(model)
                self._stack = [a for a in self._stack if a.get("model") != model]    # the folders changed under them
                self.start_indexing(model, force=True)

        threading.Thread(target=work, daemon=True).start()
        return dict(job)


ASPECT_LABELS = ["<0.5", "0.5-0.8", "0.8-1.25", "1.25-2", "2-3", ">3"]


def _aspect_bin(a: float) -> str:
    for edge, label in ((0.5, "<0.5"), (0.8, "0.5-0.8"), (1.25, "0.8-1.25"), (2, "1.25-2"), (3, "2-3")):
        if a < edge:
            return label
    return ">3"
