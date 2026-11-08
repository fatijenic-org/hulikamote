"""
privacy.py - hide people's faces and other vehicles' plates in a photo BEFORE it is saved (R.A. 10173; the proposal's
"mandatory anonymization loop"). Detection and plate reading work on the original frame in memory, so they are not
affected: only what is written to disk is blurred.

What is blurred:
  - the head of every person the detector found (riders, passengers, pedestrians), the violator's own included;
  - the head zone of a motorcycle or tricycle whose rider the detector did not find (a safety net);
  - the plate of every vehicle except the violator's. The plate model's box is used when the vehicle has one, otherwise
    the lower part of the vehicle (where plates are), so nobody is skipped just because their plate was not read yet.
The violator's plate is put back exactly as it was, because the ticket needs it readable.

Faces are NOT searched for separately. OpenCV's built-in face detector was tried on the project's saved evidence photos
and found no real face in nine hits (cars, grass, road) while taking over a second per photo, so it was left out.

Nothing here can promise to catch everybody: a person the detector misses stays visible. State that limit wherever the
system is described.
"""
from __future__ import annotations

import cv2
import numpy as np

from engine.violations.geometry import rider_boxes

Box = tuple[int, int, int, int]            # x, y, width, height

HEAD_SHARE = 0.30                          # the top 30% of a person's box is the head and neck
HEAD_PAD, PLATE_PAD = 0.15, 0.20
VEHICLES = ("car", "motorcycle", "bus", "truck", "tricycle")
TWO_WHEELERS = ("motorcycle", "tricycle")


def _grow(box, pad: float) -> Box:
    x, y, w, h = (int(v) for v in box)
    px, py = int(w * pad), int(h * pad)
    return x - px, y - py, w + 2 * px, h + 2 * py


def _clip(box: Box, frame_w: int, frame_h: int) -> Box | None:
    x, y, w, h = box
    x1, y1, x2, y2 = max(0, x), max(0, y), min(frame_w, x + w), min(frame_h, y + h)
    return (x1, y1, x2 - x1, y2 - y1) if x2 > x1 and y2 > y1 else None


def head_boxes(detections) -> list[Box]:
    """A head box for every detected person, and a head zone for every two-wheeler whose rider was not detected."""
    people = [tuple(int(v) for v in d.bbox) for d in detections if getattr(d, "cls", None) == "person"]
    boxes = [_grow((x, y, w, int(h * HEAD_SHARE)), HEAD_PAD) for x, y, w, h in people]
    for d in detections:
        if getattr(d, "cls", None) in TWO_WHEELERS and not rider_boxes(list(d.bbox), [list(p) for p in people]):
            x, y, w, h = (int(v) for v in d.bbox)
            boxes.append((x + int(w * 0.10), y - int(h * 0.60), int(w * 0.80), int(h * 0.80)))   # the rider's head sticks out above the bike
    return boxes


def other_plate_boxes(detections, ledgers: dict, keep_track_id: int = -1) -> list[Box]:
    """Where the plates of every vehicle but the violator's are (or most likely are)."""
    boxes = []
    for d in detections:
        track_id = getattr(d, "track_id", -1)
        if getattr(d, "cls", None) not in VEHICLES or (track_id != -1 and track_id == keep_track_id):
            continue
        known = getattr(ledgers.get(track_id), "plate_bbox", None) if track_id != -1 else None
        if known:
            boxes.append(_grow(known, PLATE_PAD))
        else:
            x, y, w, h = (int(v) for v in d.bbox)
            boxes.append((x, y + int(h * 0.55), w, int(h * 0.45)))             # the whole lower part: on a vehicle seen at an angle the plate is off-centre
    return boxes


def blur_boxes(frame: np.ndarray, boxes) -> None:
    """Blur each box in place, hard enough that a face cannot be recognised (shrink it, then a wide Gaussian blur)."""
    height, width = frame.shape[:2]
    for box in boxes:
        clipped = _clip(tuple(int(v) for v in box), width, height)
        if clipped is None:
            continue
        x, y, w, h = clipped
        region = frame[y:y + h, x:x + w]
        small = cv2.resize(region, (max(2, w // 6), max(2, h // 6)), interpolation=cv2.INTER_AREA)
        coarse = cv2.resize(small, (w, h), interpolation=cv2.INTER_LINEAR)
        frame[y:y + h, x:x + w] = cv2.GaussianBlur(coarse, (0, 0), sigmaX=max(3.0, min(w, h) / 4))


def anonymize(frame: np.ndarray, detections, ledgers: dict, keep_track_id: int = -1) -> np.ndarray:
    """A blurred copy of `frame` that is safe to save. `keep_track_id` is the violator: their plate stays readable."""
    out = frame.copy()
    height, width = out.shape[:2]
    ledger = ledgers.get(keep_track_id) if keep_track_id != -1 else None
    plate = _clip(tuple(int(v) for v in ledger.plate_bbox), width, height) if getattr(ledger, "plate_bbox", None) else None

    blur_boxes(out, head_boxes(detections) + other_plate_boxes(detections, ledgers, keep_track_id))

    if plate is not None:
        x, y, w, h = plate
        out[y:y + h, x:x + w] = frame[y:y + h, x:x + w]
    return out


def anonymize_crop(crop: np.ndarray, origin: tuple[int, int], detections, keep: Box | None = None) -> None:
    """Blur, in place, the heads in a crop cut out of a frame at `origin`. `keep` (in crop coordinates) is a plate that
    must stay readable."""
    ox, oy = origin
    original = crop[keep[1]:keep[1] + keep[3], keep[0]:keep[0] + keep[2]].copy() if keep else None
    blur_boxes(crop, [(x - ox, y - oy, w, h) for x, y, w, h in head_boxes(detections)])
    if keep and original is not None and original.size:
        crop[keep[1]:keep[1] + keep[3], keep[0]:keep[0] + keep[2]] = original
