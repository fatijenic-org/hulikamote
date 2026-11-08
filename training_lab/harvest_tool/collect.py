"""
collect.py - Turn saved analyses into inbox items: "here is a picture, please look at it".

The routing is plain data (ROUTES below): which violation teaches which model. Adding a
violation later = one row. Rule-only violations (counterflow, parking, ...) are not model
problems; they only show up in the board's "how the rules are doing" table.

A human always has the last word: nothing is ever added to a dataset without passing the
check & label page. Review decisions in the forensic screen are NOT required; if present
they only set the order (rejected tickets first - the model is most likely wrong there).
"""
import json
import shutil
from dataclasses import dataclass

import cv2

from .config import MODELS, Paths, active_onnx
from .detect import Detector
from .frames import FRAME_CONF, anchor_boxes, anchor_names, harvest_frames
from .pairs import build_pairs
from .sources import Frame, Ticket, forensic_task_ids, load_protected, tickets
from .store import Item, Store, make_id

# violation -> (model, intent). A vision-model violation teaches its model.
ROUTES = {
    "no_helmet": ("helmet_specialist", "riders"),
    "no_seatbelt": ("cabin_specialist", "cabin"),
    "distracted_driving": ("cabin_specialist", "cabin"),
    "missing_side_mirror": ("cabin_specialist", "cabin"),
}
PRIORITY = {"rejected": 0, "pending": 1, "approved": 2}   # lower = shown first
FRAMES_PER_WANT = {"find_plate": 2, "plate_present": 1, "riders": 3, "cabin": 2}
MIN_SIDE_FIND_PLATE = 80          # a plate cannot be seen on a vehicle smaller than this
SUGGEST_CONF = 0.25
COLLECT_VERSION = 3          # 1: pictures of tickets; 2: + the clip's own frames and "same car?" questions; 3: + many more helmet riders per clip

REASONS = {
    ("find_plate", "no_plate", "rejected"):
        "You rejected this 'no plate' ticket, so a plate is probably visible. Draw a box around it.",
    ("find_plate", "no_plate", "approved"):
        "You confirmed 'no plate'. Press Enter to keep it as a 'no plate' example (or draw the plate if one shows).",
    ("find_plate", "no_plate", "pending"):
        "The system found no plate on this vehicle. Is one visible? Draw a box around it, or press N = nothing here.",
    ("plate_present", None, None):
        "The system read a plate here. Is the box right? Enter = yes, otherwise fix it.",
    ("riders", "no_helmet", None):
        "The system flagged 'no helmet'. Box each rider: with a helmet, or without.",
    ("cabin", "no_seatbelt", None):
        "The system flagged 'no seatbelt'. Box the windshield and the seatbelt if you can see one.",
    ("cabin", "distracted_driving", None):
        "The system flagged 'phone use'. Box the phone if one is in the driver's hand.",
    ("cabin", "missing_side_mirror", None):
        "The system flagged 'missing side mirror'. Box every side mirror you can see.",
}


@dataclass
class Want:
    model: str
    intent: str
    violation: str | None
    decision: str
    reason: str
    priority: int


def _reason(intent: str, violation: str | None, decision: str | None, fallback_violation: str | None = None) -> str:
    for key in ((intent, violation, decision), (intent, violation, None), (intent, None, None)):
        if key in REASONS:
            return REASONS[key]
    return (f"The system flagged this vehicle for '{fallback_violation or violation}' but could not read its plate. "
            "Is a plate visible? Draw a box around it, or press N = nothing here.")


def wants_for(t: Ticket) -> list[Want]:
    """Which models should look at this ticket, and why."""
    wants = []
    # 1. The plate model learns from every ticket: a missed plate, or a plate it did find.
    if "no_plate" in t.violations:
        d = t.status_by_violation.get("no_plate", "pending")
        wants.append(Want("plate_specialist", "find_plate", "no_plate", d,
                          _reason("find_plate", "no_plate", d), PRIORITY.get(d, 1)))
    elif not t.plate_found:
        v = t.violations[0] if t.violations else None
        d = t.status_by_violation.get(v, "pending") if v else "pending"
        wants.append(Want("plate_specialist", "find_plate", v, d, _reason("find_plate", None, None, v), 3))
    else:
        wants.append(Want("plate_specialist", "plate_present", None, "any",
                          f"The system read a plate here ({t.plate_text}). Is the box right? "
                          "Enter = yes, otherwise fix it.", 4))
    # 2. Vision-model violations teach their own model.
    for v in t.violations:
        if v in ROUTES:
            model, intent = ROUTES[v]
            d = t.status_by_violation.get(v, "pending")
            wants.append(Want(model, intent, v, d, _reason(intent, v, d), PRIORITY.get(d, 1)))
    return wants


def _pick(frames: list[Frame], n: int) -> list[Frame]:
    if len(frames) <= n:
        return frames
    step = (len(frames) - 1) / (n - 1) if n > 1 else 0
    return [frames[round(i * step)] for i in range(n)]


class Detectors:
    """Lazy suggestion models: one per harvest model, None when nothing is deployed yet."""

    def __init__(self, paths: Paths, threads: int = 2):
        self.paths, self.threads, self._cache = paths, threads, {}

    def get(self, model: str) -> Detector | None:
        if model not in self._cache:
            onnx = active_onnx(self.paths, model)
            try:
                self._cache[model] = Detector.load(onnx, self.threads) if onnx else None
            except Exception:
                self._cache[model] = None
        return self._cache[model]


def suggest(detector: Detector | None, image, want_intent: str, width: int, height: int) -> list | None:
    """Boxes (YOLO, normalised) a model proposes, or None when it has no opinion."""
    if detector is None:
        return None
    dets = detector.detect(image, conf=SUGGEST_CONF)
    if want_intent in ("find_plate", "plate_present"):
        dets = dets[:1]                                    # one plate per vehicle
    return [d.yolo(width, height) for d in dets] or None


def collect(paths: Paths | None = None, store: Store | None = None, detectors: Detectors | None = None,
            task_ids: list[str] | None = None, dry_run: bool = False) -> dict:
    paths = paths or Paths()
    store = store or Store(paths)
    detectors = detectors or Detectors(paths)
    protected = load_protected(paths)
    summary = {"tasks": 0, "protected_tasks": 0, "tickets": 0, "no_picture": 0, "already_have": 0,
               "unreadable": 0, "added": {}, "frames": 0, "frame_crops": {}, "no_video": 0, "pairs": 0}
    for task in (task_ids or forensic_task_ids(paths)):
        if task in protected:
            summary["protected_tasks"] += 1
            continue
        try:
            task_tickets = tickets(paths, task)
        except (OSError, ValueError):                  # no report (a run that failed or is still going): nothing to gather yet
            summary["no_report"] = summary.get("no_report", 0) + 1
            continue
        summary["tasks"] += 1
        for t in task_tickets:
            summary["tickets"] += 1
            for want in wants_for(t):
                frames = _pick(t.frames, FRAMES_PER_WANT[want.intent])
                if not frames:
                    summary["no_picture"] += 1
                    continue
                for fr in frames:
                    item_id = make_id(task, t.uid, want.model, want.intent, fr.image.name)
                    if store.get(item_id) is not None:
                        summary["already_have"] += 1
                        continue
                    bucket = summary["added"].setdefault(want.model, {"check": 0, "label": 0})
                    if dry_run:
                        bucket["check"] += 1            # the real check / label split needs the model
                        continue
                    img = cv2.imread(str(fr.image))
                    if img is None:
                        summary["unreadable"] += 1
                        continue
                    h, w = img.shape[:2]
                    if want.intent == "find_plate" and min(h, w) < MIN_SIDE_FIND_PLATE:
                        summary["too_small"] = summary.get("too_small", 0) + 1
                        continue
                    boxes = suggest(detectors.get(want.model), img, want.intent, w, h)
                    confirmed_no_plate = want.violation == "no_plate" and want.decision == "approved"
                    if boxes is not None:
                        state = "check"
                    elif confirmed_no_plate:
                        state, boxes = "check", []       # the operator confirmed it: a 'no plate' example
                    else:
                        state, boxes = "label", []
                    dst = store.image_path(want.model, item_id)
                    dst.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(fr.image, dst)
                    store.add(Item(
                        id=item_id, model=want.model, state=state, source="ticket", reason=want.reason,
                        boxes=boxes, suggested=state == "check",
                        group_id=f"{task}:{t.uid}", task_id=task, ticket_uid=t.uid, violation=want.violation,
                        decision=want.decision, priority=want.priority, width=w, height=h))
                    bucket[state] += 1
        # what tickets cannot show: the clip's own frames (only when its video was kept), and "same car?" questions
        if not dry_run:
            own = harvest_frames(paths, store, detectors, suggest, task, task_tickets)
            summary["frames"] += own["frames"]
            summary["no_video"] += 0 if own["video"] else 1
            for model, n in own["crops"].items():
                summary["frame_crops"][model] = summary["frame_crops"].get(model, 0) + n
        summary["pairs"] += build_pairs(paths, store, task, dry_run=dry_run)
        if not dry_run:
            store.mark_collected(task, COLLECT_VERSION)
    if not dry_run:
        summary["upgraded"] = refresh_suggestions(paths, store, detectors)
    return summary


def refresh_suggestions(paths: Paths, store: Store, detectors: Detectors | None = None) -> int:
    """Items waiting without a suggestion get one once a model is deployed (or a newer one is)."""
    detectors = detectors or Detectors(paths)
    state_file = store.root / "suggest_state.json"
    try:
        last = json.loads(state_file.read_text())
    except Exception:
        last = {}
    upgraded = 0
    for model in MODELS:
        onnx = active_onnx(paths, model)
        det = detectors.get(model)
        if det is None or onnx is None or last.get(model) == onnx.name:
            continue
        for item in store.unsuggested_labels(model):
            img = cv2.imread(str(store.image_path(model, item.id)))
            if img is None:
                continue
            h, w = img.shape[:2]
            if model == "primary_anchor":
                boxes = anchor_boxes(det.detect(img, conf=FRAME_CONF), det.names, anchor_names(paths), w, h)
            else:
                boxes = suggest(det, img, "find_plate" if model == "plate_specialist" else "riders", w, h)
            if boxes:
                store.set_suggestion(item.id, boxes)
                upgraded += 1
        last[model] = onnx.name
    state_file.write_text(json.dumps(last))
    return upgraded
