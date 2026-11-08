"""
pickup_passengers - people riding in the open back of a moving pickup or truck.

Legal basis (RA 4136 Sections 32 and 51, enforced by an LTO memo of September 2019 for the cargo area of
trucks including pickups; MMDA Regulation 04-005 in Metro Manila): carrying persons outside the cabin or
at the rear of a vehicle is prohibited. Penalty figures reported in the news differ and are NOT quoted here.

Heuristic (see onboard.py): for a moving truck / pickup, a person counts as a passenger in the back when
  - they sit in the trailing 40% of the vehicle along its direction of travel (the bed; the cab is the leading part),
  - their feet are on the vehicle's body and most of them is over it (heads may stick out above the roof), and
  - they move WITH the vehicle (a pedestrian beside it or someone loading a parked pickup does not).
Judged by a vote over recent looks (60% of the last 10, at least 5), so one wrong frame cannot create a ticket.
Pickups are usually detected as "truck" by the vehicle detector; a "pickup" class is used if the detector has one.

VIEW REQUIRED: the camera must see the vehicle from the front, rear or side at a moderate height, so that the
bed and the cab are apart in the picture (an overhead view straight down cannot tell them apart).
bed_passengers_allowed (config, default 0) is how many people are tolerated (e.g. a loading helper).
"""
from engine import marks
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, heading
from engine.violations.onboard import claimed_by_motorcycles, in_trailing_body, moves_with

BODY_CLASSES = ("truck", "pickup")
MIN_SPEED_PX_S = 2 * STOP_SPEED       # "while the vehicle is in motion"


class PickupPassengers(Violation):
    key = "pickup_passengers"

    MIN_LOOKS = 5

    def check_frame(self, pipe, detections):
        mgr = pipe.ledger_manager
        people = [d for d in detections if d.cls == "person" and d.track_id != -1]
        claimed = claimed_by_motorcycles(detections, people)
        allowed = int((getattr(pipe, "config", None) or {}).get("bed_passengers_allowed", 0))
        for det in detections:
            if det.cls not in BODY_CLASSES or det.track_id == -1:
                continue
            ledger = mgr.ledgers.get(det.track_id)
            head = heading(ledger) if ledger is not None and ledger.path else None
            if head is None or ledger.get_speed() < MIN_SPEED_PX_S:
                continue                                    # not moving: nothing to judge (and no vote)
            on_board = []
            for person in people:
                person_ledger = mgr.ledgers.get(person.track_id)
                if (id(person.bbox) not in claimed and person_ledger is not None
                        and in_trailing_body(det.bbox, head, person.bbox) and moves_with(ledger, person_ledger)):
                    on_board.append(person.bbox)
            if on_board:
                marks.set_marks(ledger, self.key, det.bbox, [(b, "passenger", marks.YELLOW) for b in on_board],
                                note=f"{len(on_board)} PASSENGER(S) IN THE BACK")
            mgr.vote(det.track_id, self.key, len(on_board) > allowed, min_looks=self.MIN_LOOKS)
