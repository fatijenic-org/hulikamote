"""
frames.py - Pictures from the clip itself: what tickets can never show.

Tickets only exist for vehicles the system FLAGGED, so a vehicle it missed (never boxed, or boxed and never
ticketed) would never reach a person. When an analysis kept its input video (the wizard's "keep video"), this
samples a few frames evenly across the clip, runs the vehicle finder on them and makes two kinds of pictures:

    Vehicles   the whole frame with the finder's boxes, for the vehicle finder itself (primary_anchor):
               add the vehicles and riders it missed, delete the wrong boxes
    crops      each vehicle NOBODY was ticketed for, cut out like the app cuts it for the plate / helmet / cabin
               models, to find what those models miss on ordinary traffic

The video is only read. Everything new goes into the inbox. Nothing here is a verdict: a person decides.
"""
from bisect import bisect_left
from pathlib import Path

import cv2

from .config import Paths, class_names
from .detect import Det
from .sources import Ticket
from .store import Item, Store, make_id

VIDEO_NAME = "input_video.mp4"          # saved next to the report when the analysis kept its video
FRAMES_PER_CLIP = 8
MAX_CROPS = 12                          # per model and analysis
MAX_PER_FRAME = 3                       # per model: spread the crops over the clip
# Helmets are the thinnest data (the model misses riders seen from behind / above), so ask for many more riders per clip.
MAX_CROPS_FOR = {"helmet_specialist": 60}
MAX_PER_FRAME_FOR = {"helmet_specialist": 8}
MARGIN = 0.08                           # around a vehicle, like cut_plates and the app
FRAME_CONF = 0.3
MIN_SIDE = {"plate_specialist": 80, "helmet_specialist": 80, "cabin_specialist": 100}
VEHICLES = ("motorcycle", "car", "bus", "jeepney", "truck", "tricycle")
CROPS_FOR = {
    "plate_specialist": VEHICLES,
    "helmet_specialist": ("motorcycle", "tricycle"),
    "cabin_specialist": ("car", "bus", "truck"),
}
INTENT = {"plate_specialist": "find_plate", "helmet_specialist": "riders", "cabin_specialist": "cabin"}
REASON = {
    "plate_specialist": "No ticket was issued for this vehicle. Is its plate visible? Box it, or press Nothing here.",
    "helmet_specialist": "No ticket was issued for this rider. Box each rider: helmet on, or no helmet.",
    "cabin_specialist": "No ticket was issued for this vehicle. Box what you can see inside.",
}
FRAME_REASON = "A picture from the clip. Box every vehicle and rider that should be found."
COCO_NAMES = {0: "person", 2: "car", 3: "motorcycle", 5: "bus", 7: "truck"}
DEFAULT_ANCHOR = ["motorcycle", "car", "bus", "truck", "person", "tricycle", "jeepney"]
PRIORITY = 6


def task_video(paths: Paths, task_id: str) -> Path | None:
    f = paths.forensic / task_id / VIDEO_NAME
    return f if f.exists() else None


def anchor_names(paths: Paths) -> list[str]:
    """Class names of the vehicle dataset, in training order."""
    try:
        return class_names(paths, "primary_anchor") or DEFAULT_ANCHOR
    except Exception:
        return DEFAULT_ANCHOR


def sample_times(duration: float, n: int) -> list[float]:
    """n moments spread over the clip, away from its very first and last frames."""
    if n <= 1 or duration <= 0:
        return [duration / 2]
    return [duration * (0.08 + 0.84 * i / (n - 1)) for i in range(n)]


def _name(det: Det, names: dict) -> str | None:
    return (names or COCO_NAMES).get(det.cls)


def _on_bike(person: Det, bike: Det) -> bool:
    """A person whose body sits on top of this motorcycle: a rider, not someone walking past."""
    cx, cy = (person.x1 + person.x2) / 2, (person.y1 + person.y2) / 2
    bw, bh = bike.x2 - bike.x1, bike.y2 - bike.y1
    return (bike.x1 - 0.15 * bw <= cx <= bike.x2 + 0.15 * bw and
            bike.y1 - 1.0 * bh <= cy <= bike.y2 and person.y2 <= bike.y2 + 0.2 * bh)


def anchor_boxes(dets: list[Det], names: dict, anchor: list[str], width: int, height: int) -> list:
    """Vehicle finder output as YOLO boxes of the vehicle dataset: vehicles, plus riders on motorcycles."""
    named = [(_name(d, names), d) for d in dets]
    bikes = [d for n, d in named if n in ("motorcycle", "tricycle")]
    out = []
    for n, d in named:
        if n is None or n not in anchor:
            continue
        if n in VEHICLES or (n == "person" and any(_on_bike(d, b) for b in bikes)):
            out.append(Det(anchor.index(n), d.conf, d.x1, d.y1, d.x2, d.y2).yolo(width, height))
    return out


def _iou(a: tuple, b: tuple) -> float:
    ax1, ay1, ax2, ay2 = a[0], a[1], a[0] + a[2], a[1] + a[3]
    bx1, by1, bx2, by2 = b[0], b[1], b[0] + b[2], b[1] + b[3]
    inter = max(0.0, min(ax2, bx2) - max(ax1, bx1)) * max(0.0, min(ay2, by2) - max(ay1, by1))
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)


def ticketed_boxes_at(tix: list[Ticket], t: float, slack: float = 0.5) -> list[tuple]:
    """Where each ticketed car should be at second t (x, y, w, h), walking between its saved photos."""
    out = []
    for ticket in tix:
        photos = sorted((f for f in ticket.crops if f.t is not None and (f.vbox or f.box)), key=lambda f: f.t)
        if not photos or t < photos[0].t - slack or t > photos[-1].t + slack:
            continue
        times = [f.t for f in photos]
        j = bisect_left(times, t)
        if j == 0 or j == len(photos):
            nearest = photos[min(j, len(photos) - 1)]
            out.append(tuple(nearest.vbox or nearest.box))
            continue
        a, b = photos[j - 1], photos[j]
        ba, bb = a.vbox or a.box, b.vbox or b.box
        k = (t - a.t) / max(b.t - a.t, 1e-6)
        out.append(tuple(ba[i] + k * (bb[i] - ba[i]) for i in range(4)))
    return out


def _crop(image, det: Det):
    H, W = image.shape[:2]
    bw, bh = det.x2 - det.x1, det.y2 - det.y1
    x1, y1 = max(0, int(det.x1 - MARGIN * bw)), max(0, int(det.y1 - MARGIN * bh))
    x2, y2 = min(W, int(det.x2 + MARGIN * bw)), min(H, int(det.y2 + MARGIN * bh))
    return image[y1:y2, x1:x2]


def _write(path: Path, image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), image, [cv2.IMWRITE_JPEG_QUALITY, 92])


def harvest_frames(paths: Paths, store: Store, detectors, suggest, task_id: str, tix: list[Ticket],
                   dry_run: bool = False) -> dict:
    """Make the clip's own pictures for one analysis. `detectors` = collect.Detectors, `suggest` = collect.suggest."""
    video = task_video(paths, task_id)
    summary = {"video": video is not None, "frames": 0, "crops": {}}
    if video is None:
        return summary
    finder = detectors.get("primary_anchor")
    if finder is None:
        summary["no_finder"] = True
        return summary
    cap = cv2.VideoCapture(str(video))
    try:
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
        if total <= 0:
            return summary
        anchor = anchor_names(paths)
        group = f"{task_id}:frames"
        wanted: dict[str, list] = {m: [] for m in CROPS_FOR}        # model -> (area, frame no, vehicle no, crop)
        for k, t in enumerate(sample_times(total / fps, FRAMES_PER_CLIP)):
            cap.set(cv2.CAP_PROP_POS_FRAMES, min(total - 1, int(t * fps)))
            ok, frame = cap.read()
            if not ok or frame is None:
                continue
            H, W = frame.shape[:2]
            dets = finder.detect(frame, conf=FRAME_CONF)
            frame_id = make_id(task_id, "frame", str(k))
            if store.get(frame_id) is None:
                summary["frames"] += 1
                if not dry_run:
                    boxes = anchor_boxes(dets, finder.names, anchor, W, H)
                    _write(store.image_path("primary_anchor", frame_id), frame)
                    store.add(Item(
                        id=frame_id, model="primary_anchor", state="check" if boxes else "label", source="frame",
                        reason=FRAME_REASON, boxes=boxes, suggested=bool(boxes), group_id=group, task_id=task_id,
                        priority=PRIORITY, width=W, height=H))
            busy = ticketed_boxes_at(tix, t)
            vehicles = sorted((d for d in dets if _name(d, finder.names) in VEHICLES), key=lambda d: d.x1)
            for v, d in enumerate(vehicles):
                if any(_iou((d.x1, d.y1, d.x2 - d.x1, d.y2 - d.y1), b) > 0.25 for b in busy):
                    continue                                        # this car has a ticket: its pictures come from there
                crop = _crop(frame, d)
                for model, kinds in CROPS_FOR.items():
                    if _name(d, finder.names) in kinds and min(crop.shape[:2]) >= MIN_SIDE[model]:
                        wanted[model].append((crop.shape[0] * crop.shape[1], k, v, crop))
        for model, found in wanted.items():
            taken, per_frame = [], {}
            for area, k, v, crop in sorted(found, key=lambda x: -x[0]):
                if len(taken) >= MAX_CROPS_FOR.get(model, MAX_CROPS) or per_frame.get(k, 0) >= MAX_PER_FRAME_FOR.get(model, MAX_PER_FRAME):
                    continue
                per_frame[k] = per_frame.get(k, 0) + 1
                taken.append((k, v, crop))
            for k, v, crop in taken:
                item_id = make_id(task_id, "frame", str(k), model, str(v))
                if store.get(item_id) is not None:
                    continue
                summary["crops"][model] = summary["crops"].get(model, 0) + 1
                if dry_run:
                    continue
                h, w = crop.shape[:2]
                boxes = suggest(detectors.get(model), crop, INTENT[model], w, h)
                _write(store.image_path(model, item_id), crop)
                store.add(Item(
                    id=item_id, model=model, state="check" if boxes is not None else "label", source="frame",
                    reason=REASON[model], boxes=boxes or [], suggested=boxes is not None, group_id=group,
                    task_id=task_id, priority=PRIORITY + 1, width=w, height=h))
    finally:
        cap.release()
    return summary
