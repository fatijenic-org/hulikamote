"""
riding_outside_vehicle - people on the roof of, or hanging off, a moving bus / jeepney / truck.

Legal basis: the same RA 4136 Sections 32 and 51 as pickup_passengers (persons riding outside or at the
rear of a vehicle). Penalty figures are NOT quoted here.

Heuristic (see onboard.py): for a moving bus / jeepney / truck, a person counts when they
  - stand on the roof (feet in the top 30% of the vehicle, head at or above its roof line), or
  - hang off the side or back (straddle the left or right edge, a quarter to three quarters of them over the
    body, feet in the lower 60%), and
  - move WITH the vehicle (pedestrians beside it and people boarding a stopped bus do not count), and
  - keep the same spot on it (offset drifts under 15% of its size: a motorcycle passing alongside slides along it).
Never counted: motorcycle / tricycle riders, people sitting in a car or tricycle, and occupants wholly inside the
vehicle's box (the driver behind the windshield, seated passengers).
Judged by a vote over recent looks (60% of the last 10, at least 5).

VIEW REQUIRED: the camera must see the whole side or the rear of the vehicle at a moderate height. A person
hanging on the rear step of a vehicle seen from straight behind is hidden by the vehicle and cannot be seen.
"""
from engine import marks
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, heading
from engine.violations.onboard import claimed_by_small_vehicles, moves_with, outside_position, stays_attached

BODY_CLASSES = ("bus", "jeepney", "truck")
MIN_SPEED_PX_S = 2 * STOP_SPEED


class RidingOutside(Violation):
    key = "riding_outside_vehicle"

    MIN_LOOKS = 5

    def check_frame(self, pipe, detections):
        mgr = pipe.ledger_manager
        people = [d for d in detections if d.cls == "person" and d.track_id != -1]
        claimed = claimed_by_small_vehicles(detections, people)
        for det in detections:
            if det.cls not in BODY_CLASSES or det.track_id == -1:
                continue
            ledger = mgr.ledgers.get(det.track_id)
            if ledger is None or not ledger.path or heading(ledger) is None or ledger.get_speed() < MIN_SPEED_PX_S:
                continue
            found = []
            for person in people:
                person_ledger = mgr.ledgers.get(person.track_id)
                where = outside_position(det.bbox, person.bbox)
                if (where and id(person.bbox) not in claimed and person_ledger is not None
                        and moves_with(ledger, person_ledger) and stays_attached(ledger, person_ledger)):
                    found.append((person.bbox, "on roof" if where == "roof" else "hanging on"))
            if found:
                marks.set_marks(ledger, self.key, det.bbox, [(b, label, marks.YELLOW) for b, label in found],
                                note=f"{len(found)} RIDING OUTSIDE")
            mgr.vote(det.track_id, self.key, bool(found), min_looks=self.MIN_LOOKS)
