"""
pairs.py - "Are these the same car?" questions, and what the answers teach the car matcher (ReID).

The tracker sometimes loses a car and gives it a new number a moment later (an "ID jump"). Each analysis
already holds many clean photos of every ticketed car, so the questions come from there, no video needed:

    gap     car A was last seen about where and when car B first appears (same car, new number?)
    twin    two cars seen at the SAME time that look alike (one car boxed twice, or two look-alikes?)

A person answers Same / Different / Not sure. The answer is written the way the review screens already
write theirs: datasets/reid/images/<task>/<identity>/<crop>.jpg (same folder = same car) and one line in
datasets/reid/decisions.jsonl. Nothing in the backend or in the tickets changes.
"""
import json
import math
import shutil
import time

import cv2
import numpy as np

from .config import Paths
from .sources import Frame, Ticket, tickets
from .store import Pair, Store, make_id

MAX_GAP_PAIRS = 8          # questions per analysis: "same car, new number?"
MAX_TWIN_PAIRS = 4         # questions per analysis: "two look-alikes seen together"
MAX_GAP_SECONDS = 4.0      # a car that comes back later than this is not "the same moment"
MIN_LOOK = 0.55            # below this two cars do not look alike enough to be worth a question
MIN_TWIN_LOOK = 0.8
MIN_TWIN_OVERLAP = 0.5     # seconds both were on screen
MIN_SIDE = 48              # pixels: smaller crops tell nothing about a car


def identity(task_id: str, uid: str) -> str:
    """The folder name the review screens use for one car: same as hulikamote_backend/routers/forensic.py."""
    return f"{task_id[:8]}_{uid}"


# ── how alike two photos look: colour layout + colour mix. Cheap, deterministic, no model to go stale ──

def look(image) -> tuple:
    small = cv2.resize(image, (24, 48), interpolation=cv2.INTER_AREA)
    lab = cv2.cvtColor(small, cv2.COLOR_BGR2LAB)
    layout = cv2.resize(lab, (3, 6), interpolation=cv2.INTER_AREA).astype(np.float32).reshape(-1)
    hsv = cv2.cvtColor(small, cv2.COLOR_BGR2HSV)
    mix = cv2.calcHist([hsv], [0, 1], None, [12, 4], [0, 180, 0, 256]).flatten()
    return layout, mix / (mix.sum() + 1e-9)


def how_alike(a: tuple, b: tuple) -> float:
    """0..1. 1 = the same colours in the same places."""
    layout = 1.0 - float(np.abs(a[0] - b[0]).mean()) / 128.0
    mix = float(np.minimum(a[1], b[1]).sum())
    return max(0.0, min(1.0, 0.5 * max(0.0, layout) + 0.5 * mix))


# ── one car = one ticket, seen in several photos ──

class Car:
    def __init__(self, ticket: Ticket):
        self.ticket = ticket
        self.photos: list[Frame] = [f for f in ticket.crops if f.t is not None]
        self.photos.sort(key=lambda f: f.t)
        self.first = self.photos[0] if self.photos else None
        self.last = self.photos[-1] if self.photos else None
        self.start = self.first.t if self.first else 0.0
        self.end = self.last.t if self.last else 0.0
        self.label = identity(ticket.task_id, ticket.uid)
        self.vclass = next((f.vclass for f in self.photos if f.vclass and f.vclass != "unknown"), None)

    def biggest(self) -> Frame | None:
        def area(f: Frame) -> float:
            box = _where(f)
            return (box[2] * box[3]) if box else 0.0
        return max(self.photos, key=area) if self.photos else None

    def files(self) -> list[str]:
        """The crop names (in the evidence folder) the matcher is trained with, one per photo."""
        return sorted({(f.car_crop or f.image).name for f in self.photos})


def _picture(f: Frame):
    """The tight crop of the car itself when there is one: the wider clean picture shows its neighbours too."""
    return f.car_crop or f.image


def _read(frame: Frame):
    return cv2.imread(str(_picture(frame)))


def _where(f: Frame) -> tuple:
    return f.vbox or f.box


def _centre(f: Frame) -> tuple[float, float, float]:
    x, y, w, h = _where(f)
    return x + w / 2, y + h / 2, math.hypot(w, h)


def _compatible(a: Car, b: Car) -> bool:
    return a.vclass is None or b.vclass is None or a.vclass == b.vclass


def _already_judged(paths: Paths) -> set:
    """Pairs of cars a person already called 'not the same' in the review screens."""
    judged = set()
    try:
        lines = (paths.datasets / "reid" / "decisions.jsonl").read_text(encoding="utf-8").splitlines()
    except OSError:
        return judged
    for line in lines:
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("kind") in ("not_same", "split"):
            labels = sorted((d.get("identities") or {}).keys())
            judged.update(frozenset((x, y)) for i, x in enumerate(labels) for y in labels[i + 1:])
    return judged


def _candidates(cars: list[Car], judged: set) -> list[dict]:
    looks: dict = {}

    def seen(frame: Frame):
        key = str(_picture(frame))
        if key not in looks:
            img = _read(frame)
            looks[key] = look(img) if img is not None else None
        return looks[key]

    out = []
    for i, a in enumerate(cars):
        for b in cars[i + 1:]:
            if not a.photos or not b.photos or not _compatible(a, b):
                continue
            if frozenset((a.label, b.label)) in judged:
                continue
            first, second = (a, b) if a.start <= b.start else (b, a)
            gap = second.start - first.end
            if gap >= 0:                                    # one ended, the other began: maybe one car
                if gap > MAX_GAP_SECONDS:
                    continue
                la, lb = seen(first.last), seen(second.first)
                if la is None or lb is None:
                    continue
                like = how_alike(la, lb)
                if like < MIN_LOOK:
                    continue
                (x1, y1, d1), (x2, y2, d2) = _centre(first.last), _centre(second.first)
                moved = math.hypot(x2 - x1, y2 - y1) / max(d1, d2, 1.0)        # in car sizes
                near = 1.0 / (1.0 + moved / (2.0 + 3.0 * gap))
                out.append({"kind": "gap", "first": first, "second": second, "score": like * near * math.exp(-gap / 2.0),
                            "show": (first.last, second.first), "gap": gap})
            else:                                           # on screen together: two cars, unless boxed twice
                if min(a.end, b.end) - max(a.start, b.start) < MIN_TWIN_OVERLAP:
                    continue
                fa, fb = a.biggest(), b.biggest()
                la, lb = seen(fa), seen(fb)
                if la is None or lb is None:
                    continue
                like = how_alike(la, lb)
                if like < MIN_TWIN_LOOK:
                    continue
                out.append({"kind": "twin", "first": a, "second": b, "score": like, "show": (fa, fb), "gap": gap})
    return out


def build_pairs(paths: Paths, store: Store, task_id: str, dry_run: bool = False) -> int:
    """Ask about this analysis's cars. Returns how many new questions were added (idempotent)."""
    try:
        cars = [Car(t) for t in tickets(paths, task_id, max_frames=3, min_side=MIN_SIDE)]
    except (OSError, ValueError):
        return 0
    cars = [c for c in cars if c.photos]
    if len(cars) < 2:
        return 0
    found = _candidates(cars, _already_judged(paths))
    chosen = (sorted((c for c in found if c["kind"] == "gap"), key=lambda c: -c["score"])[:MAX_GAP_PAIRS] +
              sorted((c for c in found if c["kind"] == "twin"), key=lambda c: -c["score"])[:MAX_TWIN_PAIRS])
    added = 0
    for c in chosen:
        a, b = c["first"], c["second"]
        pair_id = make_id("pair", task_id, *sorted((a.ticket.uid, b.ticket.uid)))
        if store.get_pair(pair_id) is not None:
            continue
        if dry_run:
            added += 1
            continue
        for side, frame in zip(("a", "b"), c["show"]):
            dst = store.pair_image_path(pair_id, side)
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(_picture(frame), dst)
        reason = (f"Car {a.ticket.track_id} was last seen {c['gap']:.1f}s before car {b.ticket.track_id} appeared. "
                  "One car with a new number?" if c["kind"] == "gap" else
                  f"Cars {a.ticket.track_id} and {b.ticket.track_id} were on screen together and look alike.")
        store.add_pair(Pair(id=pair_id, task_id=task_id, a_label=a.label, b_label=b.label, a_files=a.files(),
                            b_files=b.files(), kind=c["kind"], reason=reason, score=round(c["score"], 4)))
        added += 1
    return added


# ── what an answer teaches ──

def _teach(paths: Paths, pair: Pair, same: bool) -> None:
    """Write the answer into datasets/reid exactly as the review screens do: one folder per car."""
    root = paths.datasets / "reid"
    images = root / "images" / pair.task_id
    keep, drop = images / pair.a_label, images / pair.b_label

    def copy_into(folder, names):
        for name in names:
            src = paths.evidence / name
            if src.exists() and not (folder / name).exists():
                folder.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, folder / name)

    if same:
        copy_into(keep, pair.a_files)
        if drop.exists():                                   # it was a car of its own before: now it is one car
            keep.mkdir(parents=True, exist_ok=True)
            for f in list(drop.iterdir()):
                if not (keep / f.name).exists():
                    shutil.move(str(f), str(keep / f.name))
            shutil.rmtree(drop, ignore_errors=True)
        copy_into(keep, pair.b_files)
        groups, kind = {pair.a_label: keep}, "merge"
    else:
        copy_into(keep, pair.a_files)
        copy_into(drop, pair.b_files)
        groups, kind = {pair.a_label: keep, pair.b_label: drop}, "not_same"
    saved = {label: [f"images/{pair.task_id}/{label}/{f.name}" for f in sorted(folder.iterdir())]
             for label, folder in groups.items() if folder.exists()}
    if saved:
        root.mkdir(parents=True, exist_ok=True)
        with open(root / "decisions.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"ts": time.time(), "kind": kind, "task_id": pair.task_id, "identities": saved,
                                 "source": "harvest"}) + "\n")


ANSWERS = {"same": "same", "different": "different", "skip": "skipped"}


def answer_pair(paths: Paths, store: Store, pair_id: str, answer: str) -> Pair:
    """Same / different teach the car matcher; skip only takes the question off the list."""
    if answer not in ANSWERS:
        raise ValueError(f"not an answer: {answer!r}")
    pair = store.get_pair(pair_id)
    if pair is None:
        raise KeyError(pair_id)
    if pair.state in ("same", "different") and ANSWERS[answer] != pair.state:
        raise ValueError("Already answered")
    if answer != "skip" and pair.state in ("open", "skipped"):
        _teach(paths, pair, same=answer == "same")
    return store.decide_pair(pair_id, ANSWERS[answer])
