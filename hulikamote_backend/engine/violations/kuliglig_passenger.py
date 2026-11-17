"""
kuliglig_passenger - a moving kuliglig (a hand tractor that pulls a trailer) carries people other than its driver.

Legal basis: TO CONFIRM. A kuliglig is farm equipment, not a registered passenger vehicle; city ordinances differ
(Manila bans them on main roads). The project's rule list asks for: any person on a kuliglig, the driver excepted.

Heuristic (see onboard.py): for a moving kuliglig, a person counts as on board when
  - their feet are on the vehicle's box and at least half of them is over it, and
  - they move WITH it (a pedestrian beside it or someone loading a parked one does not).
One person on board is the driver (the one nearest the front along the direction of travel); every other one is a
passenger. Judged by a vote over recent looks (60% of the last 10, at least 5).

NEEDS a vehicle model with a "kuliglig" class. The stock COCO model and the trained models up to train-4 have none,
so this rule cannot fire until such a model is trained (see docs/final_documents/TASKS_T1_T8_NEXT_STEPS.md).
kuliglig_passengers_allowed (config, default 0) is how many passengers are tolerated.
"""
from engine import marks
from engine.violations.base import Violation
from engine.violations.geometry import STOP_SPEED, heading
from engine.violations.onboard import claimed_by_motorcycles, moves_with, on_body

KULIGLIG_CLASSES = ("kuliglig",)
MIN_SPEED_PX_S = 2 * STOP_SPEED       # "while the vehicle is in motion"


class KuligligPassenger(Violation):
    key = "kuliglig_passenger"

    MIN_LOOKS = 5

    def check_frame(self, pipe, detections):
        mgr = pipe.ledger_manager
        people = [d for d in detections if d.cls == "person" and d.track_id != -1]
        claimed = claimed_by_motorcycles(detections, people)
        allowed = int((getattr(pipe, "config", None) or {}).get("kuliglig_passengers_allowed", 0))
        for det in detections:
            if det.cls not in KULIGLIG_CLASSES or det.track_id == -1:
                continue
            ledger = mgr.ledgers.get(det.track_id)
            head = heading(ledger) if ledger is not None and ledger.path else None
            if head is None or ledger.get_speed() < MIN_SPEED_PX_S:
                continue                                    # not moving: nothing to judge (and no vote)
            on_board = []
            for person in people:
                person_ledger = mgr.ledgers.get(person.track_id)
                if (id(person.bbox) not in claimed and person_ledger is not None
                        and on_body(det.bbox, person.bbox) and moves_with(ledger, person_ledger)):
                    on_board.append(person.bbox)
            # the driver sits at the front: the person farthest along the direction of travel
            on_board.sort(key=lambda b: (b[0] + b[2] / 2) * head[0] + (b[1] + b[3] / 2) * head[1], reverse=True)
            passengers = on_board[1:]
            if passengers:
                marks.set_marks(ledger, self.key, det.bbox,
                                [(on_board[0], "driver", marks.YELLOW)] + [(b, "passenger", marks.YELLOW) for b in passengers],
                                note=f"{len(passengers)} PASSENGER(S) ON A KULIGLIG")
            mgr.vote(det.track_id, self.key, len(passengers) > allowed, min_looks=self.MIN_LOOKS)
