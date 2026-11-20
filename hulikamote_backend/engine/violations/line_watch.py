"""
line_watch.py - one vehicle against one solid line: has it REALLY driven across it?

"The vehicle's number is now on the other side of the line" is not the same thing. The trackers hand a number to another vehicle now and
then (see engine/track_continuity.py), the box of a vehicle half hidden behind a truck jumps about, and a drawn line is never exactly
where the paint is. So a crossing is only believed when ALL of this holds:

  1. the vehicle was followed picture after picture (no long silence, no jump, no change of box size, no change from a two-wheeler
     to a four-wheeler: track_continuity.continues), from before the line to after it, as ONE run. Whenever the run breaks (another vehicle, lost for too long, past either end of
     the line), everything learned so far is forgotten and the vehicle is watched anew;
  2. it first drove ARM_SAMPLES pictures in a row with its footprint (see below) clearly on one side, so its own side is known;
  3. then at least `min_overlap` of its footprint (the operator's setting, 30% to start with) was past the line for HOLD_SAMPLES pictures
     in a row (one wrong box does not make a crossing);
  4. its trip (the leading end of its footprint) from the last picture on its own side to the other side really CUTS the line
     (geometry.line_cut), not round its end;
  5. it still looks like the same vehicle: the colours of its box did not change into another vehicle's (a colour histogram).

  6. it crossed the way a vehicle crosses a line it drives ALONG (a lane change, an overtaking swerve, riding over the line): it was driving
     (not standing or creeping) and its heading at the line was along it (at most MAX_CROSS_ANGLE_DEG), and so was the course it had been
     driving for seconds before (at most MAX_APPROACH_ANGLE_DEG). Cross traffic (a vehicle that comes from the roadside, turns across the
     road into a side street, or makes a U-turn) heads across the line: that is a turn, and the turning rules judge it, not this one;
  7. when it HAS such a course (followed for a second or more before the line), it also STEERED: it had moved sideways from that straight
     course by MIN_SHIFT_WIDTHS box widths or more. A vehicle that drives straight and only meets the line because the drawn line is not
     quite parallel to the road (a drawn line never is) is not flagged. A vehicle with no course yet (a young run) is judged by gate 6 alone.

The FOOTPRINT is where the vehicle touches the road: for a motorcycle (or bicycle) the middle of the bottom edge of its box, for every other
vehicle (car, tricycle, jeepney, bus, truck ...) the whole bottom edge, from its lower left to its lower right corner. "Overlap" is the share of
the footprint that lies past the line, like an IoU of the footprint with the far side of the line: 0 = all on its own side, 1 = all across.

A picture that is not new (the vehicle was not seen this frame, the rule is only asked again) is ignored: nothing is counted twice.
"""
import math
from collections import namedtuple

import numpy as np

from engine.track_stitcher import blend_signature, hist_distance
from engine.track_continuity import continues
from engine.violations.geometry import line_cut, line_side

Crossing = namedtuple("Crossing", "point t angle")   # where the trip cut the line (x, y), when it was believed, and the angle (deg) it cut at

TWO_WHEELERS = ("motorcycle", "bicycle")   # a ledger that turns from one of these into anything else (or back) is another vehicle

MIN_BOX_PX = 12            # a box smaller than this (width or height) says too little about where the vehicle is
DEFAULT_MIN_OVERLAP = 0.30   # the share of the footprint that must be past the line (the operator sets it; this is what it starts with)
MIN_OVERLAP_PX = 4.0       # ... and never less than this many pixels of footprint (a few pixels of box jitter are not a crossing)
OWN_SHARE = 0.999          # its own side: the whole footprint on that side (so the trip that follows starts clear of the line)
TWO_WHEELER_FOOT = 0.4     # a two-wheeler's footprint is this share of the bottom edge, in the middle (a motorcycle: bottom centre)
ARM_SAMPLES = 4            # pictures in a row on one side before that side counts as "its own"
ARM_MIN_SPAN_S = 0.2       # ... and they must cover at least this much time
HOLD_SAMPLES = 3           # pictures in a row on the other side before it counts as crossed
HOLD_MIN_SPAN_S = 0.15     # ... covering at least this much time
LAT_WIDTHS = 0.45          # sideways: it may be this many box widths from where its own sideways speed says ...
LAT_SPEED_SHARE = 0.25     # ... plus this share of the sideways distance it was expected to travel ...
LAT_SLACK_PX = 6.0         # ... plus this much for the jitter of the box
CUT_TOLERANCE_WIDTHS = 0.25  # the line is lengthened by this share of the box width at both ends when asking "did the trip cut it"
MAX_APPROACH_ANGLE_DEG = 40.0  # the course before the line, seen on the picture (a road runs away from the camera: the angle on the road is about half): steeper = cross traffic
MAX_CROSS_ANGLE_DEG = 45.0     # heading at the line: steeper = it is going across, not along
MIN_SHIFT_WIDTHS = 0.3         # with a course: it must have moved sideways this many box widths from it by the time it is over the line
COURSE_FROM_S, COURSE_TO_S = 6.0, 1.0   # its own course: how it drove from 6 s to 1 s before it cut the line ...
COURSE_MIN_SPAN_S = 1.0        # ... over at least this much time,
COURSE_MIN_SAMPLES = 6         # ... in at least this many pictures,
COURSE_MIN_WIDTHS = 1.0        # ... and travelling at least this many box widths (a vehicle that stood or crept has no course)
MIN_HEADING_WIDTHS = 0.3       # the heading at the line is only believed over a trip of at least this many box widths
SIG_MAX_DISTANCE = 0.6     # colour histogram distance above which it is another vehicle (the stitcher accepts up to 0.5 as the same one)
SIG_REFRESH = 5            # refresh its colours every this many pictures on its own side
RUN_KEEP = 12              # samples of the current run that are remembered
HIST_KEEP = 200            # ... and, for its own course before the line (up to 6 s), this many
TRAIL_KEEP = 30            # points of its trip since it was last clearly on its own side


def footprint(x: float, y: float, w: float, two_wheeler: bool):
    """The two ends ((x, y), (x, y)) of the vehicle's footprint on the road, from its ground point (bottom centre) and box width:
    the whole bottom edge (lower corner to lower corner), or only the middle of it for a motorcycle or bicycle."""
    half = (TWO_WHEELER_FOOT if two_wheeler else 1.0) * w / 2.0
    return (x - half, y), (x + half, y)


def positive_share(line, a, b):
    """(share of the segment a-b on the positive side of the line, distance at a, distance at b), or None when an end is beside neither end of
    the line. The distances are signed (px); the sign flips where the segment cuts the line."""
    sa, sb = line_side(line, a[0], a[1]), line_side(line, b[0], b[1])
    if sa is None or sb is None:
        return None
    if sa >= 0 and sb >= 0:
        return 1.0, sa, sb
    if sa <= 0 and sb <= 0:
        return 0.0, sa, sb
    f = sa / (sa - sb)                     # where along a->b the sign changes
    return (f if sa > 0 else 1.0 - f), sa, sb


class LineWatch:
    """The memory of one vehicle (one ledger) about one line (one zone). Feed it every NEW picture of the vehicle with update()."""

    def __init__(self):
        self.done = False             # it was flagged: nothing more to watch
        self.last_angle = None        # the heading (deg to the line) at the newest crossing that was weighed
        self.last_check = None        # what was found about that crossing (see _driving_along)
        self.last_t = None            # time of the newest picture seen (a picture is only ever used once)
        self._forget()

    def _forget(self) -> None:
        """Back to "knows nothing": a new run starts with the next picture."""
        self.run: list = []           # (t, x, y, w, h, s): the pictures of the current run, s = signed distance to the line
        self.side = 0                 # +1 / -1: the side it is armed on, 0: not known yet
        self.cand_side = 0            # the side it has been on for the last few pictures (before it is armed)
        self.cand_n = 0
        self.cand_t0 = 0.0
        self.cross_n = 0              # pictures in a row clearly on the other side
        self.cross_t0 = 0.0
        self.last_own = None          # (x, y, t) of its last picture clearly on its own side
        self.trail: list = []         # (x, y, t) of every picture since
        self.hist: list = []          # (t, x, y, w, h): every picture of the current run (longer than `run`)
        self.arm_sig = None           # the colours it had on its own side
        self.own_n = 0
        self.family = None            # 2: a two-wheeler, 4: any other vehicle (what the current run is)

    def leave(self, t) -> None:
        """The vehicle is outside the road section of this zone: it is not judged here, and what was known is stale."""
        if not self.done:
            self.last_t = t
            self._forget()

    # ── one new picture ──
    def update(self, sample, line, signature=None, kind=None, min_overlap=DEFAULT_MIN_OVERLAP):
        """`sample` = (t, x, y, w, h): the ground point and the box of the newest picture. `signature` = a function returning the colour
        histogram of the vehicle's box now (or None), called only when it is needed. `kind` = what the tracker calls the vehicle now
        ("car", "motorcycle" ...). `min_overlap` = the share (0 to 1) of the footprint that must be past the line. Returns a Crossing when
        this picture makes the crossing believable, else None."""
        if self.done:
            return None
        t, x, y, w, h = sample
        if self.last_t is not None and t <= self.last_t:
            return None
        self.last_t = t
        if w < MIN_BOX_PX or h < MIN_BOX_PX:
            self._forget()
            return None
        s = line_side(line, x, y)
        family = None if kind in (None, "unknown") else (2 if kind in TWO_WHEELERS else 4)
        a, b = footprint(x, y, w, (family or self.family) == 2)
        shares = positive_share(line, a, b)
        if s is None or shares is None:             # beside neither end of the line: not judged, and what was known is stale
            self._forget()
            return None
        q, sa, sb = shares
        new = (t, x, y, w, h, s)
        if self.run and (not self._same_vehicle(new) or (family and self.family and family != self.family)):
            self._forget()
        self.family = family or self.family
        self.run.append(new)
        del self.run[:-RUN_KEEP]
        self.hist.append(new[:5])
        del self.hist[:-HIST_KEEP]

        now = 1 if q >= OWN_SHARE else (-1 if q <= 1.0 - OWN_SHARE else 0)

        if self.side == 0:                          # not armed: which side does it keep to?
            if now == 0:
                self.cand_side, self.cand_n = 0, 0
                return None
            if now == self.cand_side:
                self.cand_n += 1
            else:
                self.cand_side, self.cand_n, self.cand_t0 = now, 1, t
            if self.cand_n >= ARM_SAMPLES and t - self.cand_t0 >= ARM_MIN_SPAN_S:
                lead = self._lead(a, b, sa, sb, self.cand_side)
                self.side, self.last_own, self.trail, self.cross_n, self.own_n = self.cand_side, (lead[0], lead[1], t), [], 0, 0
                self.arm_sig = signature() if signature else None
            return None

        lead = self._lead(a, b, sa, sb, self.side)  # the end of the footprint that is nearest to the other side
        past = (1.0 - q) if self.side == 1 else q   # the share of the footprint that is past the line
        need = min(0.98, max(min_overlap, MIN_OVERLAP_PX / max(b[0] - a[0], 1.0)))
        if past < need:
            if now == self.side:                    # on its own side
                self.cross_n, self.trail, self.last_own = 0, [], (lead[0], lead[1], t)
                self.own_n += 1
                if signature and self.own_n % SIG_REFRESH == 0:
                    self.arm_sig = blend_signature(self.arm_sig, signature())
                return None
            self.trail.append((lead[0], lead[1], t))    # on the line, not far enough over it
            del self.trail[:-TRAIL_KEEP]
            self.cross_n = 0
            return None

        self.trail.append((lead[0], lead[1], t))    # far enough over the line
        del self.trail[:-TRAIL_KEEP]
        if self.cross_n == 0:
            self.cross_t0 = t
        self.cross_n += 1
        if self.cross_n < HOLD_SAMPLES or t - self.cross_t0 < HOLD_MIN_SPAN_S:
            return None
        return self._confirm(line, w, t, signature)

    @staticmethod
    def _lead(a, b, sa, sb, side):
        """The end of the footprint a-b that is nearest to (or furthest across) the line, seen from `side`: the end that crosses first."""
        return a if (sa < sb) == (side == 1) else b

    def _same_vehicle(self, new) -> bool:
        """Is `new` the next picture of the vehicle of the current run? (the general check, then the check across the line)"""
        run = [r[:5] for r in self.run]
        if not continues(run, new[:5]):
            return False
        last = self.run[-1]
        dt = new[0] - last[0]
        if dt <= 0:
            return True
        part = self.run[-4:]
        span = part[-1][0] - part[0][0]
        vs = (part[-1][5] - part[0][5]) / span if len(part) >= 2 and span > 0 else 0.0     # sideways speed (px per second)
        err = abs(new[5] - (last[5] + vs * dt))
        return err <= LAT_WIDTHS * max(last[3], new[3]) + LAT_SPEED_SHARE * abs(vs) * dt + LAT_SLACK_PX

    def _confirm(self, line, w, t, signature):
        trip = ([self.last_own] if self.last_own else []) + self.trail
        cut = line_cut([(p[0], p[1]) for p in trip], line, tol=max(4.0, CUT_TOLERANCE_WIDTHS * w))
        if cut is None:                             # it went round the end of the line (or the line bends away): never crossed
            self._forget()
            return None
        verdict = self._driving_along(trip, cut, w)
        self.last_angle = verdict["at"]             # (for the notes of the evidence and for tuning)
        self.last_check = verdict
        if not verdict["ok"]:                       # cross traffic, or a straight vehicle that only meets a skewed line: not a violation
            self._rearm_on_other_side(trip[-1])
            return None
        if signature and self.arm_sig is not None:
            colours = signature()
            if colours is not None and hist_distance(self.arm_sig, colours) > SIG_MAX_DISTANCE:
                self._forget()                      # other colours than the vehicle that was on this side: another vehicle
                return None
        self.done = True
        return Crossing(cut.point, t, verdict["at"])

    @staticmethod
    def _heading(points, w, least):
        """(ux, uy) of the way `points` ((x, y) oldest first) go, or None when they travel less than `least` box widths."""
        if len(points) < 3:
            return None
        dx, dy = points[-1][0] - points[0][0], points[-1][1] - points[0][1]
        d = math.hypot(dx, dy)
        return None if d < least * w else (dx / d, dy / d)

    @staticmethod
    def _course(points, w):
        """The straight course through `points` ((x, y) oldest first): ((ux, uy), (cx, cy)), the direction it was driven in and a point on it.
        A least-squares line, so a vehicle that weaves a little round a straight course still has that course (two end points would tilt it).
        (None, None) when the points travel less than COURSE_MIN_WIDTHS box widths."""
        pts = np.asarray(points, dtype=float)
        if len(pts) < 3 or math.hypot(*(pts[-1] - pts[0])) < COURSE_MIN_WIDTHS * w:
            return None, None
        centre = pts.mean(axis=0)
        _vals, vecs = np.linalg.eigh(np.cov((pts - centre).T))
        u = vecs[:, -1]
        if float(np.dot(u, pts[-1] - pts[0])) < 0:
            u = -u
        return (float(u[0]), float(u[1])), (float(centre[0]), float(centre[1]))

    @staticmethod
    def _angle(a, b) -> float:
        """The angle (0 to 90 deg) between two directions, whichever way each points."""
        return math.degrees(math.acos(min(1.0, abs(a[0] * b[0] + a[1] * b[1]))))

    def _driving_along(self, trip, cut, w) -> dict:
        """Did the vehicle drive ALONG the line when it went over? {"ok", "before", "at", "shift"}: the angle (deg) of its own course (seconds
        before the line) and of its heading at the line to the line, and how far (box widths) it had moved sideways from that course; None
        where it could not be told. Not ok when it was not driving at the line (it stood or crept), when it was heading across the line (at
        the line, or on the way to it), or, having a course, when it did not move sideways from it."""
        i = min(cut.index, len(trip) - 2)
        t_cut = trip[i][2] + cut.frac * (trip[i + 1][2] - trip[i][2])
        hist = self.hist
        out = {"ok": False, "before": None, "at": None, "shift": None}
        k = max((j for j, p in enumerate(hist) if p[0] <= t_cut), default=0)                      # the last picture before the cut
        h_at = self._heading([(p[1], p[2]) for p in hist[max(0, k - 1):k + 4]], w, MIN_HEADING_WIDTHS)   # the pictures around the crossing
        if h_at is None:                            # it was not driving there: standing or creeping on the line is not a crossing
            return out
        out["at"] = self._angle(h_at, cut.tangent)
        if out["at"] > MAX_CROSS_ANGLE_DEG:         # heading across the line
            return out
        course = [p for p in hist if t_cut - COURSE_FROM_S <= p[0] <= t_cut - COURSE_TO_S]
        c, centre = (None, None)
        if len(course) >= COURSE_MIN_SAMPLES and course[-1][0] - course[0][0] >= COURSE_MIN_SPAN_S:
            c, centre = self._course([(p[1], p[2]) for p in course], w)
        if c is None:                               # no course to compare with (a young run, or it crept before): its heading at the line is all there is
            out["ok"] = True
            return out
        out["before"] = self._angle(c, cut.tangent)
        out["shift"] = abs((hist[-1][1] - centre[0]) * c[1] - (hist[-1][2] - centre[1]) * c[0]) / max(w, 1.0)   # now, sideways from the straight course
        out["ok"] = out["before"] <= MAX_APPROACH_ANGLE_DEG and out["shift"] >= MIN_SHIFT_WIDTHS
        return out

    def _rearm_on_other_side(self, here) -> None:
        """The vehicle crossed, but not as a violation: from now on the side it is on is its own (so one turn is not judged on every picture)."""
        self.side = -self.side
        self.last_own, self.trail, self.cross_n, self.own_n = here, [], 0, 0
