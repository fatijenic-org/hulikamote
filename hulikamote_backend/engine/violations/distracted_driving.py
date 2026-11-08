"""
distracted_driving - a car driver using a phone.  (Not in the thesis violation list; kept as an extra.)

Heuristic: the cabin model looks at the car; a tinted window means no look (Safety Override Gate).
A driver_phone detection is a bad look; the ticket is a vote over recent looks (60% of the last 10,
at least 3). The phone is boxed red.
"""
from engine import marks
from engine.specialists import IDX_DRIVER_PHONE
from engine.violations import cabin
from engine.violations.base import Violation


class DistractedDriving(Violation):
    key = "distracted_driving"
    job = "cabin"

    def judge(self, pipe, det, look):
        if det.cls == "motorcycle" or not cabin.judgeable(look):
            return
        ledger = pipe.ledger_manager.ledgers.get(det.track_id)
        boxes = cabin.boxes(look, IDX_DRIVER_PHONE, "PHONE", marks.RED)
        if ledger is not None:
            marks.set_marks(ledger, self.key, det.bbox, boxes)
        phones = [d for d in look.dets if d["class_id"] == IDX_DRIVER_PHONE]
        if phones:          # a look that voted for the violation: keep the cabin picture as a close-up
            self.keep_detail(pipe, det, look, "phone", "PHONE", boxes, max(d["confidence"] for d in phones))
        pipe.ledger_manager.vote(det.track_id, self.key, bool(phones))
