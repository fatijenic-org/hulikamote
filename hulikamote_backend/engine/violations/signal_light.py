"""
signal_light - turning without a blinking indicator.  EXPERIMENTAL: it can over-flag (hand signals
are lawful under RA 4136 s44, motorcycles are exempt from signal lights under s34(f), and a
distant or tinted indicator is hard to see), so it is not a headline result.

Heuristic: inside a zone, the vehicle's heading swings by 45 deg or more (a turn) and neither its
left nor its right edge showed a blinking amber light during the last 5 s. Each turn is judged once.
prepare() samples the amber share of each vehicle's left / right 30% edge every frame into
ledger.blink; is_blinking (engine/traffic_light.py) wants a steady on/off rhythm at 0.5 - 3 Hz, so
constantly amber paint or a parking light does not count as blinking.
"""
from engine.slicer import NumpySlicer
from engine.traffic_light import amber_fraction, is_blinking
from engine.violations.base import VEHICLE_CLASSES, Violation
from engine.violations.geometry import TURN_MIN_ANGLE_COS, dot, point_in_polygon, turn_headings

SIGNAL_LOOKBACK_S = 5.0


class SignalLight(Violation):
    key = "signal_light"
    zone_key = "signal_light_zones"
    auto = True
    color = (0, 165, 255)

    MIN_PATH_POINTS = 4
    EDGE_SHARE = 0.3

    def prepare(self, pipe, frame, detections, zones, t):
        """Record the amber share of each vehicle's left / right edge (where indicators sit)."""
        for det in detections:
            ledger = pipe.ledger_manager.ledgers.get(det.track_id)
            if ledger is None or det.cls not in VEHICLE_CLASSES or not ledger.path:
                continue
            crop = NumpySlicer.crop_box(frame, det.bbox)
            if crop.size == 0:
                continue
            edge = max(1, int(crop.shape[1] * self.EDGE_SHARE))
            ledger.blink.append((ledger.path[-1][0], amber_fraction(crop[:, :edge]), amber_fraction(crop[:, -edge:])))

    def evaluate(self, mgr, track_id, zones):
        """Each zone: {"polygon": [...]}."""
        if track_id not in mgr.ledgers or not zones:
            return False
        ledger = mgr.ledgers[track_id]
        if len(ledger.path) < self.MIN_PATH_POINTS:
            return False
        t, cx, cy, _w = ledger.path[-1]
        for i, zone in enumerate(zones):
            key = (self.key, i)
            if key in ledger.turns_judged or not point_in_polygon(cx, cy, zone["polygon"]):
                continue
            headings = turn_headings(ledger, key)
            if headings is None or dot(*headings) > TURN_MIN_ANGLE_COS:
                continue
            ledger.turns_judged.add(key)
            recent = [s for s in ledger.blink if s[0] >= t - SIGNAL_LOOKBACK_S]
            left = [(s[0], s[1]) for s in recent]
            right = [(s[0], s[2]) for s in recent]
            if not (is_blinking(left) or is_blinking(right)):
                ledger.violations.add(self.key)
                return True
        return False
