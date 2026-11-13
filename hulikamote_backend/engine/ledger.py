import time
import math
from pathlib import Path
from collections import deque, Counter
import numpy as np

from engine.track_stitcher import (
    APPEARANCE_EVERY_N,
    blend_signature,
    compute_signature,
    match_births,
)
from engine.violations import ALL as ALL_VIOLATIONS


def inside_any(box, boxes, share: float = 0.4) -> bool:
    """True when at least `share` of `box` (x, y, w, h) lies inside one of `boxes`."""
    x, y, w, h = box
    area = max(1.0, w * h)
    for bx, by, bw, bh in boxes:
        ix, iy = min(x + w, bx + bw) - max(x, bx), min(y + h, by + bh) - max(y, by)
        if ix > 0 and iy > 0 and ix * iy / area >= share:
            return True
    return False


class TrackLedger:
    # Cap on saved evidence frames per violation — bounds disk usage while still
    # giving reviewers a multi-second timeline instead of a single frame.
    MAX_EVIDENCE_FRAMES = 9999
    # Close-ups of what a specialist model looked at (the helmet crop, the cabin crop ...), kept per kind
    # as extra evidence: only the most confident few of the looks that voted for a violation.
    DETAIL_CAP = 3
    DETAIL_MIN_GAP_S = 1.0
    # A "person" that moves too fast to walk is a rider the detector saw without the bike (see check_rider).
    RIDER_SPEED = 2.0      # body heights per second over the last second (walking ~0.8, running ~1.7, a motorbike >2.5)
    RIDER_SECONDS = 0.8    # it must stay that fast this long

    def __init__(self, track_id: int):
        self.track_id = track_id
        # deque is O(1) append/pop vs O(n) for list.pop(0)
        self.history: deque = deque(maxlen=30)  # (timestamp, cx, cy, bbox)
        self.violations: set = set()
        self.snapshot_bbox: list | None = None  # best bbox for evidence crop
        self.plate_text: str = "unidentified"   # filled by Plate Specialist via EasyOCR
        self.plate_bbox: list | None = None     # [x, y, w, h] of the plate crop, global coords
        self.plate_crops: list = []             # Stores numpy arrays of plate crops for Pass 2 OCR
        self.stationary_start_time: float | None = None  # Tracks when the vehicle stopped moving
        # Longer path (~10 s at 30 fps) for turn / swerve rules: (timestamp, cx, cy, box_width)
        self.path: deque = deque(maxlen=300)
        # Per-rule state, keyed by (rule, zone index) so rules never share timers
        self.stop_timers: dict = {}       # key -> time it stopped inside the zone
        self.turn_entry: dict = {}        # key -> (x, y) where it entered the zone
        self.turn_heading: dict = {}      # key -> heading just after entering
        self.line_side: dict = {}         # key -> +1/-1 side of the line it came from, or "crossed"
        self.made_stop: set = set()       # keys of stop-sign zones where it came to a full stop
        self.votes: dict = {}             # violation -> deque of recent True/False looks (see vote)
        self.marks: dict = {}             # violation -> boxes showing why (see engine/marks.py)
        self.timers: dict = {}            # violation -> stopwatch drawn on the vehicle's box (see engine/marks.py set_timer)
        self.rides: bool = False          # a "person" that moves like a vehicle: judged as a motorcycle from now on
        self._fast_since: float | None = None
        self.blink: deque = deque(maxlen=200)   # (t, left amber, right amber) indicator samples
        self.turns_judged: set = set()    # signal-light zones where this vehicle's turn was already judged
        self.plate_checks: int = 0                        # plate looks that counted (see violations/no_plate.py)
        self.plate_hits: int = 0                          # ...and how many of them found a plate
        # Looks like a violation so far, decided only when the vehicle leaves (e.g. no_plate)
        self.pending: set = set()
        self._classes_history: deque = deque(maxlen=100) # History of class predictions to prevent flickering

        # Frame-by-frame proof timeline. Only populated once this track is
        # actually flagged, and only while it stays inside the monitored ROI —
        # never for the vehicle's entire on-screen appearance.
        self.evidence_paths: list[str] = []
        # Parallel to evidence_paths: {"file", "bbox": [x,y,w,h], "t"} for review flags
        self.evidence_meta: list[dict] = []
        # Close-ups waiting to be tied to an evidence photo when the vehicle leaves:
        # {"kind", "violation", "label", "confidence", "t", "path" (as save_snapshot returned it), "file"}
        self.detail_crops: list[dict] = []

        self.missed_frames: int = 0

        # Track stitching: colour signature + raw tracker IDs merged into this ledger
        self.appearance: np.ndarray | None = None
        self._appearance_updates: int = 0
        self.merged_ids: set[int] = set()

    @property
    def vclass(self) -> str:
        """Return the most common vehicle class over the track's lifetime (Temporal Consensus)."""
        if self.rides:
            return "motorcycle"
        if not self._classes_history:
            return "unknown"
            
        # Require at least 5 frames before making a judgement
        if len(self._classes_history) < 5:
            return "unknown"
            
        top_class, count = Counter(self._classes_history).most_common(1)[0]
        
        # Require >50% consensus confidence, otherwise it's too noisy
        if count / len(self._classes_history) < 0.5:
            return "unknown"
            
        return top_class

    @property
    def latest_class(self) -> str:
        """The class of the newest detection (vclass needs 5 looks to settle; this is known at once)."""
        if self.rides:
            return "motorcycle"
        return self._classes_history[-1] if self._classes_history else "unknown"

    def add_evidence_frame(self, path: str, bbox: list | None = None, t: float | None = None,
                           car_crop: str | None = None) -> None:
        """Append a captured proof frame path, bounded by MAX_EVIDENCE_FRAMES."""
        if len(self.evidence_paths) < self.MAX_EVIDENCE_FRAMES:
            self.evidence_paths.append(path)
            self.evidence_meta.append({
                "file": Path(path).name,
                "bbox": [int(v) for v in bbox] if bbox else None,
                "t": t,
                "car_crop": car_crop,   # clean (no overlays) vehicle crop, used for ReID training data
            })

    def accepts_detail(self, kind: str, violation: str, confidence: float, t: float | None) -> bool:
        """True when a close-up of this kind is worth saving now: there is room, or it beats the weakest kept one;
        and not within DETAIL_MIN_GAP_S of the last one (so the kept ones are spread over time)."""
        kept = [d for d in self.detail_crops if d["kind"] == kind and d["violation"] == violation]
        if t is not None and any(d["t"] is not None and abs(t - d["t"]) < self.DETAIL_MIN_GAP_S for d in kept):
            return False
        return len(kept) < self.DETAIL_CAP or confidence > min(d["confidence"] for d in kept)

    def add_detail(self, entry: dict) -> list[dict]:
        """Remember a saved close-up. Returns the entries pushed out by the DETAIL_CAP (their files may be deleted)."""
        self.detail_crops.append(entry)
        same = [d for d in self.detail_crops if d["kind"] == entry["kind"] and d["violation"] == entry["violation"]]
        if len(same) <= self.DETAIL_CAP:
            return []
        weakest = min(same, key=lambda d: d["confidence"])
        self.detail_crops.remove(weakest)
        return [weakest]

    def update_position(self, bbox: list[int], timestamp: float | None = None) -> None:
        """Update the ledger with the new position of the tracked vehicle."""
        x, y, w, h = bbox
        cx = x + w / 2
        cy = y + h  # Track the bottom-center (where tires touch the pavement) to perfectly align with 2D drawn ROIs
        
        # Use provided video timestamp, or fallback to real-time for live cameras
        t = timestamp if timestamp is not None else time.time()
        self.history.append((t, cx, cy, bbox))
        self.path.append((t, cx, cy, w))
        self.snapshot_bbox = bbox  # always keep the most recent bbox
        self.missed_frames = 0

    def update_appearance(self, frame: np.ndarray, bbox: list[int]) -> None:
        """Refresh the colour signature every APPEARANCE_EVERY_N updates (cheap)."""
        self._appearance_updates += 1
        if self.appearance is not None and self._appearance_updates % APPEARANCE_EVERY_N != 0:
            return
        self.appearance = blend_signature(self.appearance, compute_signature(frame, bbox))

    def check_rider(self, covered: bool) -> None:
        """A "person" track that keeps moving faster than a person can is a rider (the detector saw the rider, not the bike):
        from then on it is a motorcycle. Speed is counted in body heights per second so it does not depend on the camera.
        `covered`: the box sits inside a vehicle's box (a passenger, or a rider already inside a bike box): never changed."""
        if self.rides or covered or len(self.history) < 4:
            return
        last = self.history[-1]
        window = [h for h in self.history if last[0] - h[0] <= 1.0]
        dt = last[0] - window[0][0]
        if len(window) < 4 or dt < 0.4:
            return
        heights = sorted(h[3][3] for h in window)
        height = max(1.0, heights[len(heights) // 2])
        ratio = math.hypot(last[1] - window[0][1], last[2] - window[0][2]) / dt / height
        if ratio < self.RIDER_SPEED:
            self._fast_since = None
        elif self._fast_since is None:
            self._fast_since = last[0]
        elif last[0] - self._fast_since >= self.RIDER_SECONDS:
            self.rides = True

    def get_movement_vector(self) -> tuple[float, float]:
        """Returns the displacement vector over the available history."""
        if len(self.history) < 4:
            return (0.0, 0.0)
        first = self.history[0]
        last = self.history[-1]
        return (last[1] - first[1], last[2] - first[2])

    def get_speed(self) -> float:
        """Calculate speed in pixels per second."""
        if len(self.history) < 4:
            return 0.0
        first = self.history[0]
        last = self.history[-1]
        dt = last[0] - first[0]
        if dt <= 0:
            return 0.0
        return math.hypot(last[1] - first[1], last[2] - first[2]) / dt


class ActiveLedgerManager:
    """
    Manages all active vehicle ledgers and evaluates violations.

    Because store.add_violation() is async and _finalize_ticket() is called
    from a sync context, completed tickets are pushed into `pending_tickets`.
    The async stream loop must drain this queue each frame via drain_tickets().
    """

    def __init__(self):
        self.ledgers: dict[int, TrackLedger] = {}
        # Sync-safe queue: filled by _finalize_ticket, drained by async caller
        self.pending_tickets: list[dict] = []
        # Track stitching: raw tracker ID -> canonical ledger ID
        self.aliases: dict[int, int] = {}
        # Lifecycle log (birth / stitched / death) for diagnosing ID switches
        self.track_events: deque = deque(maxlen=2000)

    def _log_event(self, event: str, timestamp: float | None, **fields) -> None:
        record = {"event": event, "t": timestamp, **fields}
        self.track_events.append(record)
        detail = " ".join(f"{k}={v}" for k, v in fields.items())
        print(f"[TrackEvent] {event} t={timestamp if timestamp is None else round(timestamp, 2)} {detail}")

    def update(self, detections: list, timestamp: float | None = None, frame: np.ndarray | None = None) -> None:
        """
        Update ledger positions, stitch fragmented tracker IDs, and reap stale tracks.

        Each detection's `track_id` is rewritten to its canonical ledger ID, so every
        downstream consumer (violation checks, evidence, annotation, tickets) sees one
        stable ID per vehicle even if the tracker re-issued a new one.
        """
        now = timestamp if timestamp is not None else time.time()
        assigned: list[tuple] = []   # (det, canonical_id)
        present: set[int] = set()    # canonical IDs seen this frame
        pending: list[tuple] = []    # (det, raw_id) with no ledger of their own

        # Pass 1: tracks that already own a ledger (the original IDs claim first)
        for det in detections:
            raw = getattr(det, "track_id", -1)
            if raw == -1:
                continue
            if raw in self.ledgers:
                assigned.append((det, raw))
                present.add(raw)
            else:
                pending.append((det, raw))

        # Pass 2: previously stitched aliases, then genuinely new tracks
        births: list[tuple] = []
        for det, raw in pending:
            canon = self.aliases.get(raw)
            if canon is not None and canon in self.ledgers and canon not in present:
                assigned.append((det, canon))
                present.add(canon)
                continue
            if canon is not None:
                # Target ledger is gone, or the original track came back this frame
                self.aliases.pop(raw, None)
                self._log_event("alias_dropped", now, raw=raw, was=canon)
            births.append((det, raw))

        # Pass 3: try to stitch each newborn onto a ledger that just went missing
        if births:
            sigs = {
                raw: (compute_signature(frame, det.bbox) if frame is not None else None)
                for det, raw in births
            }
            candidates = [
                (cid, led) for cid, led in self.ledgers.items()
                if cid not in present and led.missed_frames >= 1
            ]
            matches = (
                match_births([(raw, det, sigs[raw]) for det, raw in births], candidates, now)
                if candidates else {}
            )
            for det, raw in births:
                cid = matches.get(raw)
                if cid is not None:
                    self.aliases[raw] = cid
                    self.ledgers[cid].merged_ids.add(raw)
                    assigned.append((det, cid))
                    present.add(cid)
                    self._log_event("stitched", now, raw=raw, into=cid,
                                    gap_frames=self.ledgers[cid].missed_frames, bbox=list(det.bbox))
                else:
                    ledger = TrackLedger(raw)
                    ledger.appearance = sigs[raw]
                    self.ledgers[raw] = ledger
                    assigned.append((det, raw))
                    present.add(raw)
                    self._log_event("birth", now, id=raw, bbox=list(det.bbox), cls=getattr(det, "cls", None))

        others = [d.bbox for d in detections if getattr(d, "cls", "person") != "person"]   # boxes a person could sit inside
        for det, cid in assigned:
            det.track_id = cid
            ledger = self.ledgers[cid]
            cls_val = getattr(det, "cls", "unknown")
            if ledger.rides and cls_val == "person":      # moves like a vehicle: it is a motorcycle (see TrackLedger.check_rider)
                det.cls = cls_val = "motorcycle"
            if cls_val != "unknown":
                ledger._classes_history.append(cls_val)
            ledger.update_position(det.bbox, timestamp)
            if cls_val == "person":
                ledger.check_rider(inside_any(det.bbox, others))
                if ledger.rides:
                    det.cls = "motorcycle"
                    ledger._classes_history.append("motorcycle")
            if frame is not None:
                ledger.update_appearance(frame, det.bbox)

        # Finalize vehicles that left the frame after max_age missed frames (sync with the tracker's max_age)
        for tid in list(self.ledgers.keys()):
            if tid not in present:
                self.ledgers[tid].missed_frames += 1
                if self.ledgers[tid].missed_frames > 60:
                    last = self.ledgers[tid].snapshot_bbox
                    self._log_event("death", now, id=tid, last_bbox=last,
                                    violations=sorted(self.ledgers[tid].violations),
                                    merged=sorted(self.ledgers[tid].merged_ids))
                    self._finalize_ticket(tid)
                    del self.ledgers[tid]
                    self.aliases = {r: c for r, c in self.aliases.items() if c != tid}

    def drain_tickets(self) -> list[dict]:
        """
        Pop and return all pending tickets accumulated since the last drain.
        Call this from the async WebSocket loop to persist to DB.
        """
        if not self.pending_tickets:
            return []
        tickets = self.pending_tickets.copy()
        self.pending_tickets.clear()
        return tickets

    def vote(self, track_id: int, violation: str, bad: bool, min_looks: int = 3, share: float = 0.6) -> bool:
        """
        Temporal vote for checks that look at single frames (overloading, helmet,
        seatbelt, mirrors): flag when `bad` was seen in at least `share` of the
        last 10 looks (and at least `min_looks` looks), so one wrong frame or one
        wrong model guess cannot create a ticket on its own.
        """
        if track_id not in self.ledgers:
            return False
        ledger = self.ledgers[track_id]
        votes = ledger.votes.setdefault(violation, deque(maxlen=10))
        votes.append(bool(bad))
        if len(votes) >= min_looks and sum(votes) >= math.ceil(share * len(votes)):
            ledger.violations.add(violation)
            return True
        return False

    def decide_end_of_track(self, ledger: "TrackLedger") -> None:
        """
        Final decisions when a vehicle leaves (or the video ends). Pending suspicions become
        violations only if they held to the end. Evidence photos taken only because of a
        suspicion that was cleared (e.g. a plate was found later) are deleted.
        """
        for violation in ALL_VIOLATIONS:     # e.g. a pending no_plate becomes a violation if it held to the end
            violation.decide_end(ledger)
        ledger.pending.clear()
        self._settle_details(ledger)
        if not ledger.violations and ledger.evidence_paths:
            for path, meta in zip(ledger.evidence_paths, ledger.evidence_meta):
                # the annotated photo, the vehicle crop and the clean harvest crop
                for f in (Path(path), *(Path(path).parent / (meta.get(k) or "") for k in ("car_crop", "clean"))):
                    if f.is_file():
                        f.unlink(missing_ok=True)
            ledger.evidence_paths, ledger.evidence_meta = [], []

    @staticmethod
    def _settle_details(ledger: "TrackLedger") -> None:
        """Tie each close-up of a violation the vehicle really got to the evidence photo nearest in time (it becomes
        part of that photo's entry, so it moves with it when tickets are merged or split). Close-ups of a violation
        that did not hold, or with no photo to belong to, are deleted."""
        details, ledger.detail_crops = ledger.detail_crops, []
        for d in details:
            if d["violation"] in ledger.violations and ledger.evidence_meta:
                timed = [m for m in ledger.evidence_meta if m.get("t") is not None]
                target = (min(timed, key=lambda m: abs(m["t"] - d["t"])) if timed and d.get("t") is not None
                          else ledger.evidence_meta[-1])
                target.setdefault("details", []).append(
                    {k: d[k] for k in ("kind", "violation", "label", "confidence", "file")})
            else:
                Path(d["path"]).unlink(missing_ok=True)

    def finalize_all(self) -> None:
        """End of a video: decide and queue every vehicle still on screen."""
        for tid in list(self.ledgers):
            self._finalize_ticket(tid)
            del self.ledgers[tid]

    # ─── Internal ────────────────────────────────────────────────────────────

    def _finalize_ticket(self, track_id: int) -> None:
        """
        Called when a tracked vehicle leaves the frame.
        Queues a ticket dict into pending_tickets so the async caller
        can persist it to the database via store.add_violation().
        Does NOT call async code directly — this method is sync.
        """
        ledger = self.ledgers[track_id]
        self.decide_end_of_track(ledger)
        if not ledger.violations:
            return

        ticket = {
            "track_id": track_id,
            "merged_track_ids": sorted(ledger.merged_ids),
            "violations": list(ledger.violations),
            "snapshot_bbox": ledger.snapshot_bbox,
            "plate_bbox": ledger.plate_bbox,
            "plate_text": ledger.plate_text,
            "plate_crops": ledger.plate_crops,
            "evidence_paths": ledger.evidence_paths,
            "evidence_meta": ledger.evidence_meta,
        }
        self.pending_tickets.append(ticket)
        print(
            f"[Ledger] Queued ticket — Track {track_id} | "
            f"Violations: {ledger.violations}"
        )
