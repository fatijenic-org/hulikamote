"""
missing_side_mirror - a motorcycle with fewer than two side mirrors (LTO AO AHS-2008-015).

Heuristic: the cabin model counts mirrors on the motorcycle, but ONLY when the camera sees its
front or rear (it moves mostly up or down the image): from the side one mirror is always hidden.
Fewer than 2 mirrors is a bad look; the ticket needs 80% of at least 5 looks.
NOTE: the cabin model has no motorcycle-mirror training data yet, so this cannot work until
mirror photos are labelled (see HANDOVER).
"""
from engine import marks
from engine.specialists import IDX_SIDE_MIRROR
from engine.violations import cabin
from engine.violations.base import Violation
from engine.violations.geometry import front_or_rear_view


class MissingSideMirror(Violation):
    key = "missing_side_mirror"
    job = "cabin"

    MIN_LOOKS = 5
    SHARE = 0.8

    def judge(self, pipe, det, look):
        ledger = pipe.ledger_manager.ledgers.get(det.track_id)
        if det.cls != "motorcycle" or ledger is None or not front_or_rear_view(ledger):
            return
        found = [d for d in look.dets if d["class_id"] == IDX_SIDE_MIRROR]
        mirrors = len(found)
        boxes = cabin.boxes(look, IDX_SIDE_MIRROR, "mirror", marks.GREEN)
        marks.set_marks(ledger, self.key, det.bbox, boxes, note=f"{mirrors}/2 MIRRORS")
        if mirrors < 2:     # a look that voted for the violation: keep the picture as a close-up
            self.keep_detail(pipe, det, look, "mirror", f"{mirrors}/2 MIRRORS", boxes,
                             sum(d["confidence"] for d in found) / mirrors if mirrors else 0.5, note=f"{mirrors}/2 MIRRORS")
        pipe.ledger_manager.vote(det.track_id, self.key, mirrors < 2, min_looks=self.MIN_LOOKS, share=self.SHARE)
