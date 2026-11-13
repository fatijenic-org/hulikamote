"""
double_parking - a vehicle standing in the travel lane right beside another standing vehicle while traffic keeps moving past.

Heuristic (the operator draws a zone over the travel lane next to the kerb). A vehicle is flagged when ALL hold:
  1. it has stood still (< 25 px/s) inside the zone for longer than the limit (default 8 s);
  2. another vehicle stands still BESIDE it (across the lane, not one behind the other: the direction of the traffic
     that is moving through the zone tells which way "across" is) and has been standing there longer, so the later
     one to stop is the double parker and the kerb vehicle is not flagged;
  3. some third vehicle is moving through the zone right now, so a queue at a red light, where every vehicle is
     stopped, is never flagged.
Limits: it needs moving traffic in the same zone, so draw the zone over the one lane next to the kerb and not over
the whole road; a vehicle that waits beside a kerb vehicle only while traffic happens to flow is judged the same way.
Legal basis: MMDA / LGU anti-obstruction rules (to be confirmed with the Zamboanga City ordinance before it is quoted).
"""
import math

from engine.violations.base import VEHICLE_CLASSES
from engine.violations.geometry import STOP_SPEED, dot, point_in_polygon, stopped_too_long, unit
from engine.violations.box_signs import BoxSigns
from engine.violations.stopped_in_zone import StoppedInZone

MOVING_SPEED = 3 * STOP_SPEED     # px/s; a vehicle faster than this is "traffic flowing"
FRESH_S = 1.0                     # a vehicle not seen for longer than this has left the scene


def still_for(ledger) -> float:
    """Seconds the vehicle has stayed within a third of its width of where it is now (capped by the path length)."""
    t_last, cx, cy, w = ledger.path[-1]
    radius = max(10.0, 0.3 * w)
    since = t_last
    for t, x, y, _w in reversed(ledger.path):
        if math.hypot(x - cx, y - cy) > radius:
            break
        since = t
    return t_last - since


class DoubleParking(BoxSigns, StoppedInZone):
    sign_kind = "double_parking"                       # the object placed for it (engine/overlay_objects.py)
    key = "double_parking"
    zone_key = "double_parking_zones"
    whole_frame = True
    color = (200, 120, 255)
    default_limit_s = 8.0

    @staticmethod
    def _beside(a, b, direction) -> bool:
        """b stands across the lane from a (direction = unit vector of the moving traffic), not in front of or behind it."""
        _t, ax, ay, abox = a.history[-1]
        _t, bx, by, bbox = b.history[-1]
        narrow, wide = min(abox[2], bbox[2]), max(abox[2], bbox[2])
        dx, dy = bx - ax, by - ay
        along = abs(dot((dx, dy), direction))
        across = abs(direction[0] * dy - direction[1] * dx)
        return 0.4 * narrow <= across <= 2.5 * wide and along <= 1.5 * narrow

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...], "time_limit": seconds}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.history) < self.MIN_UPDATES or ledger.vclass not in VEHICLE_CLASSES:
            return False
        now, cx, cy = ledger.history[-1][0], ledger.history[-1][1], ledger.history[-1][2]
        zone = next((z for z in zones if point_in_polygon(cx, cy, z["polygon"])), None)
        limit = (zone or {}).get("time_limit") or self.default_limit_s
        if not stopped_too_long(ledger, self.key, zone is not None, limit):
            return False

        others = [o for o in mgr.ledgers.values()
                  if o is not ledger and o.vclass in VEHICLE_CLASSES and o.history and now - o.history[-1][0] <= FRESH_S]
        flowing = [o for o in others
                   if o.get_speed() >= MOVING_SPEED and point_in_polygon(o.history[-1][1], o.history[-1][2], zone["polygon"])]
        if not flowing:
            return False
        direction = unit(*flowing[0].get_movement_vector())
        mine = still_for(ledger)
        if any(o.get_speed() < STOP_SPEED and self._beside(ledger, o, direction) and still_for(o) > mine for o in others):
            ledger.violations.add(self.key)
            return True
        return False
