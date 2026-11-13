"""
swerving - weaving from side to side.

Heuristic: over the last 6 s the path is smoothed, then each point's sideways offset from the
straight line (first -> last point) is measured. A swing counts only when the offset moves back by
at least half the median box width (box jitter and a single lane change are ignored); two or more
reversals (left-right-left) flag the vehicle. Box widths keep the threshold fair near and far from
the camera. A vehicle that travelled less than two box widths is not judged.
"""
import math

import numpy as np

from engine.violations.base import Violation
from engine.violations.geometry import point_in_polygon

SWERVE_WINDOW_S = 6.0
SWERVE_AMPLITUDE = 0.5      # box widths
SWERVE_MIN_REVERSALS = 2


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

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...]}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < 10:
            return False

        t_last, cx, cy, _w = ledger.path[-1]
        if not any(point_in_polygon(cx, cy, z["polygon"]) for z in zones):
            return False

        pts = np.array([p for p in ledger.path if p[0] >= t_last - SWERVE_WINDOW_S], dtype=float)
        if len(pts) < 10:
            return False
        k = 5
        xs = np.convolve(pts[:, 1], np.ones(k) / k, mode="valid")
        ys = np.convolve(pts[:, 2], np.ones(k) / k, mode="valid")
        width = float(np.median(pts[:, 3]))

        dx, dy = xs[-1] - xs[0], ys[-1] - ys[0]
        length = math.hypot(dx, dy)
        if width <= 0 or length < 2 * width:   # barely moving: nothing to judge
            return False
        lateral = (xs - xs[0]) * (-dy / length) + (ys - ys[0]) * (dx / length)

        if count_swings(lateral, SWERVE_AMPLITUDE * width) >= SWERVE_MIN_REVERSALS:
            ledger.violations.add(self.key)
            return True
        return False
