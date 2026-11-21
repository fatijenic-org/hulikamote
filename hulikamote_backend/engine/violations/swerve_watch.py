"""
swerve_watch.py - one vehicle: is it REALLY weaving from side to side?

The old check read the path of a tracker NUMBER. The trackers hand a number to another vehicle now and then (see
engine/track_continuity.py), so a path that jumps between two vehicles zig-zags and looked like weaving. And a measure in pixels is not
the same near the camera and far from it. So weaving is only believed when ALL of this holds:

  1. the vehicle was followed picture after picture as ONE run (track_continuity.continues: no long silence, no jump, no change of box
     size, no change from a two-wheeler to a four-wheeler). Whenever the run breaks, everything learned so far is forgotten;
  2. the run covers at least MIN_SPAN_S, and the vehicle really drives along it: at least MIN_CHORD_WIDTHS box widths from the first to
     the last point, at least MIN_SPEED_WIDTHS_PER_S box widths a second, and (nearly) always forward - a queue that creeps and stops, or
     a vehicle that backs up, is not weaving;
  3. the sideways offset from the straight line first -> last, taken in BOX WIDTHS of the vehicle at that moment (so it is fair near and
     far), swings out and back at least AMPLITUDE_WIDTHS (more for a two-wheeler), twice or more (left-right-left): a single lane change or a bend of the road
     is one swing; box jitter is below the amplitude; a swing must take at least MIN_SWING_S;
  4. the same verdict holds for HOLD_SAMPLES pictures in a row, and the colours of the box still look like the vehicle that started the run.

A picture that is not new (the vehicle was not seen this time, the rule is only asked again) is ignored.
"""
import math
from collections import namedtuple

import numpy as np

from engine.track_continuity import continues
from engine.track_stitcher import blend_signature, hist_distance

Swerve = namedtuple("Swerve", "swings amplitude point t")   # how many swings, the biggest one (box widths), where it was believed, and when

TWO_WHEELERS = ("motorcycle", "bicycle")

MIN_BOX_PX = 12
WINDOW_S = 6.0                 # the weaving is looked for in the last this many seconds of the run
MIN_SPAN_S = 2.5               # the run must cover at least this much time
MIN_SAMPLES = 12
SMOOTH = 5                     # pictures averaged to calm box jitter
AMPLITUDE_WIDTHS = 0.5         # a swing counts when the offset moves back by at least this many box widths (a car: about 0.9 m out and back)
TWO_WHEELER_AMPLITUDE = 1.2    # a rider and a bike are narrow and wobble by nature: out and back at least about 0.9 m, as a car
MIN_REVERSALS = 2              # two reversals = left-right-left
MIN_CHORD_WIDTHS = 3.0         # it must travel at least this many box widths from the first to the last point
MIN_SPEED_WIDTHS_PER_S = 0.5   # ... at least this many box widths a second
MIN_SWING_S = 0.3              # one swing (extreme to extreme) takes at least this long
FORWARD_SHARE = 0.75           # share of the steps that go forward along the line
HOLD_SAMPLES = 3               # pictures in a row with the same verdict
HOLD_MIN_SPAN_S = 0.2
SIG_MAX_DISTANCE = 0.6         # colour histogram distance above which it is another vehicle
SIG_REFRESH = 6


def swings(values, times, amplitude: float, min_swing_s: float = 0.0):
    """(reversals, biggest swing) of a 1-D signal. A move smaller than `amplitude` is jitter; a reversal needs the signal to move back by
    `amplitude` from its extreme; a swing between two extremes shorter than `min_swing_s` does not count."""
    extreme, trend, left = 0, 0, []
    for i in range(1, len(values)):
        v = values[i]
        if trend == 0:
            if abs(v - values[extreme]) >= amplitude:
                trend, extreme = (1 if v > values[extreme] else -1), i
        elif trend * (v - values[extreme]) > 0:
            extreme = i                                        # still moving the same way: a new extreme
        elif abs(v - values[extreme]) >= amplitude:
            left.append(extreme)                               # the extreme it just left
            trend, extreme = -trend, i
    count, previous, biggest = 0, 0, 0.0
    for e in left:
        if times[e] - times[previous] >= min_swing_s:
            count += 1
        biggest = max(biggest, abs(values[e] - values[previous]))
        previous = e
    return count, biggest


class SwerveWatch:
    """The memory of one vehicle (one ledger) about weaving. Feed it every NEW picture with update()."""

    def __init__(self):
        self.done = False
        self.last_t = None
        self._forget()

    def _forget(self) -> None:
        self.run: list = []           # (t, x, y, w, h): the pictures of the current run (the newest WINDOW_S seconds)
        self.hold_n = 0
        self.hold_t0 = 0.0
        self.arm_sig = None
        self.sig_n = 0
        self.family = None            # 2: a two-wheeler, 4: any other vehicle

    def leave(self, t) -> None:
        """The vehicle is outside the zone: it is not judged, and what was known is stale."""
        if not self.done:
            self.last_t = t
            self._forget()

    def update(self, sample, signature=None, kind=None):
        """`sample` = (t, x, y, w, h): the ground point and box of the newest picture. `signature` = a function returning the colour histogram
        of the vehicle's box now (or None), called only when needed. `kind` = what the tracker calls the vehicle.
        Returns a Swerve when this picture makes the weaving believable, else None."""
        if self.done:
            return None
        t, x, y, w, h = sample
        if self.last_t is not None and t <= self.last_t:
            return None
        self.last_t = t
        if w < MIN_BOX_PX or h < MIN_BOX_PX:
            self._forget()
            return None
        new = (t, x, y, w, h)
        family = None if kind in (None, "unknown") else (2 if kind in TWO_WHEELERS else 4)
        if self.run and (not continues(self.run[-12:], new) or (family and self.family and family != self.family)):
            self._forget()
        self.family = family or self.family
        if not self.run and signature:
            self.arm_sig = signature()
        self.run.append(new)
        cut = 0
        while cut < len(self.run) - 1 and t - self.run[cut][0] > WINDOW_S:
            cut += 1
        del self.run[:cut]
        if signature and self.sig_n % SIG_REFRESH == 0 and len(self.run) > 1:
            self.arm_sig = blend_signature(self.arm_sig, signature())
        self.sig_n += 1

        found = self._weaving()
        if found is None:
            self.hold_n = 0
            return None
        if self.hold_n == 0:
            self.hold_t0 = t
        self.hold_n += 1
        if self.hold_n < HOLD_SAMPLES or t - self.hold_t0 < HOLD_MIN_SPAN_S:
            return None
        if signature and self.arm_sig is not None:
            colours = signature()
            if colours is not None and hist_distance(self.arm_sig, colours) > SIG_MAX_DISTANCE:
                self._forget()                                 # other colours than the vehicle that started the run: another vehicle
                return None
        self.done = True
        return Swerve(found[0], found[1], (x, y), t)

    def _weaving(self):
        """(swings, biggest swing in box widths) when the run shows weaving, else None."""
        run = self.run
        if len(run) < MIN_SAMPLES or run[-1][0] - run[0][0] < MIN_SPAN_S:
            return None
        pts = np.array([[p[0], p[1], p[2], p[3]] for p in run], dtype=float)
        k = SMOOTH if len(pts) >= 2 * SMOOTH else 3
        kernel = np.ones(k) / k
        xs = np.convolve(pts[:, 1], kernel, mode="valid")
        ys = np.convolve(pts[:, 2], kernel, mode="valid")
        ws = np.convolve(pts[:, 3], kernel, mode="valid")
        ts = pts[k // 2: len(pts) - k // 2, 0]
        dx, dy = xs[-1] - xs[0], ys[-1] - ys[0]
        length = math.hypot(dx, dy)
        width = float(np.median(ws))
        span = float(ts[-1] - ts[0])
        if width <= 0 or span <= 0 or length < MIN_CHORD_WIDTHS * width or length / span < MIN_SPEED_WIDTHS_PER_S * width:
            return None
        ux, uy = dx / length, dy / length
        along = (xs - xs[0]) * ux + (ys - ys[0]) * uy
        if float(np.mean(np.diff(along) > -0.05 * width)) < FORWARD_SHARE:     # it keeps going forward
            return None
        lateral = ((xs - xs[0]) * (-uy) + (ys - ys[0]) * ux) / np.maximum(ws, 1.0)     # in box widths of the moment
        amplitude = TWO_WHEELER_AMPLITUDE if self.family == 2 else AMPLITUDE_WIDTHS
        count, biggest = swings(lateral, ts, amplitude, MIN_SWING_S)
        return (count, biggest) if count >= MIN_REVERSALS else None
