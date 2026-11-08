"""
overloading - more people on a motorcycle than allowed (default 2: the driver and one passenger).

Heuristic: riders are the person boxes whose feet are inside the motorcycle's width and around its
lower body, with at least 30% of the person over the motorcycle (geometry.rider_boxes). The count is
judged by a vote - more than the maximum in at least 60% of the last 10 looks, minimum 5 looks - so
a pedestrian walking past or one wrong frame cannot create a ticket.
"""
from engine import marks
from engine.violations.base import Violation
from engine.violations.geometry import rider_boxes

DEFAULT_MAX_RIDERS = 2


class Overloading(Violation):
    key = "overloading"

    MIN_LOOKS = 5

    def settings_from_wizard(self, cfg):
        return {"max_riders": int(cfg.get("max_riders", DEFAULT_MAX_RIDERS))}

    def vote_count(self, mgr, track_id: int, rider_count: int, max_riders: int = DEFAULT_MAX_RIDERS) -> bool:
        """More than max_riders in at least 60% of the last 10 looks (minimum 5)."""
        return mgr.vote(track_id, self.key, rider_count > max_riders, min_looks=self.MIN_LOOKS)

    def check_frame(self, pipe, detections):
        people = [d.bbox for d in detections if d.cls == "person"]
        for det in detections:
            if det.cls != "motorcycle" or det.track_id == -1:
                continue
            riders = rider_boxes(det.bbox, people)
            ledger = pipe.ledger_manager.ledgers.get(det.track_id)
            if ledger is not None and len(riders) > pipe.max_riders:
                marks.set_marks(ledger, self.key, det.bbox,
                                [(b, f"rider {i + 1}", marks.YELLOW) for i, b in enumerate(riders)],
                                note=f"{len(riders)} RIDERS (max {pipe.max_riders})")
            self.vote_count(pipe.ledger_manager, det.track_id, len(riders), pipe.max_riders)
