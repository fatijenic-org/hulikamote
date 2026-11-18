"""
passenger_outside - people riding where a moving vehicle has no seat for them. One rule, one case per vehicle type:

  vehicle               counted as a passenger outside                                  tolerated (config, default 0)
  pickup / truck        in the open back (the bed: trailing 40% along the travel)        bed_passengers_allowed
  bus / jeepney / truck on the roof, or hanging off the side or back                     -
  kuliglig              anyone on it or its trailer except the driver (the person         kuliglig_passengers_allowed
                        farthest forward along the travel)

Replaces pickup_passengers, riding_outside_vehicle and kuliglig_passenger (2026-11-17); LEGACY_KEYS in
engine/violations/__init__.py turns those keys in old saved configs into this one.

Legal basis: RA 4136 Sections 32 and 51 (persons riding outside or at the rear of a vehicle; an LTO memo of
September 2019 applies it to the cargo area of trucks including pickups; MMDA Regulation 04-005 in Metro Manila).
Kuliglig: TO CONFIRM (farm equipment; city ordinances differ). Penalty figures are NOT quoted here.

Every case (see onboard.py) also needs: the vehicle moves, the person moves WITH it (a pedestrian beside it or someone
loading a parked one does not count), and a person already claimed by a motorcycle (or, for roof / hanging, by any small
vehicle) is never counted. Judged by a vote over recent looks (60% of the last 10, at least 5).

VIEW REQUIRED: front, rear or side view at a moderate height, the whole vehicle visible. A straight top-down view cannot
tell a bed from a cab; someone on a rear step seen from straight behind is hidden. Kuliglig needs a vehicle model with a
"kuliglig" class (none of the current models has one), so that case cannot fire yet.
"""
from engine import marks
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, heading
from engine.violations.onboard import (claimed_by_motorcycles, claimed_by_small_vehicles, in_trailing_body, moves_with,
                                       on_body, outside_position, stays_attached)

BED_CLASSES = ("truck", "pickup")
ROOF_CLASSES = ("bus", "jeepney", "truck")
KULIGLIG_CLASSES = ("kuliglig",)
MIN_SPEED_PX_S = 2 * STOP_SPEED       # "while the vehicle is in motion"


class PassengerOutside(Violation):
    key = "passenger_outside"

    MIN_LOOKS = 5
    SETTINGS = ("bed_passengers_allowed", "kuliglig_passengers_allowed")

    def settings_from_wizard(self, cfg: dict) -> dict:
        return {k: int(cfg[k]) for k in self.SETTINGS if cfg.get(k) is not None}

    def check_frame(self, pipe, detections):
        mgr = pipe.ledger_manager
        cfg = getattr(pipe, "config", None) or {}
        people = [d for d in detections if d.cls == "person" and d.track_id != -1]
        moto_claimed = claimed_by_motorcycles(detections, people)
        small_claimed = claimed_by_small_vehicles(detections, people)
        for det in detections:
            cls = det.cls
            if det.track_id == -1 or cls not in BED_CLASSES + ROOF_CLASSES + KULIGLIG_CLASSES:
                continue
            ledger = mgr.ledgers.get(det.track_id)
            head = heading(ledger) if ledger is not None and ledger.path else None
            if head is None or ledger.get_speed() < MIN_SPEED_PX_S:
                continue                                    # not moving: nothing to judge (and no vote)

            found, allowed = [], 0                          # (person box, label)
            for person in people:
                pl = mgr.ledgers.get(person.track_id)
                if pl is None or not moves_with(ledger, pl):
                    continue
                key = id(person.bbox)
                if cls in BED_CLASSES and key not in moto_claimed and in_trailing_body(det.bbox, head, person.bbox):
                    found.append((person.bbox, "passenger"))
                elif cls in ROOF_CLASSES and key not in small_claimed and stays_attached(ledger, pl):
                    where = outside_position(det.bbox, person.bbox)
                    if where:
                        found.append((person.bbox, "on roof" if where == "roof" else "hanging on"))
                elif cls in KULIGLIG_CLASSES and key not in moto_claimed and on_body(det.bbox, person.bbox):
                    found.append((person.bbox, "passenger"))

            boxes = []
            if cls in KULIGLIG_CLASSES:
                # the driver sits at the front: the person farthest along the direction of travel
                found.sort(key=lambda f: (f[0][0] + f[0][2] / 2) * head[0] + (f[0][1] + f[0][3] / 2) * head[1], reverse=True)
                if found:
                    boxes.append((found[0][0], "driver", marks.YELLOW))
                found = found[1:]
                allowed = int(cfg.get("kuliglig_passengers_allowed", 0))
            elif cls in BED_CLASSES and all(label == "passenger" for _, label in found):
                allowed = int(cfg.get("bed_passengers_allowed", 0))
            if found:
                boxes += [(b, label, marks.YELLOW) for b, label in found]
                marks.set_marks(ledger, self.key, det.bbox, boxes, note=f"{len(found)} PASSENGER(S) OUTSIDE")
            mgr.vote(det.track_id, self.key, len(found) > allowed, min_looks=self.MIN_LOOKS)
