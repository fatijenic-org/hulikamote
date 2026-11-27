"""
incoming.py - two-wheelers that come TOWARD the camera are not judged.

A motorcycle, a tricycle or a kuliglig seen from the front shows no plate (the rule asks for a rear plate on two-wheelers, and a tricycle's
number is on its back), so a ticket for it could never name its owner. The pipeline therefore leaves such a vehicle out: no box, no rule,
no ticket. The same vehicle is judged normally when it goes AWAY from the camera (its rear and plate are visible then).

"Toward the camera" is read from the vehicle's own path, with no model and no setup: in a road picture a vehicle that comes closer moves
DOWN the picture and gets BIGGER. A vehicle that stands still, or whose direction is not clear yet, is not called incoming (it stays judged).

The wizard's demo switch "Judge incoming motorcycles and tricycles too" (config `judge_incoming_two_wheelers`) turns this rule off.
"""
import math

FRONT_UNPLATED = ("motorcycle", "tricycle", "kuliglig")   # classes whose plate cannot be read from the front
WINDOW_S = 1.5            # the part of the path that is looked at (seconds)
MIN_SAMPLES = 6
MIN_SPAN_S = 0.6          # the path in the window must last this long
MIN_MOVE = 0.25           # ... and cover this share of the vehicle's width, or it is standing still
DOWN_RATIO = 0.6          # "mostly down the picture": dy >= this x |dx|
GROWTH = 1.05             # the box got at least this much wider


def is_incoming(path) -> bool | None:
    """True: comes toward the camera. False: goes away. None: not clear (standing still, or too little path yet).
    `path` = the ledger's (time, cx, cy, width) samples, the newest last (cy is the bottom of the box)."""
    samples = list(path)
    if len(samples) < MIN_SAMPLES:
        return None
    newest = samples[-1][0]
    window = [s for s in samples if newest - s[0] <= WINDOW_S]
    if len(window) < MIN_SAMPLES or window[-1][0] - window[0][0] < MIN_SPAN_S:
        return None
    t0, x0, y0, w0 = window[0]
    t1, x1, y1, w1 = window[-1]
    dx, dy = x1 - x0, y1 - y0
    if math.hypot(dx, dy) < MIN_MOVE * max(w0, w1, 1.0):
        return None
    grows = w1 >= w0 * GROWTH
    if dy > 0 and dy >= DOWN_RATIO * abs(dx) and grows:
        return True
    if dy < 0 and not grows:
        return False
    return None
