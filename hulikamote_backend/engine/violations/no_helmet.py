"""
no_helmet - a motorcycle rider without a helmet.

Heuristic: the helmet model looks at the motorcycle TOGETHER with its riders (the motorcycle box
often cuts off the heads). A look is "bad" when any rider is detected as rider_without_helmet; a
look with no rider found does not vote. The ticket is decided by a vote over recent looks
(ledger.vote: 60% of the last 10, at least 3), so one wrong frame cannot create a ticket.
The model labels the whole rider (not just the helmet), which avoids the "helmet on lap" miss.
A look that voted for the violation also keeps its crop (boxes drawn on it) as a close-up of the ticket's evidence.
"""
from engine import marks
from engine.specialists import IDX_RIDER_WITH_HELMET, IDX_RIDER_WITHOUT_HELMET
from engine.violations.base import Violation


class NoHelmet(Violation):
    key = "no_helmet"
    job = "helmet"

    def judge(self, pipe, det, look):
        riders = [d for d in look.dets if d["class_id"] in (IDX_RIDER_WITH_HELMET, IDX_RIDER_WITHOUT_HELMET)]
        if not riders:
            return
        bare = sum(1 for d in riders if d["class_id"] == IDX_RIDER_WITHOUT_HELMET)
        ledger = pipe.ledger_manager.ledgers.get(det.track_id)
        boxes = [(d["box"],      # box each rider: bare head red, helmet green
                  "NO HELMET" if d["class_id"] == IDX_RIDER_WITHOUT_HELMET else "helmet",
                  marks.RED if d["class_id"] == IDX_RIDER_WITHOUT_HELMET else marks.GREEN)
                 for d in riders]
        if ledger is not None:
            marks.set_marks(ledger, self.key, det.bbox, boxes)
        if bare:    # a look that voted for the violation: keep what the model saw as a close-up
            self.keep_detail(pipe, det, look, "helmet", "NO HELMET", boxes,
                             max(d["confidence"] for d in riders if d["class_id"] == IDX_RIDER_WITHOUT_HELMET))
        pipe.ledger_manager.vote(det.track_id, self.key, bare > 0)
