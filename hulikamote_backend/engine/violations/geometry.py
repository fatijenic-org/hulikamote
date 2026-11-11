"""
geometry.py - movement and geometry pieces shared by several violation rules.

Every function works on a TrackLedger (engine/ledger.py): `ledger.path` is [(t, x, y, box_width)]
with (x, y) the point where the tyres touch the road, and `ledger.history` is the same with the box.
Per-rule memory (timers, entry headings, line sides) lives on the ledger under a key that includes
the rule name and zone number, so rules never share state.
"""
import math

import cv2
import numpy as np

STOP_SPEED = 25.0   # px/s; below this a vehicle counts as stopped (jitter filter: boxes "breathe" a little)
TURN_MIN_ANGLE_COS = math.cos(math.radians(45.0))   # heading must swing at least 45 deg to count as a turn
TURN_ALIGN_COS = math.cos(math.radians(45.0))       # "pointing along an arrow" = within 45 deg of it
U_TURN_COS = math.cos(math.radians(150.0))          # a heading swing of 150 deg or more is a U-turn, not a turn
MIN_SPEED_WIDTHS = 0.25                             # "driving" = at least this many box widths per second


def unit(x: float, y: float) -> tuple[float, float]:
    mag = math.hypot(x, y)
    return (x / mag, y / mag) if mag > 0 else (0.0, 0.0)


def dot(a: tuple, b: tuple) -> float:
    return a[0] * b[0] + a[1] * b[1]


def point_in_polygon(x: float, y: float, polygon: list) -> bool:
    """OpenCV's pointPolygonTest: points on the edge count as inside."""
    poly = np.array(polygon, dtype=np.int32)
    return cv2.pointPolygonTest(poly, (float(x), float(y)), False) >= 0


def step(ledger) -> float:
    """Travel needed before a heading counts: half a box width, at least 15 px (beats box jitter)."""
    return max(15.0, 0.5 * ledger.path[-1][3])


def stopped_too_long(ledger, key, in_zone: bool, limit: float) -> bool:
    """Own timer per key: True once stopped inside the zone for `limit` seconds."""
    t = ledger.history[-1][0]
    if not in_zone or len(ledger.history) < 5 or ledger.get_speed() >= STOP_SPEED:
        ledger.stop_timers.pop(key, None)
        return False
    start = ledger.stop_timers.setdefault(key, t)
    return t - start >= limit


def recent_speed(ledger, seconds: float) -> float:
    """Speed (px/s) over the last `seconds` of the path; inf until that much time is covered."""
    t_last, cx, cy, _w = ledger.path[-1]
    for t, px, py, _pw in reversed(ledger.path):
        if t_last - t >= seconds:
            return math.hypot(cx - px, cy - py) / (t_last - t)
    return math.inf


def is_driving(ledger) -> bool:
    """Really moving over the last second: at least 2 x STOP_SPEED and a quarter of a box width per second.
    A parked vehicle's box drift and jitter are not driving."""
    speed = recent_speed(ledger, 1.0)               # inf until a second of path exists
    return speed != math.inf and speed >= max(2 * STOP_SPEED, MIN_SPEED_WIDTHS * ledger.path[-1][3])


def heading(ledger):
    """Current heading (unit vector) over the last `step` px of travel, or None if barely moving."""
    _t, cx, cy, _w = ledger.path[-1]
    needed = step(ledger)
    for _pt, px, py, _pw in reversed(ledger.path):
        if math.hypot(cx - px, cy - py) >= needed:
            return unit(cx - px, cy - py)
    return None


def moving_along(ledger, arrow) -> bool:
    """True if the vehicle is heading within 45 deg of `arrow`."""
    current, arrow = heading(ledger), unit(*(arrow or (0.0, 0.0)))
    return current is not None and arrow != (0.0, 0.0) and dot(current, arrow) >= TURN_ALIGN_COS


def turn_headings(ledger, key):
    """
    (heading just after entering the zone, heading now), or None while those are not known yet.
    Call only while inside the zone; the entry heading is learned from the first `step` px of
    travel after entering.
    """
    _t, cx, cy, _w = ledger.path[-1]
    if key not in ledger.turn_entry:
        ledger.turn_entry[key] = (cx, cy)
        return None
    if key not in ledger.turn_heading:
        ex, ey = ledger.turn_entry[key]
        if math.hypot(cx - ex, cy - ey) >= step(ledger):
            ledger.turn_heading[key] = unit(cx - ex, cy - ey)
        return None
    current = heading(ledger)
    return None if current is None else (ledger.turn_heading[key], current)


def turned_into(ledger, key, arrow) -> bool:
    """
    True when the heading swung by >= 45 deg since entering the zone, now points along `arrow`
    (within 45 deg) and did NOT already point that way on entry (driving straight is not a turn).
    Call only while inside the zone.
    """
    headings, arrow = turn_headings(ledger, key), unit(*(arrow or (0.0, 0.0)))
    if headings is None or arrow == (0.0, 0.0):
        return False
    entry, current = headings
    return (
        dot(entry, current) <= TURN_MIN_ANGLE_COS
        and dot(current, arrow) >= TURN_ALIGN_COS
        and dot(entry, arrow) < TURN_ALIGN_COS
    )


def turned_side(ledger, key) -> str | None:
    """
    'left' or 'right' once the heading has swung 45 to 150 deg since the vehicle entered the zone (a wider swing
    is a U-turn), else None. Left / right as the driver sees it: a right turn is clockwise on the picture.
    Call only while inside the zone.
    """
    headings = turn_headings(ledger, key)
    if headings is None:
        return None
    entry, current = headings
    swing = dot(entry, current)
    if swing > TURN_MIN_ANGLE_COS or swing <= U_TURN_COS:
        return None
    return "right" if entry[0] * current[1] - entry[1] * current[0] > 0 else "left"


def line_side(line, x: float, y: float):
    """
    Which side of a line a point is on, and how far: the signed distance, or None when the point is
    beside neither end of the line (so the line does not judge points far past its ends).

    `line` is two or more points ([[x, y], ...]); with more than two it is a bent line (a curve, a
    corner) and the nearest straight piece of it decides. The sign never flips while the point moves
    along one side of the line, also around a bend, so "crossed" means really crossed.
    """
    pieces = []
    for (x1, y1), (x2, y2) in zip(line, line[1:]):
        lx, ly = x2 - x1, y2 - y1
        length = math.hypot(lx, ly)
        if length > 0:
            pieces.append((x1, y1, lx, ly, length))
    if not pieces:
        return None
    best = None
    for index, (x1, y1, lx, ly, length) in enumerate(pieces):
        along = ((x - x1) * lx + (y - y1) * ly) / (length * length)
        near = min(max(along, 0.0), 1.0)
        distance = math.hypot(x - (x1 + near * lx), y - (y1 + near * ly))
        if best is None or distance < best[0] - 1e-9:
            best = (distance, index, along, ((x - x1) * ly - (y - y1) * lx) / length)
    _distance, index, along, side = best
    if (index == 0 and along < -0.1) or (index == len(pieces) - 1 and along > 1.1):
        return None
    return side


def crossed_line(ledger, key, line) -> bool:
    """
    True only on the frame the vehicle's ground point crosses `line` ([[x1,y1],[x2,y2]], or more points
    for a bent line), coming from the side it was first seen on. It must end up clearly past the line
    (30% of its box width, at least 10 px), so a car stopped ON the line with its box wobbling back and
    forth is not a crossing. Points beyond the line's ends are ignored.
    """
    if not line or len(line) < 2:
        return False
    _t, cx, cy, w = ledger.path[-1]
    side = line_side(line, cx, cy)       # signed distance from the line
    if side is None:
        return False
    margin = max(10.0, 0.3 * w)
    state = ledger.line_side.get(key)
    if state is None:
        if abs(side) >= margin:
            ledger.line_side[key] = 1.0 if side > 0 else -1.0
        return False
    if state == "crossed" or side * state > -margin:
        return False
    ledger.line_side[key] = "crossed"
    return True


def rider_boxes(moto_bbox: list, person_bboxes: list) -> list:
    """
    People riding a motorcycle: feet (bottom-centre of the person box) inside the motorcycle's
    width and around its lower body, and at least 30% of the person box over the motorcycle box.
    Boxes are [x, y, w, h].
    """
    mx, my, mw, mh = moto_bbox
    riders = []
    for box in person_bboxes:
        px, py, pw, ph = box
        if pw <= 0 or ph <= 0:
            continue
        foot_x, foot_y = px + pw / 2, py + ph
        if not (mx <= foot_x <= mx + mw):
            continue
        if not (my + 0.3 * mh <= foot_y <= my + 1.15 * mh):
            continue
        ix = max(0.0, min(px + pw, mx + mw) - max(px, mx))
        iy = max(0.0, min(py + ph, my + mh) - max(py, my))
        if ix * iy / (pw * ph) >= 0.3:
            riders.append(box)
    return riders


def front_or_rear_view(ledger) -> bool:
    """True when the vehicle moves mostly up or down the image, i.e. the camera sees its front or rear
    (both side mirrors visible); False when it moves sideways or barely moves."""
    dx, dy = ledger.get_movement_vector()
    return math.hypot(dx, dy) >= 6.0 and abs(dy) >= abs(dx)
