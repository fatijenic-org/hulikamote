"""
decisions.py - the journal of box decisions, so careful hand work is never lost.

Why: a person looked at thousands of truck boxes and said "this one is a pickup". That work lives in the label files, and a
re-merge (scripts/fetch_datasets.py) or `data.py curate --apply` rewrites label files. This journal keeps every decision on its
own, one JSON line per box:

    datasets/_decisions/<model>.jsonl

    {"v": 1, "ts": ..., "action": "<id>", "split": "train", "name": "srcA__one.jpg", "box": [cx, cy, w, h],
     "from": "truck", "decision": "move", "to": "pickup"}        or   "decision": "keep"   (looked at, NOT changed)

A box is found again by its picture name and its place in the picture (not by its position in the file), so it survives a
re-merge. `reapply()` puts the "move" decisions back. Also here: `add_class_to_yaml()`, which adds a class to data.yaml
WITHOUT changing the old class numbers.

Plain functions and one small class, no dataset needed to test them.
"""
from __future__ import annotations

import json
import os
import re
import threading
import time
import uuid
from pathlib import Path

from . import common

DIR_NAME = "_decisions"
DEFAULT_CLASS = "pickup"
TOLERANCE = 0.0015                     # how far a box may have moved (as a share of the picture) and still be "the same box"
_CLASS_NAME = re.compile(r"^[a-z][a-z0-9_]{0,29}$")
_NAMES_LINE = re.compile(r"^names\s*:\s*(#.*)?$")
_ENTRY = re.compile(r"^(\s+)(\d+)\s*:\s*([^#\r\n]*?)\s*(#.*)?$")
_LOCKS: dict[str, threading.RLock] = {}


class DecisionError(ValueError):
    """Something about a decision or class name is wrong (plain words for the person)."""


def _lock(path: Path) -> threading.RLock:
    return _LOCKS.setdefault(str(path), threading.RLock())


def journal_file(datasets: Path, model: str) -> Path:
    return Path(datasets) / DIR_NAME / f"{model}.jsonl"


def box_sig(name: str, box) -> str:
    """The identity of one box: picture name + its place (3 decimals, enough to tell boxes of one picture apart)."""
    cx, cy, w, h = (float(v) for v in box[-4:])
    return f"{name}|{cx:.3f}|{cy:.3f}|{w:.3f}|{h:.3f}"


def safe_class_name(name) -> str:
    if not isinstance(name, str) or not _CLASS_NAME.match(name):
        raise DecisionError("A class name uses lower-case letters, digits and _ (for example: pickup).")
    return name


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    try:
        with open(tmp, "w", encoding="utf-8", newline="") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    finally:
        tmp.unlink(missing_ok=True)


# --------------------------------------------------------------------------- the journal

class Journal:
    """Reads and writes the journal of one dataset. The latest decision about a box wins."""

    def __init__(self, datasets: Path, model: str):
        self.path = journal_file(datasets, model)
        self._stamp: tuple | None = None
        self._by_sig: dict[str, dict] = {}

    def _load(self) -> None:
        with _lock(self.path):
            try:
                st = self.path.stat()
                stamp = (st.st_mtime_ns, st.st_size)
            except OSError:
                self._stamp, self._by_sig = None, {}
                return
            if stamp == self._stamp:
                return
            by_sig: dict[str, dict] = {}
            with open(self.path, encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        e = json.loads(line)
                        by_sig[box_sig(e["name"], e["box"])] = e
                    except (ValueError, KeyError, TypeError):
                        continue                                  # a broken line never breaks the rest
            self._stamp, self._by_sig = stamp, by_sig

    def entries(self) -> dict[str, dict]:
        self._load()
        return self._by_sig

    def get(self, name: str, box) -> dict | None:
        return self.entries().get(box_sig(name, box))

    def append(self, rows: list[dict]) -> None:
        if not rows:
            return
        with _lock(self.path):
            self.path.parent.mkdir(parents=True, exist_ok=True)
            with open(self.path, "a", encoding="utf-8", newline="\n") as f:
                for r in rows:
                    f.write(json.dumps(r, ensure_ascii=False) + "\n")
            self._stamp = None

    def make(self, action: str, split: str, name: str, box, from_name: str, decision: str, to_name: str | None = None) -> dict:
        row = {"v": 1, "ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "action": action, "split": split, "name": name,
               "box": [round(float(v), 5) for v in box[-4:]], "from": from_name, "decision": decision}
        if to_name:
            row["to"] = to_name
        return row

    def drop_action(self, action: str) -> int:
        """Take back everything one action wrote (the undo of a decision). Returns how many lines went."""
        with _lock(self.path):
            try:
                lines = self.path.read_text(encoding="utf-8", errors="replace").splitlines()
            except OSError:
                return 0
            keep, dropped = [], 0
            for line in lines:
                try:
                    if json.loads(line).get("action") == action:
                        dropped += 1
                        continue
                except ValueError:
                    pass
                keep.append(line)
            if dropped:
                _atomic_write(self.path, "\n".join(keep) + ("\n" if keep else ""))
                self._stamp = None
            return dropped

    def counts(self, from_name: str | None = None, to_name: str = DEFAULT_CLASS) -> dict:
        """reviewed = boxes of class [from_name] that were looked at; moved = how many of them became [to_name]."""
        reviewed = moved = kept = 0
        for e in self.entries().values():
            if from_name and e.get("from") != from_name:
                continue
            reviewed += 1
            if e.get("decision") == "move" and e.get("to") == to_name:
                moved += 1
            elif e.get("decision") == "keep":
                kept += 1
        return {"reviewed": reviewed, "moved": moved, "kept": kept}


# --------------------------------------------------------------------------- data.yaml: add a class

def class_ids(yaml_path: Path) -> dict[str, int]:
    names = common.load_yaml(yaml_path).get("names") or {}
    if isinstance(names, dict):
        return {str(v): int(k) for k, v in names.items()}
    return {str(v): i for i, v in enumerate(names)}


def add_class_to_yaml(yaml_path: Path, name: str, note: str = "added in the dataset viewer") -> tuple[int, bool]:
    """Add [name] as the NEXT class number (old numbers never change) and raise `nc`. -> (class id, whether it was added).
    The file is edited as text so its comments stay. Safe to repeat: a class that exists is just returned."""
    name = safe_class_name(name)
    existing = class_ids(yaml_path)
    if name in existing:
        return existing[name], False
    text = Path(yaml_path).read_text(encoding="utf-8")
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.splitlines(keepends=True)
    start = next((i for i, ln in enumerate(lines) if _NAMES_LINE.match(ln.rstrip("\r\n"))), None)
    if start is None:
        raise DecisionError("data.yaml must list the classes one per line (names:, then 0: name ...) to add a class here.")
    last, indent, top = start, "  ", -1
    for i in range(start + 1, len(lines)):
        m = _ENTRY.match(lines[i].rstrip("\r\n"))
        if m:
            last, indent, top = i, m.group(1), max(top, int(m.group(2)))
        elif lines[i].strip() == "" or lines[i].lstrip().startswith("#"):
            continue
        else:
            break
    if top < 0:
        raise DecisionError("data.yaml has no class list to add to.")
    new_id = max(existing.values(), default=top) + 1
    lines.insert(last + 1, f"{indent}{new_id}: {name}   # {note}{nl}")
    out = "".join(lines)
    out = re.sub(r"(?m)^nc\s*:\s*\d+", f"nc: {len(existing) + 1}", out, count=1)
    _atomic_write(Path(yaml_path), out)
    return new_id, True


# --------------------------------------------------------------------------- put the decisions back

def _label_file(base: Path, name: str) -> tuple[str, Path] | None:
    stem = Path(name).stem
    for split in common.SPLITS:
        p = base / "labels" / split / f"{stem}.txt"
        if p.is_file():
            return split, p
    return None


def reapply(datasets: Path, model: str, to_name: str = DEFAULT_CLASS, is_training=None, on_changed=None) -> dict:
    """Put every "move" decision (box -> [to_name]) back into the label files. Run it after a re-merge or after
    `data.py curate --apply`. Adds the class to data.yaml when the re-merge removed it. Never touches a box that now has a class the
    decision did not come from (the source data changed: that needs a person)."""
    datasets = Path(datasets)
    if is_training is not None and is_training(model):
        raise DecisionError(f"{model} is training right now: nothing was changed.")
    base = datasets / model
    to_id, _ = add_class_to_yaml(base / "data.yaml", to_name)
    ids = class_ids(base / "data.yaml")
    by_id = {v: k for k, v in ids.items()}
    moves: dict[str, list[dict]] = {}
    for e in Journal(datasets, model).entries().values():
        if e.get("decision") == "move" and e.get("to") == to_name:
            moves.setdefault(e["name"], []).append(e)
    out = {"decisions": sum(len(v) for v in moves.values()), "applied": 0, "already": 0, "image_missing": 0, "box_missing": 0,
           "different_class": 0, "class": to_name, "class_id": to_id}
    for name, entries in moves.items():
        found = _label_file(base, name)
        if found is None:
            out["image_missing"] += len(entries)
            continue
        split, path = found
        boxes = common.read_yolo(path)
        changed = False
        for e in entries:
            target = e["box"]
            best, gap = None, TOLERANCE
            for i, b in enumerate(boxes):
                d = max(abs(b[1] - target[0]), abs(b[2] - target[1]), abs(b[3] - target[2]), abs(b[4] - target[3]))
                if d < gap:
                    best, gap = i, d
            if best is None:
                out["box_missing"] += 1
                continue
            if boxes[best][0] == to_id:
                out["already"] += 1
                continue
            if e.get("from") and by_id.get(boxes[best][0]) != e["from"]:
                out["different_class"] += 1
                continue
            boxes[best] = (to_id, *boxes[best][1:])
            out["applied"] += 1
            changed = True
        if changed:
            _atomic_write(path, "\n".join(f"{c} {cx:.6f} {cy:.6f} {w:.6f} {h:.6f}" for c, cx, cy, w, h in boxes))
            if on_changed:
                on_changed(split, name)
    return out
