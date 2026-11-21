"""
box_stabilizer.py - keep a vehicle's box on the screen when the detector misses it for a moment.

The detector (and the tracker behind it) sometimes lose a vehicle for a few pictures: its confidence dips, it is half hidden, the number
changes. The box then blinks off and on. This stabilizer follows every tracked vehicle and, when a vehicle that was followed for a few
pictures is missing, it hands back a PREDICTED box for it for a short time (the hold): the last box moved on along the way the vehicle was
going, never backwards, never faster than it went, never out of the picture. The predicted boxes are for the SCREEN only:

  - they are ghosts (GhostDetection.ghost is True), added to the list the dashboard draws, after the rules have judged the real boxes;
  - the ledgers, the models and the evidence never see them, so a ghost cannot make a ticket or a photo;
  - a ghost goes away at once when a real box covers it (the vehicle was found again, under any number) or when the hold is over.

The way it works is measured offline on saved runs (tools/box_stability.py). All times are in PICTURES (the hold in seconds is turned into
pictures with the frame rate of the source): a slow backend plays a video file slower, but the vehicle still moves the same per picture.
"""
from __future__ import annotations

from yolo_inference import YoloDetection

MIN_HITS = 8                 # a vehicle must have been seen this many times before it gets a ghost (a flicker or a passing glance never does)
EDGE_MARGIN = 0.04           # a vehicle whose predicted centre is this close (share of the picture) to an edge is leaving: no ghost
MAX_STEP = 0.35              # a ghost moves at most this share of the box size per picture
COVER_IOU = 0.35             # a real box this much over the ghost: the vehicle was found again, the ghost is dropped
DECAY = 0.92                 # the confidence of a ghost falls by this much each picture
KEEP_AFTER_HOLD = 30         # a track that is gone is forgotten this many pictures after its hold ended
SPEED_SAMPLES = 6


class GhostDetection(YoloDetection):
    """A predicted box (see the module text). It carries what the last real box carried, so it looks the same on the screen."""
    __slots__ = ("ghost", "fade")

    def __init__(self, source, bbox, confidence, fade: float = 0.8):
        super().__init__(source.cls, confidence, bbox, getattr(source, "violation_type", "") or "", source.track_id,
                         bool(getattr(source, "is_violator", False)))
        self.ghost = True
        self.fade = fade                  # how strongly the dashboard draws it (1 = like a real box): fainter the longer it stands in
        for name in ("assigned_user_id", "assigned_user_name", "plate_text", "plate_bbox"):
            try:
                setattr(self, name, getattr(source, name))
            except AttributeError:
                pass
        self.marks = []


def _iou(a, b) -> float:
    ax2, ay2, bx2, by2 = a[0] + a[2], a[1] + a[3], b[0] + b[2], b[1] + b[3]
    iw, ih = min(ax2, bx2) - max(a[0], b[0]), min(ay2, by2) - max(a[1], b[1])
    if iw <= 0 or ih <= 0:
        return 0.0
    inter = iw * ih
    return inter / (a[2] * a[3] + b[2] * b[3] - inter + 1e-9)


class _Track:
    __slots__ = ("hits", "last_frame", "samples", "bbox", "det", "ghosts", "dead")

    def __init__(self):
        self.hits = 0
        self.last_frame = -1
        self.samples: list = []        # (frame, centre x, centre y)
        self.bbox = None
        self.det = None                # the last real detection (a ghost copies its look)
        self.ghosts = 0                # pictures a ghost has been shown for since the last real box
        self.dead = False

    def velocity(self) -> tuple[float, float]:
        """Pixels per picture over the last few samples ((0, 0) when it cannot be told)."""
        part = self.samples[-SPEED_SAMPLES:]
        if len(part) < 2 or part[-1][0] <= part[0][0]:
            return 0.0, 0.0
        n = part[-1][0] - part[0][0]
        return (part[-1][1] - part[0][1]) / n, (part[-1][2] - part[0][2]) / n


class BoxStabilizer:
    def __init__(self, hold_s: float = 0.8, fps: float = 25.0, enabled: bool = True):
        self.enabled = enabled
        self.hold_s = float(hold_s)
        self.fps = float(fps) if fps and fps > 0 else 25.0
        self.tracks: dict = {}
        self.stats = {"ghost_boxes": 0, "rescued": 0, "covered": 0}

    # ── settings ──
    def set_fps(self, fps) -> None:
        try:
            if fps and float(fps) > 0:
                self.fps = float(fps)
        except (TypeError, ValueError):
            pass

    def configure(self, enabled=None, hold_s=None) -> None:
        if enabled is not None:
            self.enabled = bool(enabled)
            if not self.enabled:
                self.tracks.clear()
        if hold_s is not None:
            self.hold_s = max(0.0, min(5.0, float(hold_s)))

    @property
    def hold_frames(self) -> int:
        return max(0, round(self.hold_s * self.fps))

    def reset(self) -> None:
        self.tracks.clear()

    # ── one picture ──
    def step(self, detections, frame_idx: int, size: tuple | None = None) -> list:
        """The real boxes of this picture in, the ghosts to draw with them out (a list, usually empty). `frame_idx` counts pictures."""
        if not self.enabled or self.hold_frames <= 0:
            return []
        from engine.violations.base import VEHICLE_CLASSES
        hold = self.hold_frames
        seen = set()
        reals = []
        for det in detections:
            tid = getattr(det, "track_id", -1)
            if tid == -1 or getattr(det, "ghost", False):
                continue
            if det.cls not in VEHICLE_CLASSES:
                continue
            reals.append(det)
            seen.add(tid)
            tr = self.tracks.get(tid)
            if tr is None:
                tr = self.tracks[tid] = _Track()
            if tr.ghosts:
                self.stats["rescued"] += 1                       # it came back under its own number while a ghost stood in for it
            tr.ghosts = 0
            tr.hits += 1
            tr.last_frame = frame_idx
            tr.bbox = [float(v) for v in det.bbox]
            tr.det = det
            tr.samples.append((frame_idx, tr.bbox[0] + tr.bbox[2] / 2.0, tr.bbox[1] + tr.bbox[3] / 2.0))
            del tr.samples[:-SPEED_SAMPLES * 2]

        ghosts = []
        real_boxes = [d.bbox for d in reals]
        for tid, tr in list(self.tracks.items()):
            if tid in seen:
                continue
            missed = frame_idx - tr.last_frame
            if missed > hold + KEEP_AFTER_HOLD:
                del self.tracks[tid]
                continue
            if tr.dead or tr.hits < MIN_HITS or missed > hold or tr.det is None:
                continue
            x, y, w, h = tr.bbox
            vx, vy = tr.velocity()
            cap = MAX_STEP * max(w, h)
            speed = (vx * vx + vy * vy) ** 0.5
            if speed > cap:
                vx, vy = vx * cap / speed, vy * cap / speed          # never faster than a vehicle goes (a jump in the samples)
            box = [x + vx * missed, y + vy * missed, w, h]
            if size:
                fw, fh = size
                cx, cy = box[0] + w / 2.0, box[1] + h / 2.0
                edge = EDGE_MARGIN * min(fw, fh)
                if cx < edge or cy < edge or cx > fw - edge or cy > fh - edge:
                    tr.dead = True                                   # it is leaving the picture (or has left): nothing to hold
                    continue
            if any(_iou(box, rb) >= COVER_IOU for rb in real_boxes):
                tr.dead = True                                       # found again (maybe under another number): the real box takes over
                self.stats["covered"] += 1
                continue
            tr.ghosts += 1
            self.stats["ghost_boxes"] += 1
            fade = max(0.3, 1.0 - 0.7 * missed / (hold + 1.0))
            ghosts.append(GhostDetection(tr.det, [int(round(v)) for v in box], float(tr.det.confidence) * (DECAY ** missed), fade))
        return ghosts
