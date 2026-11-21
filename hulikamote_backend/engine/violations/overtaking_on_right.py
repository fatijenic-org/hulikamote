"""
overtaking_on_right - passing another moving vehicle on its right side.

Legal basis (RA 4136 Sec. 39): a driver who overtakes a vehicle going the same way must pass on its LEFT.
Passing on the right is legal on a road with two or more lanes for traffic in one direction, and beside a vehicle
that is turning left. The lane count cannot be seen by the system, so the operator states it: the rule is only
switched on (or its zone only drawn) where passing on the right is not allowed; a zone with "one_way_lanes" of 2
or more is never judged. Exact wording of the exceptions: TO CONFIRM with the adviser.

Heuristic, judged for vehicle A against every other vehicle B in the same zone, over the last 3 s both were tracked:
  - both are driving (not stopped, not parked) and travel the same way (within 30 deg),
  - A was BEHIND B by at least half of B's box width and is now AHEAD of it by as much (measured along B's travel),
  - at the moment A drew level it was on B's RIGHT (the driver's right: image right when driving up the picture,
    image left when driving down), between 0.3 and 3 box widths away (nearer is the same lane, farther is another road),
  - B did not turn left during the pass (its heading swung less than 20 deg to the left).
Both tracks must exist during the whole pass, so a tracker ID that jumps from one car to another is not a pass: each path is cut where
it stops being one vehicle (engine/track_continuity.py, engine/violations/run_mark.py), and only the part both vehicles share is read.
The same verdict must hold for HOLD_PICTURES new pictures of the passing vehicle in a row (one wrong box is not a pass). The light path
line of the passing vehicle, with a ring where it was flagged, is drawn on the live evidence photos.

VIEW REQUIRED: both vehicles visible during the whole pass, seen from the front or the rear at a moderate height.
A side view cannot tell left from right (one vehicle hides the other).
"""
import math

from engine import marks
from engine.track_continuity import last_run
from engine.violations.base import Violation
from engine.violations.geometry import dot, is_driving, point_in_polygon, unit
from engine.violations.run_mark import run_start

WINDOW_S = 3.0                    # the pass must happen within this long
MIN_PASS_S = 0.8                  # ...and both vehicles must be tracked together at least this long
SAME_WAY_COS = math.cos(math.radians(30.0))
LEFT_TURN_SIN = math.sin(math.radians(20.0))
AHEAD_WIDTHS = 0.5                # behind -> ahead by this many widths of the overtaken vehicle
MIN_SIDE_WIDTHS, MAX_SIDE_WIDTHS = 0.3, 3.0
MIN_TRAVEL_PX = 15.0              # a direction needs this much travel (beats box jitter)
HOLD_PICTURES = 3                 # new pictures of the passing vehicle in a row that must show the pass


def _since(path, t0: float) -> list:
    """The points of a path (t, cx, cy, w) from time t0 on, oldest first."""
    out = []
    for p in reversed(path):
        if p[0] < t0:
            break
        out.append(p)
    out.reverse()
    return out


def _travel(a, b):
    """Unit direction from point a to point b, or None when they are too close to tell."""
    dx, dy = b[1] - a[1], b[2] - a[2]
    return unit(dx, dy) if math.hypot(dx, dy) >= MIN_TRAVEL_PX else None


class PassWatch:
    """One vehicle about one other vehicle: how many NEW pictures of it in a row show that it passed the other one on its right."""

    def __init__(self):
        self.last_t = None
        self.n = 0

    def update(self, t, hit: bool) -> bool:
        if self.last_t is not None and t <= self.last_t:
            return False                                 # not a new picture: nothing is counted twice
        self.last_t = t
        self.n = self.n + 1 if hit else 0
        return self.n >= HOLD_PICTURES


def _run_from(path) -> float:
    """When the newest part of `path` that is one vehicle began."""
    run = last_run(list(path))
    return run[0][0] if run else path[0][0]


def passed_on_right(a_path, b_path, a_from=None, b_from=None) -> bool:
    """True when the vehicle with path `a_path` has just overtaken the one with `b_path` on its right (see the module text).
    `a_from` / `b_from`: when the newest continuous run of each path began (run_mark.run_start); worked out here when not given."""
    if not a_path or not b_path:
        return False
    a_from = _run_from(a_path) if a_from is None else a_from
    b_from = _run_from(b_path) if b_from is None else b_from
    now = min(a_path[-1][0], b_path[-1][0])
    t0 = max(a_path[0][0], b_path[0][0], now - WINDOW_S, a_from, b_from)      # only the part where both are one vehicle
    if now - t0 < MIN_PASS_S:
        return False
    a, b = _since(a_path, t0), _since(b_path, t0)
    if len(a) < 3 or len(b) < 3:
        return False
    way = _travel(b[0], b[-1])                       # the overtaken vehicle's travel over the pass
    a_way = _travel(a[0], a[-1])
    if way is None or a_way is None or dot(a_way, way) < SAME_WAY_COS:
        return False
    half = len(b) // 2                               # a left turn of the overtaken vehicle makes the pass legal
    first, second = _travel(b[0], b[half]), _travel(b[half], b[-1])
    if first is not None and second is not None and first[0] * second[1] - first[1] * second[0] <= -LEFT_TURN_SIN:
        return False

    right = (-way[1], way[0])                        # the driver's right, in picture coordinates (y grows downward)
    width = max(1.0, b[-1][3])
    along, side = [], []
    j = 0
    for t, ax, ay, _w in a:                          # pair every point of A with B's point at the same time
        while j + 1 < len(b) and b[j + 1][0] <= t:
            j += 1
        rel = (ax - b[j][1], ay - b[j][2])
        along.append(dot(rel, way))
        side.append(dot(rel, right))
    if along[0] > -AHEAD_WIDTHS * width or along[-1] < AHEAD_WIDTHS * width:
        return False
    level = min(range(len(along)), key=lambda i: abs(along[i]))     # the moment the two were side by side
    return MIN_SIDE_WIDTHS * width <= side[level] <= MAX_SIDE_WIDTHS * width


class OvertakingOnRight(Violation):
    key = "overtaking_on_right"
    zone_key = "overtaking_zones"
    whole_frame = True
    color = (180, 105, 255)

    def parse_zone(self, raw):
        zone = super().parse_zone(raw)
        if zone is not None:
            zone["one_way_lanes"] = int(raw.get("one_way_lanes", 1))
        return zone

    def from_wizard(self, cfg):
        lanes = int(cfg.get("one_way_lanes", 1))
        return [{**z, "one_way_lanes": lanes} for z in super().from_wizard(cfg)]

    def whole_frame_zone(self, cfg, polygon, frame_size, flow):
        return {**super().whole_frame_zone(cfg, polygon, frame_size, flow), "one_way_lanes": int(cfg.get("one_way_lanes", 1))}

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "one_way_lanes": 1}. Two or more one-way lanes: passing on the right is legal there."""
        ledger = mgr.ledgers.get(track_id)
        if ledger is None or not zones or len(ledger.path) < 3 or self.key in ledger.violations:
            return False
        if "person" in (ledger.vclass, ledger.latest_class) or not is_driving(ledger):
            for watch in ledger.pass_watch.values():
                watch.n = 0                                  # not driving: what was seen of a pass is stale
            return False
        now, cx, cy, _w = ledger.path[-1]
        a_from = run_start(ledger)
        for zone in zones:
            if zone.get("one_way_lanes", 1) >= 2 or not point_in_polygon(cx, cy, zone["polygon"]):
                continue
            for other_id, other in mgr.ledgers.items():
                if other_id == track_id or len(other.path) < 3 or "person" in (other.vclass, other.latest_class):
                    continue
                _ot, ox, oy, _ow = other.path[-1]
                watch = ledger.pass_watch.setdefault(other_id, PassWatch())
                if not point_in_polygon(ox, oy, zone["polygon"]) or not is_driving(other):
                    watch.n = 0
                    continue
                if watch.last_t is not None and now <= watch.last_t:
                    continue                                 # no new picture of this vehicle since the last look
                if watch.update(now, passed_on_right(ledger.path, other.path, a_from, run_start(other))):
                    ledger.cross_points.append((now, cx, cy))      # a ring on the live evidence photo
                    ledger.violations.add(self.key)
                    if ledger.history and other.history:
                        marks.set_marks(ledger, self.key, ledger.history[-1][3],
                                        [(other.history[-1][3], "passed on its right", marks.YELLOW)],
                                        note="OVERTOOK ON THE RIGHT")
                    return True
        return False
