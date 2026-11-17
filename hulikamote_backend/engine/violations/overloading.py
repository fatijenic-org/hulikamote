"""
overloading - more people on a motorcycle than allowed (default 2: the driver and one passenger).

Heuristic: two counts, the larger one is used.
  1. Person boxes: riders are the person boxes whose feet are inside the motorcycle's width and around its
     lower body, with at least 30% of the person over the motorcycle (geometry.rider_boxes). Riders who sit close
     together overlap, and the vehicle detector then returns ONE person box for two or three people.
  2. Rider boxes of the helmet model (the "helmet" look, specialist_jobs.HelmetJob): that model was trained to box
     every rider of one motorcycle, with or without a helmet, so it separates riders the vehicle detector merges.
     Only boxes that sit on this motorcycle count (centre inside its width, not below it), duplicates are removed,
     and a count is used for 1 s (the model looks at a motorcycle about twice a second).
The count is judged by a vote - more than the maximum in at least 60% of the last 10 looks, minimum 5 looks - so
a pedestrian walking past or one wrong frame cannot create a ticket.
"""
import os

from engine import marks
from engine.specialists import IDX_RIDER_WITH_HELMET, IDX_RIDER_WITHOUT_HELMET
from engine.violations.base import Violation
from engine.violations.geometry import rider_boxes

DEFAULT_MAX_RIDERS = 2
RIDER_BOX_CONF = 0.35       # a helmet-model rider box counts as a rider from this confidence (its look is taken at 0.25)
RIDER_BOX_FRESH_S = 1.0     # how long a helmet-model count stays valid
# Set HK_RIDERS_FROM_HELMET=0 before starting the backend to count from person boxes only (the "before" of a benchmark).
USE_HELMET_BOXES = os.environ.get("HK_RIDERS_FROM_HELMET", "1") != "0"
SAME_RIDER_IOU = 0.5        # two rider boxes that overlap this much are one rider (with-helmet and without-helmet both fired)


def _iou(a: list, b: list) -> float:
    ix = max(0.0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))
    union = a[2] * a[3] + b[2] * b[3] - ix * iy
    return ix * iy / union if union > 0 else 0.0


def riders_from_look(moto_bbox: list, dets: list, min_conf: float = RIDER_BOX_CONF) -> list:
    """The helmet model's rider boxes that belong to this motorcycle, one per rider (boxes [x, y, w, h] in frame pixels)."""
    mx, my, mw, mh = moto_bbox
    kept: list = []
    for d in sorted(dets, key=lambda d: -d["confidence"]):
        if d["class_id"] not in (IDX_RIDER_WITH_HELMET, IDX_RIDER_WITHOUT_HELMET) or d["confidence"] < min_conf:
            continue
        x, y, w, h = d["box"]
        cx, cy = x + w / 2, y + h / 2
        if not (mx - 0.1 * mw <= cx <= mx + 1.1 * mw and my - 1.5 * mh <= cy <= my + mh):
            continue                                  # a neighbour's rider that happens to be in the crop
        if all(_iou(d["box"], k) < SAME_RIDER_IOU for k in kept):
            kept.append(d["box"])
    return kept


class Overloading(Violation):
    key = "overloading"
    job = "helmet"              # optional: with no helmet model loaded there is no look and only person boxes are counted

    MIN_LOOKS = 5

    def settings_from_wizard(self, cfg):
        return {"max_riders": int(cfg.get("max_riders", DEFAULT_MAX_RIDERS))}

    def vote_count(self, mgr, track_id: int, rider_count: int, max_riders: int = DEFAULT_MAX_RIDERS) -> bool:
        """More than max_riders in at least 60% of the last 10 looks (minimum 5)."""
        return mgr.vote(track_id, self.key, rider_count > max_riders, min_looks=self.MIN_LOOKS)

    def judge(self, pipe, det, look):
        """Remember the riders the helmet model boxed on this motorcycle; check_frame uses the count while it is fresh."""
        if not USE_HELMET_BOXES:
            return
        ledger = pipe.ledger_manager.ledgers.get(det.track_id)
        if ledger is not None and ledger.path:
            ledger.rider_boxes_seen = (ledger.path[-1][0], riders_from_look(det.bbox, look.dets))

    def check_frame(self, pipe, detections):
        people = [d.bbox for d in detections if d.cls == "person"]
        for det in detections:
            if det.cls != "motorcycle" or det.track_id == -1:
                continue
            riders = rider_boxes(det.bbox, people)
            ledger = pipe.ledger_manager.ledgers.get(det.track_id)
            seen = getattr(ledger, "rider_boxes_seen", None) if ledger is not None else None
            if seen is not None and ledger.path and ledger.path[-1][0] - seen[0] <= RIDER_BOX_FRESH_S and len(seen[1]) > len(riders):
                riders = seen[1]                      # the helmet model separated riders the person boxes merged
            if ledger is not None and len(riders) > pipe.max_riders:
                marks.set_marks(ledger, self.key, det.bbox,
                                [(b, f"rider {i + 1}", marks.YELLOW) for i, b in enumerate(riders)],
                                note=f"{len(riders)} RIDERS (max {pipe.max_riders})")
            self.vote_count(pipe.ledger_manager, det.track_id, len(riders), pipe.max_riders)
