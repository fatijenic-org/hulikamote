"""
indicators.py - does a vehicle show a blinking indicator (turn signal or hazard lights)?

Two rules use it:
  signal_light    a turn needs a blinking indicator;
  illegal_parking a vehicle with a blinking indicator has not parked yet.

sample_indicators() runs once per frame and writes one (t, left amber, right amber) sample per vehicle into ledger.blink,
however many rules ask for it (a second call in the same frame adds nothing).
is_signalling() reads those samples with the blink test in engine/traffic_light.py: a steady on/off rhythm at 0.5 - 3 Hz, so
constantly amber paint or a parking light does not count.
"""
from engine.slicer import NumpySlicer
from engine.traffic_light import amber_fraction, is_blinking
from engine.violations.base import VEHICLE_CLASSES

EDGE_SHARE = 0.3        # indicators sit at the left and right edge: read the outer 30% of the vehicle's box on each side


def sample_indicators(pipe, frame, detections, wanted=None) -> None:
    """Record the amber share of each vehicle's left / right edge.
    wanted: optional test on the ledger; a vehicle it rejects is not sampled (saves time for rules that only need parked vehicles)."""
    for det in detections:
        ledger = pipe.ledger_manager.ledgers.get(det.track_id)
        if ledger is None or det.cls not in VEHICLE_CLASSES or not ledger.path:
            continue
        t = ledger.path[-1][0]
        if ledger.blink and ledger.blink[-1][0] == t:       # another rule already read this vehicle in this frame
            continue
        if wanted is not None and not wanted(ledger):
            continue
        crop = NumpySlicer.crop_box(frame, det.bbox)
        if crop.size == 0:
            continue
        edge = max(1, int(crop.shape[1] * EDGE_SHARE))
        ledger.blink.append((t, amber_fraction(crop[:, :edge]), amber_fraction(crop[:, -edge:])))


def is_signalling(ledger, t: float, lookback_s: float) -> bool:
    """True when the left or the right edge blinked during the last lookback_s seconds."""
    recent = [s for s in ledger.blink if s[0] >= t - lookback_s]
    return is_blinking([(s[0], s[1]) for s in recent]) or is_blinking([(s[0], s[2]) for s in recent])
