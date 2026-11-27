"""
folder_labeller.py - The Labeller: label EVERY picture of a folder for one model, then export a clean dataset.

  scan      lists every picture under a folder (the backend's evidence folder, or any folder) and queues each one
            for the chosen model. Nothing is copied: the pictures stay where they are.
  prepare   when the labelling page asks for a page of pictures, each one gets a hard link (or a copy, on another
            drive) in the inbox, so the same labelling screen as in the Forensic Analyzer can show it.
  suggest   pre-draws the boxes of the model that is deployed (CPU only), so a person only fixes them.
  export    writes a clean YOLO dataset for the model to ANY folder (an external drive too) and MOVES the labelled
            pictures there: train / val split, labels, data.yaml, a report. Nothing half-decided is exported.

The folder items are kept out of the normal "all analyses" harvest views (see store.FOLDER_SOURCE), so the Harvest tab
and "Add to dataset" never touch them. Moving files out of the evidence folder makes the photos of the tickets that
used them disappear from the review screens: that is the point of the Labeller, and why export asks first.
"""
import hashlib
import json
import os
import re
import shutil
import threading
import time
from pathlib import Path

import cv2
import yaml
from PIL import Image

from .accept import VAL_SHARE, is_training, pick_split
from .collect import SUGGEST_CONF, Detectors, suggest
from .config import FOCUS_MODELS, MODELS, Paths, base_model, class_names, dataset_class_ids, dataset_class_names, known_model, model_spec
from . import ledger, pii_blur
from .frames import FRAME_CONF, anchor_boxes, anchor_names
from .store import FOLDER_SOURCE, Item, Store, make_id, yolo_text

IMAGE_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}
SKIP_DIRS = {"harvest_inbox", "__pycache__", ".git"}
_TIME_RE = re.compile(r"(\d{10,})")
_TRIED: set[str] = set()                     # pictures the model already looked at and found nothing in (this session)


def folder_task(folder) -> str:
    """The name that ties the pictures of one folder together (it is a valid analysis-style id: letters, digits, _)."""
    return "folder_" + hashlib.sha1(str(Path(folder).resolve()).lower().encode("utf-8")).hexdigest()[:8]


def picture_group(name: str) -> str:
    """Pictures taken within the same minute (millisecond file names) share a group, so they land on the same side of the
    train / validation split and near-identical frames never end up on both sides."""
    m = _TIME_RE.search(Path(name).stem)
    return f"t{int(m.group(1)) // 60000}" if m else Path(name).stem


def scan(paths: Paths, store: Store, model: str, folder, batch: int = 2000) -> dict:
    """Queue every picture under [folder] for [model]. Safe to repeat: known pictures are not added twice.
    A picture the ledger says is already labelled for this model (matched by content, so a rename does not fool it) is left out."""
    if not known_model(model):
        raise KeyError(model)
    root = Path(folder)
    if not root.is_dir():
        raise ValueError(f"not a folder: {folder}")
    task = folder_task(root)
    found = new = already = 0
    done = ledger.load(paths, model)                       # sha1 -> entry: pictures already labelled for THIS model
    done_sizes = {e.get("size") for e in done.values()}    # only pictures of a matching size are worth reading
    pending: list[Item] = []
    for dirpath, dirnames, files in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in sorted(files):
            if Path(name).suffix.lower() not in IMAGE_EXT:
                continue
            path = os.path.join(dirpath, name)
            found += 1
            if done:
                try:
                    if os.path.getsize(path) in done_sizes and ledger.digest(path) in done:
                        already += 1
                        continue
                except OSError:
                    pass
            pending.append(Item(id=make_id("folder", model, path.lower()), model=model, state="label", source=FOLDER_SOURCE,
                                reason=f"Picture {name}", group_id=picture_group(name), task_id=task, priority=5,
                                src_path=path))
            if len(pending) >= batch:
                new += store.add_many(pending)
                pending.clear()
    if pending:
        new += store.add_many(pending)
    return {"task": task, "folder": str(root), "found": found, "new": new, "already_labelled": already}


def _link_or_copy(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(src, dst)                      # same drive: no extra space
    except OSError:
        shutil.copy2(src, dst)                 # another drive, or a drive without links


def _size(path: Path) -> tuple[int, int]:
    with Image.open(path) as im:               # reads the header only
        return im.size


def prepare(store: Store, items: list) -> list:
    """Make each picture showable by the labelling screen. Pictures that vanished from the folder are set aside
    (state 'skipped') and left out of the returned list."""
    shown = []
    for item in items:
        if not item.src_path:
            shown.append(item)
            continue
        src = Path(item.src_path)
        if not src.exists():
            store.skip(item.id)
            continue
        dst = store.image_path(item.model, item.id)
        if not dst.exists():
            _link_or_copy(src, dst)
        if not item.width:
            try:
                item.width, item.height = _size(dst)
                store.set_size(item.id, item.width, item.height)
            except Exception:
                store.skip(item.id)            # not a readable picture
                continue
        shown.append(item)
    return shown


def suggest_batch(paths: Paths, store: Store, model: str, task: str, n: int = 40, detectors: Detectors | None = None,
                  heads: bool = False, plates: bool = False) -> int:
    """Pre-draw the boxes of the deployed model on the next [n] pictures that have none, and (when asked) a first guess of
    what to blur (heads of people, plates of vehicles) in the separate blur layer. Returns how many pictures got a guess."""
    detectors = detectors or Detectors(paths)
    det = detectors.get(model)
    heads, plates = pii_blur.allowed(model, heads, plates)
    if det is None and not (heads or plates):
        return 0
    wants_blur = bool(heads or plates)
    todo = [i for i in store.items(model, ("label", "check"), task=task) if i.id not in _TRIED
            and ((i.state == "label" and not i.suggested and det is not None) or (wants_blur and not i.blur))][:n]
    got = 0
    for item in prepare(store, todo):
        img = cv2.imread(str(store.image_path(model, item.id)))
        if img is None:
            continue
        h, w = img.shape[:2]
        if det is None or item.state != "label" or item.suggested:
            boxes = []
        elif model in FOCUS_MODELS:                          # the big model's guess, kept to this class only (renumbered)
            ids = dataset_class_ids(paths, model)
            boxes = [[ids.index(d.cls), *d.yolo(w, h)[1:]] for d in det.detect(img, conf=SUGGEST_CONF) if d.cls in ids]
        elif model == "primary_anchor":
            boxes = anchor_boxes(det.detect(img, conf=FRAME_CONF), det.names, anchor_names(paths), w, h)
        else:
            boxes = suggest(det, img, "find_plate" if model == "plate_specialist" else "riders", w, h) or []
        areas = []
        if wants_blur and not item.blur:
            areas = [pii_blur.to_yolo(b, w, h, 0) for b in pii_blur.find_pii(
                img, heads=heads, plates=plates, vehicle_detector=detectors.get("primary_anchor"),
                plate_detector=detectors.get("plate_specialist"))]
        _TRIED.add(item.id)
        if boxes:
            store.set_suggestion(item.id, boxes)
        if areas:
            store.set_blur_guess(item.id, areas)
        if boxes or areas:
            got += 1
    return got


def _inside(child: Path, parent: Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


_digest = ledger.digest


def _safe_move(src: Path, dst: Path) -> None:
    """Copy, check the copy has the same size, then remove the original (also works between drives)."""
    shutil.copy2(src, dst)
    if dst.stat().st_size != src.stat().st_size:
        dst.unlink(missing_ok=True)
        raise OSError(f"the copy of {src.name} is not the same size: the original was kept")
    src.unlink()


class Exporter:
    """Writes finished pictures as a clean dataset under <dest>/<model>/, one picture at a time, and moves them there.

    One of these serves the "Build the dataset" button (many pictures at once) and the "send each picture right away" mode
    (one picture each time a person finishes it). Clean means: a picture with no box is a real "nothing here" example,
    only readable pictures, no duplicate picture twice, a group (same minute) never split over train and val."""

    def __init__(self, paths: Paths, store: Store, model: str, task: str, dest, move: bool = True,
                 val_share: float = VAL_SHARE, keep_view: bool = False):
        if not known_model(model):
            raise KeyError(model)
        self.paths, self.store, self.model, self.task = paths, store, model, task
        self.move, self.val_share = bool(move), val_share
        self.keep_view = keep_view          # leave the inbox link, so the labelling screen can still show a picture it just sent
        self.names = dataset_class_names(paths, model)       # the dataset's own class list (a focus target: its big model's)
        self.ids = dataset_class_ids(paths, model)            # labelling class number -> dataset class number
        self.out = Path(dest) / model
        big = base_model(model)
        if _inside(self.out, paths.datasets / big) and is_training(big):
            raise RuntimeError(f"{model_spec(big)['title']} is training right now, and that folder is its dataset.")
        for folder in {Path(i.src_path).parent for i in store.items(model, ("label", "check", "ready", "skipped"), task=task) if i.src_path}:
            if _inside(self.out, folder):
                raise ValueError("the destination is inside the folder being labelled: choose another folder")
        for split in ("train", "val"):
            (self.out / "images" / split).mkdir(parents=True, exist_ok=True)
            (self.out / "labels" / split).mkdir(parents=True, exist_ok=True)
        self.seen: dict[str, str] = {}
        for existing in (self.out / "images").rglob("*"):
            if existing.is_file():
                self.seen[_digest(existing)] = existing.name
        self.per_class: dict[int, int] = {}
        self.result = {"model": model, "task": task, "ready": 0, "exported": 0, "train": 0, "val": 0, "empty_labels": 0,
                       "duplicates": 0, "unreadable": 0, "missing": 0, "failed": 0, "moved": self.move, "per_class": {},
                       "blurred_pictures": 0, "blurred_regions": 0, "dest": str(self.out)}
        self._lock = threading.Lock()
        (self.out / "data.yaml").write_text(yaml.safe_dump(
            {"path": ".", "train": "images/train", "val": "images/val", "nc": len(self.names),
             "names": {i: n for i, n in enumerate(self.names)}}, sort_keys=False), encoding="utf-8")

    def add(self, item: Item) -> str:
        """Export one finished picture. Returns what happened: exported, duplicate, unreadable, missing or failed."""
        with self._lock:
            return self._add(item)

    def _add(self, item: Item) -> str:
        r, out, model = self.result, self.out, self.model
        src = Path(item.src_path or "")
        if not src.is_file():
            r["missing"] += 1
            return "missing"
        picture = cv2.imread(str(src))
        if picture is None:
            r["unreadable"] += 1
            return "unreadable"
        src_size = src.stat().st_size
        label_boxes = [(self.ids[int(b[0])] if 0 <= int(b[0]) < len(self.ids) else int(b[0]), *b[1:]) for b in item.boxes]   # dataset class numbers
        # (labels and blur areas are kept apart: blur is never a label)
        blur_boxes = item.blur
        digest = _digest(src)
        if digest in self.seen:
            r["duplicates"] += 1
            return "duplicate"
        split = pick_split(item.group_id, item.split_hint, self.val_share)
        name = src.name
        if (out / "images" / split / name).exists():
            name = f"{src.stem}_{item.id[:6]}{src.suffix.lower()}"
        target = out / "images" / split / name
        try:
            if blur_boxes:                                 # the saved copy is blurred; the original (with the faces) is removed when moving
                pii_blur.blur_yolo(picture, blur_boxes)
                if not cv2.imwrite(str(target), picture, [cv2.IMWRITE_JPEG_QUALITY, 95]):
                    raise OSError(f"could not write {target.name}")
                if self.move:
                    src.unlink()
            elif self.move:
                _safe_move(src, target)
            else:
                shutil.copy2(src, target)
        except OSError:
            target.unlink(missing_ok=True)
            r["failed"] += 1
            return "failed"
        (out / "labels" / split / f"{Path(name).stem}.txt").write_text(yolo_text(label_boxes), encoding="utf-8")
        self.seen[digest] = name
        self.store.mark_accepted(item.id, name)
        try:                                               # the mark that outlives the inbox: central ledger + a copy beside the dataset
            mark = dict(name=src.name, folder=str(src.parent), size=src_size, labels=len(label_boxes), blur=len(blur_boxes),
                        status="exported", moved_to=str(target) if self.move else None, copies=(out / ledger.COPY_NAME,))
            ledger.record(self.paths, model, sha1=digest, **mark)
            if blur_boxes:                                 # the blurred copy is a different file: remember it too
                ledger.record(self.paths, model, sha1=ledger.digest(target), **{**mark, "size": target.stat().st_size})
        except OSError:
            pass                                           # the ledger is a memory aid; it must never fail an export
        if self.move:
            self.store.set_source(item.id, str(target))
            if not self.keep_view:
                self.store.image_path(model, item.id).unlink(missing_ok=True)      # the inbox link
        r["exported"] += 1
        r[split] += 1
        r["empty_labels"] += 0 if label_boxes else 1
        if blur_boxes:
            r["blurred_pictures"] += 1
            r["blurred_regions"] += len(blur_boxes)
        for b in label_boxes:
            self.per_class[int(b[0])] = self.per_class.get(int(b[0]), 0) + 1
        return "exported"

    def finish(self) -> dict:
        """Write report.json with the totals so far and return them."""
        with self._lock:
            self.result["per_class"] = {self.names[c] if c < len(self.names) else str(c): n for c, n in sorted(self.per_class.items())}
            (self.out / "report.json").write_text(json.dumps({**self.result, "when": time.strftime("%Y-%m-%d %H:%M:%S")}, indent=2),
                                                  encoding="utf-8")
            return dict(self.result)


def export(paths: Paths, store: Store, model: str, task: str, dest, move: bool = True,
           val_share: float = VAL_SHARE) -> dict:
    """Write the finished pictures of one folder as a clean dataset under <dest>/<model>/ and move them there.
    (A picture with no box is a real "nothing here" example; see [Exporter] for the rules.)"""
    if not known_model(model):
        raise KeyError(model)
    ready = store.items(model, ("ready",), task=task)
    if not ready:                                          # nothing to write: leave the destination alone
        return {"model": model, "task": task, "ready": 0, "exported": 0, "train": 0, "val": 0, "empty_labels": 0,
                "duplicates": 0, "unreadable": 0, "missing": 0, "failed": 0, "moved": bool(move), "per_class": {},
                "blurred_pictures": 0, "blurred_regions": 0, "dest": str(Path(dest) / model)}
    exporter = Exporter(paths, store, model, task, dest, move, val_share)
    exporter.result["ready"] = len(ready)
    for item in ready:
        exporter.add(item)
    return exporter.finish()
