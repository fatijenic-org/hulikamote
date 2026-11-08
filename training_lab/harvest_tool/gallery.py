"""
gallery.py - A read-only snapshot of the whole inbox, for the Forensic Analyzer's Harvest tab.

harvest_inbox/gallery.json says, for every use (the model a picture teaches), what is there,
where it came from and what state it is in. The dashboard reads this file and the pictures next
to it directly, so it needs neither the backend nor the check & label page.

The file is derived: safe to delete, rebuilt by `harvest.py gallery` and after every collect,
save, skip and accept. It lives inside harvest_inbox/, like everything else this tool writes.
"""
import json
import os
import time
from pathlib import Path

from .collect import ROUTES
from .config import AUTOMATIC, CLASS_HELP, MODELS, Paths, active_onnx
from .sources import load_protected
from .store import Store

SCHEMA_VERSION = 1
MAX_ITEMS = 1500            # pictures listed per use (a few hundred KB of JSON at most)
MAX_SAMPLES = 200           # OCR pictures listed
MAX_GROUPS = 40             # cars listed for the matcher
PHOTOS_PER_GROUP = 6

STATE_ORDER = {"check": 0, "label": 1, "ready": 2, "skipped": 3, "accepted": 4}

SOURCE_LABELS = {
    "ticket": "Vehicles from your forensic tickets",
    "plate_photo_cut": "Cut from plate photos you already have",
    "frame": "Frames and vehicles from the clip itself (no ticket)",
}

# Plain words for the dashboard, one entry per model the harvest feeds.
USES = {
    "plate_specialist": {
        "title": "Plate finder",
        "used_for": ("Teaches the plate finder to spot number plates it missed. Every 'plate unread' ticket "
                     "starts here: the better it finds plates, the fewer tickets stay unidentified."),
        "fed_by": ["Vehicles from tickets where no plate was found",
                   "Vehicles where a plate was read, to check that the box is right",
                   "Plate photos you already have, cut down to one vehicle"],
        "your_job": "Plate visible? Draw a box around it. No plate? Press N.",
    },
    "helmet_specialist": {
        "title": "Helmet check",
        "used_for": ("Teaches the helmet check what riders with and without a helmet look like, "
                     "so 'no helmet' tickets are right more often."),
        "fed_by": ["Vehicles from 'no helmet' tickets"],
        "your_job": "Box each rider: with a helmet, or without.",
    },
    "cabin_specialist": {
        "title": "Cabin check",
        "used_for": ("Teaches the cabin check to find the windshield, seatbelt, phone and side mirrors, "
                     "which the seatbelt, phone and mirror tickets depend on."),
        "fed_by": ["Vehicles from 'no seatbelt', 'phone use' and 'missing side mirror' tickets"],
        "your_job": "Box what you can see: windshield, seatbelt, phone, side mirrors.",
    },
    "primary_anchor": {
        "title": "Vehicle finder",
        "used_for": ("Teaches the vehicle finder to find every car, motorcycle, bus, truck, tricycle and rider. It runs "
                     "first: whatever it misses never reaches the plate, helmet or cabin checks."),
        "fed_by": ["Frames sampled from clips whose video was kept (the finder's guess is drawn)"],
        "your_job": "Add the vehicles and riders it missed, delete the wrong boxes.",
    },
}

AUTOMATIC_USES = {
    "plate_ocr": {
        "title": "Plate text reader",
        "does": "reads the letters and digits of a plate",
        "used_for": ("Teaches the reader to read the characters of a plate. Each picture is a plate crop, "
                     "named after the text you typed for it."),
        "fed_by": ["Corrections typed under 'Teach the OCR' in the review screen"],
        "your_job": "Nothing to check here. It grows each time you teach the OCR in the review screen.",
        "kind_note": "pictures",
    },
    "reid": {
        "title": "Car matcher",
        "does": "tells whether two photos show the same car",
        "used_for": ("Teaches the tracker which photos belong to one car, so a single car stays a single ticket "
                     "instead of splitting in two."),
        "fed_by": ["Merge ('same car') and Separate decisions in the review screen"],
        "your_job": "Nothing to check here. It grows each time you merge or separate tickets.",
        "kind_note": "cars",
    },
}


def _violations_for(model: str) -> list[str]:
    if model == "plate_specialist":
        return ["no_plate"]                      # plus every ticket whose plate was never read
    return [v for v, (m, _) in ROUTES.items() if m == model]


def _why(item) -> str:
    """One short line: why this picture is in the inbox."""
    if item.source == "frame":
        return "From the clip: no ticket" if item.model != "primary_anchor" else "A frame from the clip"
    if item.source == "plate_photo_cut":
        return "Cut from a plate photo"
    if item.model == "plate_specialist":
        if item.violation == "no_plate":
            return "'No plate' ticket"
        if item.violation:
            return f"Plate never read ({item.violation.replace('_', ' ')} ticket)"
        return "Plate was read: check the box"
    if item.violation:
        return f"'{item.violation.replace('_', ' ')}' ticket"
    return "Collected from a ticket"


def _item(item) -> dict:
    return {
        "id": item.id,
        "image": f"{item.model}/images/{item.id}.jpg",
        "state": item.state,
        "source": item.source,
        "why": _why(item),
        "reason": item.reason,
        "violation": item.violation,
        "decision": item.decision,
        "suggested": bool(item.suggested),
        "boxes": item.boxes,
        "width": item.width,
        "height": item.height,
        "group": item.group_id,
        "task": item.task_id,
        "ticket": item.ticket_uid,
        "created": item.created,
        "decided": item.decided,
        "accepted": item.accepted,
        "dataset_name": item.dataset_name,
    }


def _count_by(items: list, key) -> list[dict]:
    out: dict = {}
    for it in items:
        k = key(it)
        if k is not None:
            out[k] = out.get(k, 0) + 1
    return [{"key": k, "n": n} for k, n in sorted(out.items(), key=lambda kv: (-kv[1], str(kv[0])))]


def _model_category(paths: Paths, store: Store, key: str, training: bool | None, dataset_size, class_names) -> dict:
    spec, use = MODELS[key], USES[key]
    counts = store.counts(key)
    counts["total"] = sum(counts[s] for s in ("check", "label", "ready", "skipped", "accepted"))
    items = store.items(key, tuple(STATE_ORDER), None)
    items.sort(key=lambda it: (STATE_ORDER.get(it.state, 9), it.priority, it.created, it.id))
    listed = items[:MAX_ITEMS]
    onnx = active_onnx(paths, key)
    if counts["needs_eyes"]:
        nxt = f"{counts['needs_eyes']} pictures need your eyes."
    elif counts["ready"]:
        nxt = f"{counts['ready']} pictures are ready to add to the dataset."
    else:
        nxt = "Nothing waiting. Analyze more clips, then press Collect."
    classes = [{"name": name, "help": CLASS_HELP.get(key, {}).get(name, "")} for name in class_names(paths, key)]
    return {
        "key": key,
        "kind": "detector",
        "title": use["title"],
        "does": spec["does"],
        "used_for": use["used_for"],
        "fed_by": use["fed_by"],
        "your_job": use["your_job"],
        "violations": _violations_for(key),
        "classes": classes,
        "model_file": onnx.name if onnx else None,
        "training": training,                 # None = not checked this time
        "dataset_images": dataset_size(paths, key),
        "counts": counts,
        "next": nxt,
        "sources": [{"key": c["key"], "label": SOURCE_LABELS.get(c["key"], c["key"]), "n": c["n"]}
                    for c in _count_by(items, lambda it: it.source)],
        "violations_seen": [{"violation": c["key"], "n": c["n"]}
                            for c in _count_by(items, lambda it: it.violation)],
        "listed": len(listed),
        "items": [_item(it) for it in listed],
    }


def _ocr_category(paths: Paths, spec: dict) -> dict:
    use = AUTOMATIC_USES["plate_ocr"]
    folder = paths.datasets / spec["folder"]
    samples = []
    total = 0
    if folder.exists():
        with os.scandir(folder) as it:
            entries = [e for e in it if e.is_file() and e.name.lower().endswith((".jpg", ".jpeg", ".png"))]
        total = len(entries)
        entries.sort(key=lambda e: e.stat().st_mtime, reverse=True)
        for e in entries[:MAX_SAMPLES]:
            stem = Path(e.name).stem
            text, _, stamp = stem.rpartition("_")
            when = None
            if text and stamp.isdigit():
                when = int(stamp) / 1000 if len(stamp) >= 12 else int(stamp)
            samples.append({
                "path": (Path("datasets") / spec["folder"] / e.name).as_posix(),
                "label": text or stem,
                "when": when or e.stat().st_mtime,
            })
    return {
        "key": "plate_ocr", "kind": "automatic", "title": use["title"], "does": use["does"],
        "used_for": use["used_for"], "fed_by": use["fed_by"], "your_job": use["your_job"],
        "how": spec["how"], "count": total, "need": spec["need"], "unit": spec.get("unit", "pictures"),
        "samples": samples, "groups": [], "facts": [],
    }


def _reid_category(paths: Paths, spec: dict) -> dict:
    use = AUTOMATIC_USES["reid"]
    root = paths.datasets / "reid" / "images"
    groups = []
    cars_with_2 = 0
    if root.exists():
        for task in sorted(p for p in root.iterdir() if p.is_dir()):
            for car in sorted(p for p in task.iterdir() if p.is_dir()):
                photos = sorted(p.name for p in car.iterdir() if p.is_file())
                if len(photos) >= 2:
                    cars_with_2 += 1
                groups.append({
                    "id": f"{task.name[:8]}/{car.name}",
                    "n": len(photos),
                    "photos": [(Path("datasets") / "reid" / "images" / task.name / car.name / n).as_posix()
                               for n in photos[:PHOTOS_PER_GROUP]],
                })
    groups.sort(key=lambda g: -g["n"])
    merges = separations = 0
    decisions = paths.datasets / "reid" / "decisions.jsonl"
    if decisions.exists():
        try:
            for line in decisions.read_text(encoding="utf-8").splitlines():
                kind = json.loads(line).get("kind", "")
                if kind == "merge":
                    merges += 1
                elif kind in ("split", "not_same"):
                    separations += 1
        except Exception:
            pass
    return {
        "key": "reid", "kind": "automatic", "title": use["title"], "does": use["does"],
        "used_for": use["used_for"], "fed_by": use["fed_by"], "your_job": use["your_job"],
        "how": spec["how"], "count": cars_with_2, "need": spec["need"], "unit": spec.get("unit", "cars"),
        "samples": [], "groups": groups[:MAX_GROUPS],
        "facts": [{"label": "'Same car' decisions", "value": merges},
                  {"label": "'Different car' decisions", "value": separations}],
    }


def build_gallery(paths: Paths, store: Store, busy: set | None = None, previous: dict | None = None) -> dict:
    """The whole snapshot as a plain dict. `busy` = models being trained now (None = not checked:
    the flags of the previous snapshot are kept)."""
    from .web import dataset_size, safe_classes

    carried = {c["key"]: c.get("training") for c in (previous or {}).get("categories", [])}
    categories = []
    for key in MODELS:
        training = (key in busy) if busy is not None else carried.get(key)
        categories.append(_model_category(paths, store, key, training, dataset_size, safe_classes))
    for spec in AUTOMATIC:
        if spec["key"] == "plate_ocr":
            categories.append(_ocr_category(paths, spec))
        elif spec["key"] == "reid":
            categories.append(_reid_category(paths, spec))
    return {
        "schema": SCHEMA_VERSION,
        "generated": time.time(),
        "lab": str(paths.lab),
        "inbox": str(paths.inbox),
        "protected": len(load_protected(paths)),
        "categories": categories,
    }


def read_gallery(paths: Paths) -> dict | None:
    f = paths.inbox / "gallery.json"
    try:
        return json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return None


def write_gallery(paths: Paths, store: Store | None = None, busy: set | None = None) -> Path:
    """Rebuild harvest_inbox/gallery.json (atomically, so a reader never sees half a file)."""
    store = store or Store(paths)
    data = build_gallery(paths, store, busy=busy, previous=read_gallery(paths))
    target = paths.inbox / "gallery.json"
    tmp = paths.inbox / "gallery.json.tmp"
    tmp.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    try:
        os.replace(tmp, target)
    except OSError:                              # a reader holds the file on Windows: write in place
        target.write_text(tmp.read_text(encoding="utf-8"), encoding="utf-8")
        tmp.unlink(missing_ok=True)
    return target
