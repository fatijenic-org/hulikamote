"""
no_helmet - a motorcycle rider without a helmet.

Heuristic: the helmet model looks at the motorcycle TOGETHER with its riders (the motorcycle box
often cuts off the heads). A look is "bad" when any rider is detected as rider_without_helmet; a
look with no rider found does not vote. The ticket is decided by a vote over recent looks
(ledger.vote: 60% of the last 10, at least 3), so one wrong frame cannot create a ticket.
The model labels the whole rider (not just the helmet), which avoids the "helmet on lap" miss.
A look that voted for the violation also keeps its crop (boxes drawn on it) as a close-up of the ticket's evidence.

Only a real motorcycle can get this ticket. The class of a vehicle flickers (a jeepney or a car is called "motorcycle" in a few frames,
and the people in it look like riders), so three guards stand before and after the vote:
  1. the track must have been a motorcycle in most of its looks (MOTOR_SHARE); a track that was mostly a car, jeepney, bus, truck, pickup
     or tricycle loses its helmet votes and the violation, even if some looks said "motorcycle";
  2. a "motorcycle" box that sits on top of another vehicle's box (same object called twice) is not looked at;
  3. when the vehicle leaves, the violation is dropped again if the first guard fails then (the last word).
"""
from engine import marks
from engine.specialists import IDX_RIDER_WITH_HELMET, IDX_RIDER_WITHOUT_HELMET
from engine.violations.base import Violation


NOT_MOTORCYCLE = ("car", "jeepney", "bus", "truck", "pickup", "tricycle")   # a helmet ticket never goes to these
MOTOR_SHARE = 0.6        # a track must have been called "motorcycle" in at least this share of its looks
MIN_CLASS_LOOKS = 3      # fewer looks than this say nothing about the class yet


def _twin_of_other_vehicle(det, others) -> bool:
    """The "motorcycle" box is another vehicle seen twice: it overlaps a car / jeepney / bus / truck / pickup / tricycle box a lot (IoU, or
    nearly inside a box that is not much bigger). A motorcycle that is merely IN FRONT of a big vehicle is far smaller, so it passes."""
    x, y, w, h = det.bbox
    area = w * h
    if area <= 0:
        return False
    for other in others:
        if other is det or getattr(other, "cls", None) not in NOT_MOTORCYCLE:
            continue
        ox, oy, ow, oh = other.bbox
        iw, ih = min(x + w, ox + ow) - max(x, ox), min(y + h, oy + oh) - max(y, oy)
        if iw <= 0 or ih <= 0:
            continue
        inter = iw * ih
        other_area = ow * oh
        if inter / (area + other_area - inter) >= 0.4 or (inter / area >= 0.85 and other_area <= 2.0 * area):
            return True
    return False


class NoHelmet(Violation):
    key = "no_helmet"
    job = "helmet"

    @staticmethod
    def is_motorcycle_track(ledger) -> bool:
        """False when most looks of this track said car / jeepney / bus ... : it is not a motorcycle, whatever a few frames said."""
        if ledger is None:
            return True
        share, looks = ledger.motorcycle_share()
        return looks < MIN_CLASS_LOOKS or share >= MOTOR_SHARE

    def decide_end(self, ledger):
        if self.key in ledger.violations and not self.is_motorcycle_track(ledger):
            ledger.violations.discard(self.key)

    def judge(self, pipe, det, look):
        ledger = pipe.ledger_manager.ledgers.get(det.track_id)
        if not self.is_motorcycle_track(ledger):                 # a car or a jeepney that was called "motorcycle" now and then
            ledger.votes.pop(self.key, None)
            ledger.violations.discard(self.key)
            return
        if _twin_of_other_vehicle(det, getattr(pipe, "_look_dets", ())):
            return
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
