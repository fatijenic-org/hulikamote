"""
marks.py — Boxes that show WHY a vehicle was flagged (the bare head, the phone, the
missing plate area, each rider ...), drawn on the result video and the evidence photos.

The specialist models only look every few frames, so each mark is stored RELATIVE to the
vehicle's box (fractions of its width / height). On every frame it is placed on the
vehicle's current box, so it follows the vehicle. A mark is drawn only while its violation
is flagged on that vehicle, and only for MARK_TTL_S seconds after the last look.
"""
import math

import cv2
import numpy as np

MARK_TTL_S = 3.0
TIMER_TTL_S = 1.0      # a stopwatch is rewritten on every frame it runs; it vanishes this long after the rule stops writing it
RED, GREEN, YELLOW = (0, 0, 255), (0, 200, 0), (0, 220, 255)
AMBER = (0, 165, 255)


def clock(seconds: float) -> str:
    """72 -> "1:12"."""
    minutes, secs = divmod(int(max(0, seconds)), 60)
    return f"{minutes}:{secs:02d}"


def set_timer(ledger, key: str, text: str, over: bool, t: float) -> None:
    """A stopwatch on the vehicle's own box (e.g. illegal parking: "PARKED 0:07 / 0:10"): amber while counting, red once over the
    limit. It is a separate chip on the bottom edge of the box: the labels above the box and the marks are not touched."""
    ledger.timers[key] = {"t": t, "text": text, "over": over}


def clear_timer(ledger, key: str) -> None:
    ledger.timers.pop(key, None)


def current_timers(ledger) -> list[tuple]:
    """[(text, BGR colour)] of the stopwatches running on this vehicle now."""
    timers = getattr(ledger, "timers", None)
    if not timers:
        return []
    now = ledger.path[-1][0] if ledger.path else 0.0
    return [(tm["text"], RED if tm["over"] else AMBER) for tm in timers.values() if now - tm["t"] <= TIMER_TTL_S]


def to_relative(box: list, vehicle: list) -> tuple:
    vx, vy, vw, vh = vehicle
    x, y, w, h = box
    vw, vh = max(vw, 1), max(vh, 1)
    return ((x - vx) / vw, (y - vy) / vh, w / vw, h / vh)


def to_absolute(rel: tuple, vehicle: list) -> list[int]:
    vx, vy, vw, vh = vehicle
    rx, ry, rw, rh = rel
    return [int(vx + rx * vw), int(vy + ry * vh), int(rw * vw), int(rh * vh)]


def set_marks(ledger, violation: str, vehicle: list, boxes: list, note: str | None = None) -> None:
    """Remember the boxes (frame coords [x, y, w, h], label, BGR colour) found by the latest look."""
    t = ledger.path[-1][0] if ledger.path else 0.0
    ledger.marks[violation] = {
        "t": t,
        "items": [(to_relative(b, vehicle), label, colour) for b, label, colour in boxes],
        "note": note,
    }


def current_marks(ledger, vehicle: list) -> list[tuple]:
    """[(box, label, colour)] to draw now, plus notes as box=None entries."""
    if not getattr(ledger, "marks", None):
        return []
    now = ledger.path[-1][0] if ledger.path else 0.0
    out = []
    for violation, mark in ledger.marks.items():
        shown = violation in ledger.violations or violation in getattr(ledger, "pending", ())
        if not shown or now - mark["t"] > MARK_TTL_S:
            continue
        out += [(to_absolute(rel, vehicle), label, colour) for rel, label, colour in mark["items"]]
        if mark["note"]:
            out.append((None, mark["note"], RED))
    return out


def line_width(thick: int) -> int:
    """Box line width: half of the old `thick + 1`, never below 1 pixel."""
    return max(1, round((thick + 1) / 2))


def place_block(box: list, size: tuple, bw: int, bh: int) -> tuple[int, int]:
    """Top-left corner of a label block (bw x bh) for a box, kept INSIDE a picture of `size` (W, H) even when the box is
    partly outside it: the block sits on the visible part of the box, above it when there is room, else inside its top edge."""
    width, height = size
    x, y = box[0], box[1]
    x0 = min(max(0, x), max(0, width - bw))
    y0 = max(0, y) - bh
    if y0 < 0:
        y0 = max(0, y)
    return int(x0), int(min(y0, max(0, height - bh)))


def draw_label_block(img: np.ndarray, box: list, lines: list, colour: tuple, text_colour: tuple, scale: float, thick: int) -> None:
    """Stack the lines (top to bottom) on a coloured background above the box, kept inside the picture."""
    height, width = img.shape[:2]
    sizes = [cv2.getTextSize(line, cv2.FONT_HERSHEY_SIMPLEX, scale, thick)[0] for line in lines]
    rows = [th + 6 for _, th in sizes]
    x0, y = place_block(box, (width, height), max(tw for tw, _ in sizes) + 4, sum(rows))
    for line, (tw, _), row in zip(lines, sizes, rows):
        cv2.rectangle(img, (x0, y), (x0 + tw + 4, y + row), colour, -1)
        cv2.putText(img, line, (x0 + 2, y + row - 4), cv2.FONT_HERSHEY_SIMPLEX, scale, text_colour, thick, cv2.LINE_AA)
        y += row


def draw_timers(frame: np.ndarray, ledger, vehicle: list) -> None:
    """The stopwatch chips, stacked up from the bottom edge of the vehicle's box, kept inside the picture."""
    chips = current_timers(ledger)
    if not chips:
        return
    height, width = frame.shape[:2]
    scale = max(0.4, height / 1400)
    thick = max(1, height // 400)
    vx, vy, vw, vh = vehicle
    bottom = int(min(vy + vh, height))
    for text, colour in chips:
        (tw, th), _ = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, scale, thick)
        bw, bh = tw + 6, th + 8
        x = int(min(max(0, vx), max(0, width - bw)))
        y = int(max(0, min(bottom - bh, height - bh)))
        cv2.rectangle(frame, (x, y), (x + bw, y + bh), colour, -1)
        cv2.putText(frame, text, (x + 3, y + bh - 5), cv2.FONT_HERSHEY_SIMPLEX, scale,
                    (255, 255, 255) if colour == RED else (0, 0, 0), thick, cv2.LINE_AA)
        bottom = y


def mark_specs(ledger, vehicle: list) -> list[dict]:
    """The marks of one vehicle as plain data (BGR colours), for the replay's box file: {box, color, lines}, {note, at}
    or {timer, box, color}: a stopwatch chip on the bottom edge of the vehicle's box."""
    out = [{"timer": text, "box": [int(v) for v in vehicle], "color": list(colour), "lines": []}
           for text, colour in current_timers(ledger)]
    for box, label, colour in sorted(current_marks(ledger, vehicle), key=lambda it: it[2] == RED):
        if box is None:
            out.append({"note": label, "at": [int(vehicle[0]), int(vehicle[1] + vehicle[3])]})
        else:
            out.append({"box": [int(v) for v in box], "color": list(colour), "lines": [label]})
    return out


def draw_marks(frame: np.ndarray, ledger, vehicle: list) -> np.ndarray:
    """Draw the marks (and the stopwatch chips) of one vehicle in place (and return the frame)."""
    draw_timers(frame, ledger, vehicle)
    items = current_marks(ledger, vehicle)
    if not items:
        return frame
    items.sort(key=lambda it: it[2] == RED)   # the violation (red) boxes last, so they stay on top
    scale = max(0.4, frame.shape[0] / 1400)
    thick = max(1, frame.shape[0] // 400)
    notes = []
    for box, label, colour in items:
        if box is None:
            notes.append(label)
            continue
        x, y, w, h = box
        cv2.rectangle(frame, (x, y), (x + w, y + h), colour, line_width(thick))
        draw_label_block(frame, box, [label], colour, (255, 255, 255), scale, thick)
    vx, vy, vw, vh = vehicle
    for i, note in enumerate(notes):   # e.g. "3 RIDERS (max 2)", "1/2 MIRRORS" under the vehicle
        y = min(frame.shape[0] - 6, vy + vh + int((i + 1) * 28 * scale * 1.6))
        cv2.putText(frame, note, (vx, y), cv2.FONT_HERSHEY_SIMPLEX, scale * 1.1, (0, 0, 0), thick + 3, cv2.LINE_AA)
        cv2.putText(frame, note, (vx, y), cv2.FONT_HERSHEY_SIMPLEX, scale * 1.1, RED, thick, cv2.LINE_AA)
    return frame


PATH_SECONDS = 8.0
PATH_LIGHT = (255, 240, 140)     # a light line (BGR: pale cyan) that shows on dark and bright roads
PATH_RING = (255, 255, 255)      # the ring where the path cut the line


def _smooth(points: list) -> list:
    """Each point is the average of its neighbours (2 each side; fewer near the ends, so the first and the last point stay where they are).
    The box of a detector jitters a few pixels from picture to picture: the trail should look like the way a vehicle drives."""
    out = []
    for i in range(len(points)):
        half = min(2, i, len(points) - 1 - i)
        window = points[i - half:i + half + 1]
        out.append((sum(p[0] for p in window) / len(window), sum(p[1] for p in window) / len(window)))
    return out


def draw_path(frame: np.ndarray, ledger, seconds: float = PATH_SECONDS) -> np.ndarray:
    """The way the vehicle drove, as a light line from where it was `seconds` ago to where it is now (its ground point, in frame pixels),
    in place. Only the part that is ONE vehicle is drawn: the ledger of a tracker number can hold another vehicle before a jump or a long
    silence (engine/track_continuity.py), and the line must never run from one vehicle to another. It is smoothed, fades in toward the
    vehicle, has a dot at the start and a bigger one at the vehicle's ground point, and a ring where it cut a solid line."""
    from engine.track_continuity import last_run
    run = last_run(list(getattr(ledger, "path", ()) or ()))
    if len(run) < 2:
        return frame
    now = run[-1][0]
    run = [p for p in run if now - p[0] <= seconds]
    if len(run) < 2:
        return frame
    points = _smooth([(p[1], p[2]) for p in run])
    points[-1] = (run[-1][1], run[-1][2])                         # the end is the vehicle's own ground point
    rings = [(x, y) for t, x, y in getattr(ledger, "cross_points", ()) if run[0][0] <= t <= now]
    thick = max(3, frame.shape[0] // 240)
    pad = 6 * thick + 4
    fh, fw = frame.shape[:2]
    xs = [p[0] for p in points] + [r[0] for r in rings]
    ys = [p[1] for p in points] + [r[1] for r in rings]
    x0, x1 = max(0, int(min(xs)) - pad), min(fw, int(max(xs)) + pad + 1)      # work on the part of the picture the trail is in
    y0, y1 = max(0, int(min(ys)) - pad), min(fh, int(max(ys)) + pad + 1)
    if x1 <= x0 or y1 <= y0:
        return frame
    roi = frame[y0:y1, x0:x1]
    layer = np.zeros_like(roi)
    mask = np.zeros(roi.shape[:2], np.uint8)

    def at(p):
        return int(round(p[0])) - x0, int(round(p[1])) - y0

    n = len(points)
    for i in range(1, n):
        fade = 0.35 + 0.65 * i / n                                # older = fainter
        cv2.line(layer, at(points[i - 1]), at(points[i]), tuple(int(c * fade) for c in PATH_LIGHT), thick, cv2.LINE_AA)
        cv2.line(mask, at(points[i - 1]), at(points[i]), 255, thick + 2, cv2.LINE_AA)
    cv2.circle(layer, at(points[0]), thick + 1, PATH_LIGHT, -1, cv2.LINE_AA)
    cv2.circle(layer, at(points[-1]), thick + 3, PATH_LIGHT, -1, cv2.LINE_AA)
    cv2.circle(mask, at(points[0]), thick + 3, 255, -1, cv2.LINE_AA)
    cv2.circle(mask, at(points[-1]), thick + 5, 255, -1, cv2.LINE_AA)
    for r in rings:
        cv2.circle(mask, at(r), 4 * thick + 2, 255, thick + 3, cv2.LINE_AA)
        cv2.circle(layer, at(r), 4 * thick, PATH_RING, max(1, thick - 1), cv2.LINE_AA)
    shade = cv2.GaussianBlur(mask, (0, 0), 1.5)[..., None].astype(np.float32) / 255.0   # a soft dark edge under the line, so it reads on a white road
    roi[:] = np.clip(roi.astype(np.float32) * (1 - 0.45 * shade), 0, 255).astype(np.uint8)
    painted = layer.any(axis=2)
    roi[painted] = layer[painted]
    return frame


TRAIL_SECONDS = 4.0
TRAIL_POINTS = 24            # a trail is sent with at most this many points (it is only a picture of the way the vehicle drove)
TRAIL_GAP_S = 0.8            # a silence this long in the path, or a jump of more than TRAIL_JUMP box sizes, ends the trail there
TRAIL_JUMP = 2.5


def trail_specs(mgr, detections, seconds: float = TRAIL_SECONDS) -> list[dict]:
    """The light trail of every vehicle that is on screen now, as plain data (BGR colour): {"trail": [[x, y], ...], "color": [b, g, r]}.
    The Live Monitor draws these under its boxes while Crossing a solid line is on, so a vehicle's way can be checked against the line.
    Only the part of the path that is ONE vehicle is sent (a long silence or a jump ends it), smoothed and thinned out."""
    out = []
    for det in detections:
        ledger = mgr.ledgers.get(getattr(det, "track_id", -1))
        if ledger is None or len(ledger.path) < 2 or getattr(det, "cls", "person") == "person":
            continue
        path = list(ledger.path)
        now = path[-1][0]
        run = [path[-1]]
        for before, after in zip(reversed(path[:-1]), reversed(path[1:])):          # back from the newest picture until the path stops being one vehicle
            if now - before[0] > seconds or after[0] - before[0] > TRAIL_GAP_S:
                break
            if math.hypot(after[1] - before[1], after[2] - before[2]) > TRAIL_JUMP * max(after[3], before[3], 40.0):
                break
            run.append(before)
        run.reverse()
        if len(run) < 3:
            continue
        points = _smooth([(p[1], p[2]) for p in run])
        points[-1] = (run[-1][1], run[-1][2])
        step = max(1, math.ceil(len(points) / TRAIL_POINTS))
        thin = points[::step]
        if thin[-1] != points[-1]:
            thin.append(points[-1])
        out.append({"trail": [[round(x, 1), round(y, 1)] for x, y in thin], "color": list(PATH_LIGHT)})
    return out


def draw_boxes(image: np.ndarray, items: list, note: str | None = None) -> np.ndarray:
    """Draw (box, label, colour) items, boxes in the image's OWN pixels, on a small crop in place (the close-ups kept
    as extra evidence). An optional note goes along the top. Returns the image."""
    h, w = image.shape[:2]
    scale = max(0.4, min(h, w) / 420)
    thick = max(1, min(h, w) // 200)
    for box, label, colour in sorted(items, key=lambda it: it[2] == RED):
        x, y, bw, bh = (int(v) for v in box)
        cv2.rectangle(image, (x, y), (x + bw, y + bh), colour, line_width(thick))
        text_scale = scale
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, text_scale, thick)
        if tw + 6 > w:                                  # a narrow crop: shrink the label so it is not cut off
            text_scale = max(0.25, text_scale * (w - 6) / tw)
            (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, text_scale, 1)
            thick_text = 1
        else:
            thick_text = thick
        x_text = min(max(0, x), max(0, w - tw - 4))     # keep it inside the picture
        ty = y - 4 if y - th - 6 >= 0 else y + bh + th + 4
        ty = min(max(th + 2, ty), h - 4)
        cv2.rectangle(image, (x_text, ty - th - 3), (min(w - 1, x_text + tw + 4), ty + 3), colour, -1)
        cv2.putText(image, label, (x_text + 2, ty), cv2.FONT_HERSHEY_SIMPLEX, text_scale, (255, 255, 255), thick_text, cv2.LINE_AA)
    if note:
        cv2.putText(image, note, (4, int(18 * scale * 1.6)), cv2.FONT_HERSHEY_SIMPLEX, scale * 1.1, (0, 0, 0), thick + 3, cv2.LINE_AA)
        cv2.putText(image, note, (4, int(18 * scale * 1.6)), cv2.FONT_HERSHEY_SIMPLEX, scale * 1.1, RED, thick, cv2.LINE_AA)
    return image
