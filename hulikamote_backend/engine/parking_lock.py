"""
parking_lock.py - the aid script of Illegal parking: lock on to a vehicle that stands still, keep the time it has been there, and give
that time (and the ticket) back to the SAME vehicle when the tracker loses it and finds it again.

Two problems of the plain rule ("slower than 25 pixels a second for N seconds"):

1. Moving vehicles were flagged. Pixels are not a speed: a car far down the road drives at full speed and moves only a few pixels a
   second, so it looked "stopped". Here a vehicle is STILL only when it stays inside a small circle that is a share of ITS OWN size
   (is_still), and it is LOCKED to the spot where it stood: from then on it counts only while it stays within a (slightly larger) circle
   around that spot. A vehicle that drives, crawls in a queue or drifts away leaves the circle, the lock is let go, and its time is gone.
2. The tracker loses a parked vehicle whenever something drives in front of it, and gives it a new number when it shows again. A new
   number started a new stopwatch and made a second ticket. Here the lock belongs to the SPOT, not to the number: a new number that stands
   on a free lock (same place, size, kind and colours) takes the lock over and carries on with the same time; a lock that already made
   its ticket gives the new number no second one.

A lock: where (ground point of the box), how big, what kind, its colours, since when (the time it came to rest, found by walking back
along the vehicle's path), when it was last seen, and whether it already made a ticket. Times are the ledger's own (video time or wall
clock). Nothing here reads a picture, and nothing here knows about the violation rule: it answers "since when has this vehicle stood
here, and is it the one that was ticketed?". Pure Python on small numbers.
"""
import math
from dataclasses import dataclass

import numpy as np

from engine.track_stitcher import hist_distance

STILL_WINDOW_S = 1.5         # a vehicle is read as still over its last 1.5 s of pictures ...
STILL_MIN_SAMPLES = 4        # ... of at least 4 pictures (more of the past are taken when the pictures come slowly) ...
STILL_MAX_SPAN_S = 6.0       # ... that cover at most this much time
STILL_MIN_SPAN_S = 1.0       # ... and at least this much
STILL_TOL_SHARE = 0.15       # still = every picture within this share of the box width from the middle of the window ...
STILL_TOL_MIN_PX = 3.0       # ... or this many pixels (a tiny far box)
LOCK_RADIUS_SHARE = 0.2      # a locked vehicle stays locked while its ground point is within this share of the box width of the spot ...
LOCK_RADIUS_MIN_PX = 6.0     # ... or this many pixels
SIZE_RATIO = (0.6, 1.7)      # its box area against the lock's
MAX_HIST_DISTANCE = 0.55     # its colours against the lock's (0 = the same colours)
SAME_BOX_IOU = 0.5           # the owner of a lock is in view: only a box on top of its box is the same vehicle (a second ledger on it)
GONE_PENDING_S = 40.0        # a lock nobody has stood on for this long is let go (the vehicle left) ...
GONE_TICKETED_S = 120.0      # ... a lock that made a ticket is kept longer, so the vehicle that comes back under a new number is known
GHOST_AFTER_S = 0.3          # the locked box is drawn on its own when nothing has stood on the spot for this long (the detector dropped it) ...
GHOST_MAX_S = 25.0           # ... and for at most this long (the ledger of a lost stopped vehicle is closed after the same time)


@dataclass
class Lock:
    id: int
    ledger_id: int                      # the ledger that owns it (the one whose ticket it is)
    x: float                            # the spot: where the tyres touch the road
    y: float
    w: float
    h: float
    vclass: str
    signature: np.ndarray | None
    since: float                        # when the vehicle came to rest here
    last_t: float                       # when a vehicle was last seen on the spot
    ticketed: bool = False
    limit: float = 0.0                  # the zone's time limit, for the stopwatch chip of the locked box


def _iou(a, b) -> float:
    ix = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    iy = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    if ix <= 0 or iy <= 0:
        return 0.0
    inter = ix * iy
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)


def _radius(width: float) -> float:
    return max(LOCK_RADIUS_MIN_PX, LOCK_RADIUS_SHARE * width)


def still_run(ledger) -> tuple[float, float, float, float] | None:
    """(x, y, width, since) of a vehicle that stands still, or None when it does not. Judged on the ledger's own path (t, x, y, width),
    in the vehicle's own size: it stands still when its last pictures all lie within STILL_TOL_SHARE of its width from their middle.
    `since` is when it came to rest: back along the path for as long as it stayed within the lock radius of that middle."""
    path = list(ledger.path)
    if len(path) < STILL_MIN_SAMPLES:
        return None
    t_now = path[-1][0]
    recent = [p for p in path if t_now - p[0] <= STILL_WINDOW_S]
    if len(recent) < STILL_MIN_SAMPLES:                       # pictures come slowly: take the last few, as long as they are close in time
        recent = [p for p in path[-STILL_MIN_SAMPLES:] if t_now - p[0] <= STILL_MAX_SPAN_S]
    if len(recent) < STILL_MIN_SAMPLES or recent[-1][0] - recent[0][0] < STILL_MIN_SPAN_S:
        return None
    xs, ys, ws = sorted(p[1] for p in recent), sorted(p[2] for p in recent), sorted(p[3] for p in recent)
    mx, my, width = xs[len(xs) // 2], ys[len(ys) // 2], ws[len(ws) // 2]
    if width <= 0:
        return None
    tol = max(STILL_TOL_MIN_PX, STILL_TOL_SHARE * width)
    if max(math.hypot(p[1] - mx, p[2] - my) for p in recent) > tol:
        return None
    radius, since = _radius(width), recent[0][0]
    for p in reversed(path):                                   # how long has it been here?
        if math.hypot(p[1] - mx, p[2] - my) > radius:
            break
        since = p[0]
    return mx, my, width, since


def is_still(ledger) -> bool:
    return still_run(ledger) is not None


class ParkingLocks:
    """The locks of one run (`ActiveLedgerManager.locks`)."""

    def __init__(self):
        self.locks: list[Lock] = []
        self._next_id = 1

    # ── housekeeping ──
    def purge(self, now: float) -> None:
        self.locks = [k for k in self.locks if now - k.last_t <= (GONE_TICKETED_S if k.ticketed else GONE_PENDING_S)]

    def ghosts(self, ledgers: dict, now: float) -> list[tuple]:
        """[(lock, owner ledger)] of the locks whose vehicle the detector has dropped for now: the owner is still known (the tracker may find
        it again) but nothing stands on the spot. The dashboard keeps drawing the locked box for them, so the box does not blink away."""
        out = []
        for k in self.locks:
            owner = ledgers.get(k.ledger_id)
            if owner is None or not owner.history or owner.missed_frames < 1:
                continue
            if GHOST_AFTER_S <= now - k.last_t <= GHOST_MAX_S:
                out.append((k, owner))
        return out

    def release(self, ledger) -> None:
        """The ledger moved (or left the zone): the locks it owns are let go. Its ticket, if it got one, stays with the ledger."""
        if self.locks:
            self.locks = [k for k in self.locks if k.ledger_id != ledger.track_id]

    # ── the lock ──
    @staticmethod
    def _fits(k: Lock, x: float, y: float, w: float, h: float, vclass: str, signature) -> bool:
        """Is a vehicle with this ground point, size, class and colours the one the lock holds?"""
        if math.hypot(x - k.x, y - k.y) > _radius(max(w, k.w)):
            return False
        if k.vclass != "unknown" and vclass != "unknown" and k.vclass != vclass:
            return False
        if k.w <= 0 or k.h <= 0 or w <= 0 or h <= 0:
            return False
        if not (SIZE_RATIO[0] <= (w * h) / (k.w * k.h) <= SIZE_RATIO[1]):
            return False
        if k.signature is not None and signature is not None and hist_distance(k.signature, signature) > MAX_HIST_DISTANCE:
            return False
        return True

    def hold(self, ledger, ledgers: dict, still: tuple) -> Lock:
        """Lock `ledger`, which stands still ('still' = still_run(ledger)), on its spot, and return the lock.
        - its own lock, if it still fits (the vehicle has not moved off the spot);
        - else a lock that nobody is standing on now and that fits (the tracker lost the vehicle and found it again under a new number):
          an open lock is taken over (the time goes on), a ticketed lock stays with the ticketed ledger (the caller gives no second ticket);
        - else a new lock, from the time it came to rest.
        The caller compares `lock.ledger_id` with the ledger's number: different = this is the vehicle that was ticketed already."""
        _t, _x, _y, box = ledger.history[-1]
        x, y, width, since = still
        h = float(box[3])
        signature = getattr(ledger, "appearance", None)
        vclass = ledger.vclass
        t = ledger.history[-1][0]

        moved = False
        for k in self.locks:                                   # its own lock
            if k.ledger_id == ledger.track_id:
                if self._fits(k, _x, _y, float(box[2]), h, vclass, signature):
                    k.last_t = max(k.last_t, t)
                    return k
                self.locks.remove(k)                           # it stands somewhere else now (or is not the same vehicle): start again,
                moved = True                                   # and its time starts again too: the time it spent on the old spot is not its time here
                break

        best, best_cost = None, math.inf
        for k in self.locks:                                   # a lock whose vehicle was lost
            if abs(t - k.last_t) > (GONE_TICKETED_S if k.ticketed else GONE_PENDING_S):
                continue
            owner = ledgers.get(k.ledger_id)
            if owner is not None and owner is not ledger and owner.history and owner.missed_frames == 0:
                if _iou(owner.history[-1][3], box) < SAME_BOX_IOU:
                    continue                                   # its vehicle is in view somewhere else: this is another vehicle
            if not self._fits(k, _x, _y, float(box[2]), h, vclass, signature):
                continue
            cost = math.hypot(_x - k.x, _y - k.y) / max(width, 1.0)
            if cost < best_cost:
                best, best_cost = k, cost
        if best is not None:
            best.last_t = max(best.last_t, t)
            if not best.ticketed:
                best.ledger_id = ledger.track_id               # the same vehicle under a new number: the lock and its time are its own now
            return best

        lock = Lock(self._next_id, ledger.track_id, x, y, float(box[2]), h, vclass, signature, t if moved else since, t,
                    ticketed="illegal_parking" in ledger.violations)
        self._next_id += 1
        self.locks.append(lock)
        return lock
