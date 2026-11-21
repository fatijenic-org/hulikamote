"""
swerving - weaving from side to side.

The vehicle is followed as ONE vehicle (engine/violations/swerve_watch.py): the trackers hand a number to another vehicle now and then, and
the old rule read the zig-zag of such a jump as weaving. Over the last 6 s of an unbroken run the path is smoothed, then each point's
sideways offset from the straight line (first -> last point) is measured in BOX WIDTHS of the vehicle at that moment (fair near and far from
the camera). A swing counts only when the offset moves back by at least half a box width (box jitter and a single lane change are ignored);
two or more reversals (left-right-left), held for several pictures in a row, flag the vehicle. A vehicle that does not really drive
(a creeping queue, a stop, backing up) is not judged. The light path line of the vehicle, with a ring where it was flagged, is drawn on
the live evidence photos.
"""
from engine.track_stitcher import compute_signature
from engine.violations.base import Violation
from engine.violations.geometry import point_in_polygon
from engine.violations.swerve_watch import AMPLITUDE_WIDTHS as SWERVE_AMPLITUDE   # noqa: F401  (kept for older imports)
from engine.violations.swerve_watch import MIN_REVERSALS as SWERVE_MIN_REVERSALS  # noqa: F401
from engine.violations.swerve_watch import WINDOW_S as SWERVE_WINDOW_S            # noqa: F401
from engine.violations.swerve_watch import SwerveWatch


def count_swings(values, amplitude: float) -> int:
    """Count direction reversals in a 1-D signal, ignoring moves smaller than `amplitude`."""
    extreme, trend, reversals = values[0], 0, 0
    for v in values[1:]:
        if trend == 0:
            if abs(v - extreme) >= amplitude:
                trend, extreme = (1 if v > extreme else -1), v
        elif trend * (v - extreme) > 0:
            extreme = v                      # still moving the same way: new extreme
        elif abs(v - extreme) >= amplitude:
            trend, extreme = -trend, v       # moved back far enough: a reversal
            reversals += 1
    return reversals


class Swerving(Violation):
    key = "swerving"
    zone_key = "swerving_zones"
    whole_frame = True
    color = (0, 255, 0)

    def prepare(self, pipe, frame, detections, zones, t):
        """Once per picture: keep it, so the colours of a vehicle can be looked at when its weaving is about to be believed."""
        pipe.ledger_manager.swerve_frame = frame

    @staticmethod
    def _signature(mgr, ledger):
        frame = getattr(mgr, "swerve_frame", None)
        if frame is None or not ledger.history:
            return None
        return compute_signature(frame, ledger.history[-1][3])

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...]}. Asked for every vehicle on every picture, also for one that was not seen in it: only a NEW picture
        of the vehicle counts (engine/violations/swerve_watch.py decides whether it really weaves)."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if not ledger.path or not ledger.history or ledger.latest_class == "unknown":
            return False
        t, cx, cy, w = ledger.path[-1]
        zone = next((i for i, z in enumerate(zones) if point_in_polygon(cx, cy, z["polygon"])), None)
        if zone is None:                                  # outside every zone: not judged, and what was known is stale
            for watch in ledger.swerve_watch.values():
                watch.leave(t)
            return False
        sample = (t, cx, cy, w, ledger.history[-1][3][3])
        watch = ledger.swerve_watch.setdefault((self.key, zone), SwerveWatch())
        found = watch.update(sample, lambda: self._signature(mgr, ledger), ledger.latest_class)
        if found is None:
            return False
        ledger.cross_points.append((found.t, found.point[0], found.point[1]))     # where it was believed: a ring on the live evidence photo
        ledger.violations.add(self.key)
        return True
