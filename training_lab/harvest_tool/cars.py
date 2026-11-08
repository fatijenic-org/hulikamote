"""
cars.py - Check one car at a time: are all the photos filed under this number really the same car?

The tracker sometimes follows car A, loses it, and keeps the same number on car B. Every ticket holds a
strip of photos of "its" car, so a person can walk along the strip and mark the photos that show a
different car from the first one (the original). The answer is written the way the review screens write
theirs, into datasets/reid/images/<analysis>/<car>/ (one folder per car) and one line in decisions.jsonl.
The ticket itself never changes: this only makes training data for the car matcher (ReID).
"""
import json
import shutil
import time

from .config import Paths
from .pairs import identity
from .sources import Ticket, tickets
from .store import Store


def _photos(ticket: Ticket) -> list[str]:
    """The names (in the evidence folder) of this car's tight crops, in the order they were taken."""
    seen, names = set(), []
    for f in sorted(ticket.crops, key=lambda f: (f.t is None, f.t or 0.0)):
        name = (f.car_crop or f.image).name
        if name not in seen:
            seen.add(name)
            names.append(name)
    return names


def _cars(paths: Paths, task: str) -> list[Ticket]:
    try:
        found = tickets(paths, task, max_frames=1, min_side=1)
    except (OSError, ValueError):
        raise KeyError(task)
    return sorted((t for t in found if len(_photos(t)) >= 2), key=lambda t: t.track_id)       # one photo: nothing to compare


def car_counts(paths: Paths, store: Store, task: str) -> dict:
    try:
        cars = _cars(paths, task)
    except KeyError:
        return {"open": 0, "checked": 0, "split": 0}
    checks = store.car_checks(task)
    counts = {"open": 0, "checked": 0, "split": 0}
    for t in cars:
        counts[checks[t.uid][0] if t.uid in checks else "open"] += 1
    return counts


def car_list(paths: Paths, store: Store, task: str) -> dict:
    checks = store.car_checks(task)
    items = []
    for t in _cars(paths, task):
        names = _photos(t)
        items.append({"uid": t.uid, "track": t.track_id, "label": identity(task, t.uid), "photos": len(names),
                      "first": names[0], "state": checks[t.uid][0] if t.uid in checks else "open",
                      "violations": t.violations})
    counts = {"open": 0, "checked": 0, "split": 0}
    for i in items:
        counts[i["state"]] += 1
    return {"task": task, "evidence_dir": str(paths.evidence), "items": items, "counts": counts}


def _find(paths: Paths, task: str, uid: str) -> Ticket:
    for t in _cars(paths, task):
        if t.uid == uid:
            return t
    raise KeyError(uid)


def car_detail(paths: Paths, store: Store, task: str, uid: str) -> dict:
    t = _find(paths, task, uid)
    state, marked = store.car_checks(task).get(uid, ("open", []))
    return {"task": task, "uid": uid, "track": t.track_id, "label": identity(task, uid), "state": state,
            "violations": t.violations, "evidence_dir": str(paths.evidence), "photos": _photos(t), "marked": marked}


def check_car(paths: Paths, store: Store, task: str, uid: str, different: list) -> dict:
    """Write the answer: photos not marked stay one car, marked photos become another car."""
    return _apply(paths, store, task, _find(paths, task, uid), different)


def fill_cars(paths: Paths, store: Store, task: str) -> dict:
    """Every car nobody opened is taken as one car (the tracker was right): its photos are filed, nothing is marked.
    The ones a person already went through are left exactly as they were."""
    done = store.car_checks(task)
    filled = 0
    for t in _cars(paths, task):
        if t.uid not in done:
            _apply(paths, store, task, t, [])
            filled += 1
    return {"filled": filled, "counts": car_counts(paths, store, task)}


def _apply(paths: Paths, store: Store, task: str, t: Ticket, different: list) -> dict:
    uid = t.uid
    names = _photos(t)
    marked = sorted({str(n) for n in different}, key=names.index) if all(str(n) in names for n in different) else None
    if marked is None:
        raise ValueError("Those are not photos of this car")
    if names[0] in marked:
        raise ValueError("The first photo is the original: it cannot be a different car")
    label = identity(task, uid)
    other = f"{label}_b"
    root = paths.datasets / "reid"
    keep_dir, other_dir = root / "images" / task / label, root / "images" / task / other

    def place(name: str, into, out_of) -> None:
        dest = into / name
        if dest.exists():
            return
        into.mkdir(parents=True, exist_ok=True)
        stray = out_of / name                            # it was filed under the other car earlier: move, never duplicate
        if stray.exists():
            shutil.move(str(stray), str(dest))
        elif (paths.evidence / name).exists():
            shutil.copy2(paths.evidence / name, dest)

    for name in names:
        if name in marked:
            place(name, other_dir, keep_dir)
        else:
            place(name, keep_dir, other_dir)
    for folder in (keep_dir, other_dir):                 # a folder left with nothing in it is not a car
        if folder.exists() and not any(folder.iterdir()):
            folder.rmdir()
    groups = {label: keep_dir, **({other: other_dir} if marked else {})}
    saved = {k: [f"images/{task}/{k}/{f.name}" for f in sorted(d.iterdir())] for k, d in groups.items() if d.exists()}
    if saved:
        root.mkdir(parents=True, exist_ok=True)
        with open(root / "decisions.jsonl", "a", encoding="utf-8") as fh:
            fh.write(json.dumps({"ts": time.time(), "kind": "split" if marked else "checked", "task_id": task,
                                 "identities": saved, "source": "harvest"}) + "\n")
    store.save_car_check(task, uid, "split" if marked else "checked", marked)
    return {"state": "split" if marked else "checked", "kept": len(names) - len(marked), "other": len(marked),
            "counts": car_counts(paths, store, task)}
