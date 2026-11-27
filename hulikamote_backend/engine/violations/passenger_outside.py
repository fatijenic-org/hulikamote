"""
passenger_outside - people riding where a moving vehicle has no seat for them. One rule, one case per vehicle type:

  vehicle                               counted as a passenger outside                       tolerated (config, default 0)
  pickup / truck                        in the open back (the bed: trailing 40% along the    bed_passengers_allowed
                                        travel)
  bus / jeepney / truck / pickup /      on the roof, hanging off the side, or standing on    -
  car / tricycle                        the back step (the feet at the bottom edge)
  kuliglig                              anyone on it or its trailer except the driver (the   kuliglig_passengers_allowed
                                        person farthest forward along the travel)
  (every class but the motorcycle: a motorcycle's riders are judged by the helmet and overloading rules)

Replaces pickup_passengers, riding_outside_vehicle and kuliglig_passenger (2026-11-17); LEGACY_KEYS in
engine/violations/__init__.py turns those keys in old saved configs into this one.

Legal basis: RA 4136 Sections 32 and 51 (persons riding outside or at the rear of a vehicle; an LTO memo of
September 2019 applies it to the cargo area of trucks including pickups; MMDA Regulation 04-005 in Metro Manila).
Kuliglig: TO CONFIRM (farm equipment; city ordinances differ). Penalty figures are NOT quoted here.

Every case (see onboard.py) also needs: the vehicle moves, the person keeps the SAME PLACE ON the vehicle (a pedestrian beside
it or someone loading a parked one does not count), and a person already claimed by a motorcycle (or, for roof / hanging, by any
small vehicle) is never counted. Judged over time: 6 looks with a passenger outside within 4 seconds.

Why it works on people the detector is unsure of (2026-11-19): a person on a roof or a step scores 0.10-0.25 and often gets no stable
person track number (or none at all), so the rule uses EVERY person box of a look (tracked or not) and checks the place on the vehicle
over the last 1.6 s (onboard.attached_here) instead of the person's own track. A fast "person" carried by a bus / jeepney / truck is no
longer turned into a "motorcycle" by the ledger (engine/ledger.py carried_by), which used to remove exactly these people from the rule.

VIEW REQUIRED: front, rear or side view at a moderate height, the whole vehicle visible. A straight top-down view cannot
tell a bed from a cab; someone on a rear step seen from straight behind is hidden. Kuliglig needs a vehicle model with a
"kuliglig" class (none of the current models has one), so that case cannot fire yet.
"""
from engine import marks
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, heading
from engine.violations.onboard import (attached_here, claimed_by_motorcycles, claimed_by_small_vehicles, count_hit, in_trailing_body,
                                       on_body, outside_position, place_on, reasonable_box, remember_places, remember_riders,
                                       was_rider_here)

BED_CLASSES = ("truck", "pickup")
ROOF_CLASSES = ("bus", "jeepney", "truck", "pickup", "car", "tricycle")      # roof, side or back step (every class but the motorcycle)
NO_ROOF_CLASSES = ("car", "tricycle")   # nobody rides on a car's or a tricycle's roof: a head over its roof line is the rider of the bike behind it
OUTSIDE_LABELS = {"roof": "on roof or back", "hanging": "hanging on", "rear": "on back step"}
KULIGLIG_CLASSES = ("kuliglig",)
MIN_SPEED_PX_S = 2 * STOP_SPEED       # "while the vehicle is in motion"


class PassengerOutside(Violation):
    key = "passenger_outside"

    SETTINGS = ("bed_passengers_allowed", "kuliglig_passengers_allowed")

    def settings_from_wizard(self, cfg: dict) -> dict:
        return {k: int(cfg[k]) for k in self.SETTINGS if cfg.get(k) is not None}

    def check_frame(self, pipe, detections):
        mgr = pipe.ledger_manager
        cfg = getattr(pipe, "config", None) or {}
        everybody = [d for d in detections if d.cls == "person"]       # tracked or not: a weak person on a vehicle has no stable number
        people = [d for d in everybody if not getattr(d, "on_bike", False)]    # one the people search saw on a bike is a rider
        riders = [d for d in everybody if getattr(d, "on_bike", False)]
        moto_claimed = claimed_by_motorcycles(detections, people)
        small_claimed = claimed_by_small_vehicles(detections, people)
        for det in detections:
            cls = det.cls
            if det.track_id == -1 or cls not in BED_CLASSES + ROOF_CLASSES + KULIGLIG_CLASSES:
                continue
            ledger = mgr.ledgers.get(det.track_id)
            head = heading(ledger) if ledger is not None and ledger.path else None
            if head is None or ledger.get_speed() < MIN_SPEED_PX_S:
                continue                                    # not moving: nothing to judge (and nothing remembered)

            t = ledger.history[-1][0]
            memory = ledger.onboard
            remember_riders(memory, t, det.bbox, [place_on(det.bbox, r.bbox) for r in riders])
            found = []                                      # (person box, label)
            for person in people:
                key = id(person.bbox)
                if not reasonable_box(det.bbox, person.bbox) or was_rider_here(memory, t, place_on(det.bbox, person.bbox)):
                    continue                                # not a box a passenger has, or a rider that was just seen on its bike
                if cls in BED_CLASSES and key not in moto_claimed and in_trailing_body(det.bbox, head, person.bbox):
                    found.append((person.bbox, "passenger"))
                elif cls in ROOF_CLASSES and key not in small_claimed:
                    where = outside_position(det.bbox, person.bbox, head, roof=cls not in NO_ROOF_CLASSES)
                    if where:
                        found.append((person.bbox, OUTSIDE_LABELS[where]))
                elif cls in KULIGLIG_CLASSES and key not in moto_claimed and on_body(det.bbox, person.bbox):
                    found.append((person.bbox, "passenger"))

            boxes, allowed = [], 0
            if cls in KULIGLIG_CLASSES:
                # the driver sits at the front: the person farthest along the direction of travel
                found.sort(key=lambda f: (f[0][0] + f[0][2] / 2) * head[0] + (f[0][1] + f[0][3] / 2) * head[1], reverse=True)
                if found:
                    boxes.append((found[0][0], "driver", marks.YELLOW))
                found = found[1:]
                allowed = int(cfg.get("kuliglig_passengers_allowed", 0))

            # Only those who keep the same place on the vehicle count: a pedestrian or a rider passing by is left behind.
            places = [place_on(det.bbox, box) for box, _ in found]
            counted = [f for f, place in zip(found, places) if attached_here(memory, t, det.bbox, place)]
            remember_places(memory, t, det.bbox, places)

            if cls in BED_CLASSES and counted and all(label == "passenger" for _, label in counted):
                allowed = int(cfg.get("bed_passengers_allowed", 0))
            if counted:
                boxes += [(b, label, marks.YELLOW) for b, label in counted]
                marks.set_marks(ledger, self.key, det.bbox, boxes, note=f"{len(counted)} PASSENGER(S) OUTSIDE")
            if count_hit(memory, t, len(counted) > allowed):
                ledger.violations.add(self.key)
