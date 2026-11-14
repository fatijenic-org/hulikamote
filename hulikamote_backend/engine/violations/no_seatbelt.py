"""
no_seatbelt - a car driver without a seatbelt.

Heuristic: the cabin model looks at the vehicle, but only cars and trucks are judged (no ticket for
buses, jeepneys, tricycles or motorcycles). A tinted window, or no clear window seen, means no look at all (Safety Override Gate).
With a clear window, "no seatbelt seen" is a bad look. The ticket needs 80% of at least 4 looks,
so a model miss on one frame cannot create a ticket. The windshield is boxed red unless a seatbelt is seen.
"""
from engine import marks
from engine.specialists import IDX_CLEAR_WINDOW, IDX_SEATBELT
from engine.violations import cabin
from engine.violations.base import Violation


class NoSeatbelt(Violation):
    key = "no_seatbelt"
    job = "cabin"

    MIN_LOOKS = 4
    SHARE = 0.8
    JUDGED_CLASSES = ("car", "truck")       # only these: no ticket for a bus, jeepney, tricycle or motorcycle driver

    def judge(self, pipe, det, look):
        if det.cls not in self.JUDGED_CLASSES or not cabin.judgeable(look):
            return
        belted = any(d["class_id"] == IDX_SEATBELT for d in look.dets)
        ledger = pipe.ledger_manager.ledgers.get(det.track_id)
        boxes = (cabin.boxes(look, IDX_SEATBELT, "seatbelt", marks.GREEN) if belted
                 else cabin.boxes(look, IDX_CLEAR_WINDOW, "NO SEATBELT", marks.RED))
        if ledger is not None:
            marks.set_marks(ledger, self.key, det.bbox, boxes)
        if not belted:      # a look that voted for the violation: keep the cabin picture as a close-up
            self.keep_detail(pipe, det, look, "seatbelt", "NO SEATBELT", boxes,
                             max(d["confidence"] for d in look.dets if d["class_id"] == IDX_CLEAR_WINDOW))
        pipe.ledger_manager.vote(det.track_id, self.key, not belted, min_looks=self.MIN_LOOKS, share=self.SHARE)
