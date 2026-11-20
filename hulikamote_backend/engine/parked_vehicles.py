"""
parked_vehicles.py - the vehicles that already got an Illegal parking ticket in this run, so one parked vehicle never gets two.

A parked vehicle does not move, so "is this the vehicle that was ticketed?" is answered by WHERE it stands (and a look at its colours):
a new tracker number on the same spot, the same size, the same colours is the same vehicle. That is easier and stricter than following
the vehicle: the tracker loses a parked vehicle whenever something drives in front of it, and gives it a new number when it shows again.
Each new number would start the stopwatch again and make a second ticket.

The ledger manager keeps one registry (`ActiveLedgerManager.parked`). Illegal parking:
  remember()  a vehicle was flagged: its spot, size, class and colours are kept;
  find()      does a vehicle standing still in a zone match a remembered one? Then it is that vehicle: no stopwatch, no ticket.
A remembered vehicle is forgotten when nothing has matched its spot for GONE_AFTER_S seconds: it has left, and the next one is a new case.
Times are the ledger's own (video time or wall clock). All the work is on small numbers; nothing here reads a picture.
"""
import math
from dataclasses import dataclass

import numpy as np

from engine.track_stitcher import hist_distance

GONE_AFTER_S = 120.0       # nothing matched the spot for this long: the vehicle has left
POS_MIN_PX = 25.0          # how far the ground point may be from where it was ...
POS_BOX_SHARE = 0.6        # ... or this share of the box width, whichever is more
AREA_RATIO = (0.5, 2.0)    # new box area / remembered box area
SAME_BOX_IOU = 0.5         # the flagged vehicle is in view: only a box on top of its own box can be it again (a second ledger on one vehicle)
MAX_HIST_DISTANCE = 0.55   # colour histogram distance (0 = the same colours); a parked vehicle looks the same from the same camera


@dataclass
class ParkedVehicle:
    id: int
    ledger_id: int                      # the ledger that was flagged (it owns the ticket)
    x: float                            # where its tyres touch the road (ledger anchor)
    y: float
    w: float
    h: float
    vclass: str
    signature: np.ndarray | None
    first_t: float
    last_t: float


def _iou(a, b) -> float:
    ix = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    iy = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    if ix <= 0 or iy <= 0:
        return 0.0
    inter = ix * iy
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)


def _ground(ledger) -> tuple[float, float, float, float, float]:
    """(t, x, y, w, h) of the ledger's newest position."""
    t, x, y, box = ledger.history[-1]
    return t, x, y, float(box[2]), float(box[3])


class ParkedRegistry:
    def __init__(self):
        self.entries: list[ParkedVehicle] = []
        self._next_id = 1

    def purge(self, now: float) -> None:
        """Forget the vehicles that nothing has matched for GONE_AFTER_S."""
        if self.entries:
            self.entries = [e for e in self.entries if now - e.last_t <= GONE_AFTER_S]

    def find(self, ledger, ledgers=None) -> ParkedVehicle | None:
        """The remembered vehicle this ledger is, or None. A ledger that was flagged finds its own entry.
        `ledgers` (the manager's ledgers by number): a vehicle that was flagged and is IN VIEW now stands where it stands, so another vehicle
        close to it (the next car in a row of parked cars, the same colour) is not it; only a box on top of its box is (two ledgers on one vehicle)."""
        if not ledger.history:
            return None
        for e in self.entries:
            if e.ledger_id == ledger.track_id:
                return e
        t, x, y, w, h = _ground(ledger)
        best, best_cost = None, math.inf
        for e in self.entries:
            if abs(t - e.last_t) > GONE_AFTER_S:
                continue
            owner = (ledgers or {}).get(e.ledger_id)
            if owner is not None and owner is not ledger and owner.history and owner.missed_frames == 0:
                if _iou(owner.history[-1][3], ledger.history[-1][3]) < SAME_BOX_IOU:
                    continue
            old_class, new_class = e.vclass, ledger.vclass
            if old_class != "unknown" and new_class != "unknown" and old_class != new_class:
                continue
            dist = math.hypot(x - e.x, y - e.y)
            if dist > max(POS_MIN_PX, POS_BOX_SHARE * max(w, e.w)):
                continue
            if e.w <= 0 or e.h <= 0 or w <= 0 or h <= 0:
                continue
            ratio = (w * h) / (e.w * e.h)
            if not (AREA_RATIO[0] <= ratio <= AREA_RATIO[1]):
                continue
            colour = 0.0
            if e.signature is not None and getattr(ledger, "appearance", None) is not None:
                colour = hist_distance(e.signature, ledger.appearance)
                if colour > MAX_HIST_DISTANCE:
                    continue
            cost = dist / max(w, 1.0) + colour
            if cost < best_cost:
                best, best_cost = e, cost
        return best

    def remember(self, ledger) -> ParkedVehicle:
        """The ledger was flagged (or still is): keep, or refresh, its spot."""
        t, x, y, w, h = _ground(ledger)
        for e in self.entries:
            if e.ledger_id == ledger.track_id:
                e.x, e.y, e.w, e.h, e.last_t = x, y, w, h, t
                if e.vclass == "unknown":
                    e.vclass = ledger.vclass
                return e
        entry = ParkedVehicle(self._next_id, ledger.track_id, x, y, w, h, ledger.vclass,
                              getattr(ledger, "appearance", None), t, t)
        self._next_id += 1
        self.entries.append(entry)
        return entry

    def touch(self, entry: ParkedVehicle, ledger) -> None:
        """A vehicle stands on the remembered spot (a new number for it, or the flagged one): the vehicle is still there."""
        entry.last_t = max(entry.last_t, ledger.history[-1][0])
