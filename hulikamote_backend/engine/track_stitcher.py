"""
Track stitching: glue fragmented tracker IDs back onto one vehicle identity.

DeepSORT occasionally drops a vehicle (occlusion, detector flicker, angle change)
and then re-acquires it under a brand-new ID, which produces duplicate ledger
entries and duplicate tickets for the same car. This module decides whether a
newly born track is really a continuation of a track that was just lost.

It is tracker-agnostic and does NOT touch the locked DeepSORT hyperparameters.
All functions are pure (no shared state) so they are easy to unit test.

A newborn track is stitched onto a lost ledger only if ALL gates pass:
  1. Time      - lost for at most MAX_GAP_SECONDS.
  2. Class     - same vehicle class (when both are known).
  3. Space     - appears near where the lost vehicle should be now, extrapolating
                 its recent velocity (gate scales with the vehicle's box size).
  4. Size      - bounding-box area within AREA_RATIO_RANGE of the last box.
  5. Direction - if the lost vehicle was moving, the jump must not go backwards.
  6. Colour    - HSV histogram distance <= MAX_HIST_DISTANCE (when available).
Among passing pairs the lowest-cost pair wins, one-to-one.
"""
from __future__ import annotations

import math

import numpy as np

# ── Tunables ────────────────────────────────────────────────────────────────
MAX_GAP_SECONDS = 3.0        # longest a vehicle may be lost and still be re-linked
MIN_GATE_PX = 40.0           # minimum spatial gate (pixels)
GATE_BOX_FACTOR = 1.2        # spatial gate = factor * max(box w, h) of last box
AREA_RATIO_RANGE = (0.4, 2.5)  # new box area / last box area
MIN_MOVING_SPEED = 20.0      # px/s: below this the vehicle counts as stationary
MIN_DIRECTION_STEP = 15.0    # px: ignore direction check for tiny jumps
MAX_HIST_DISTANCE = 0.5      # Bhattacharyya distance (0 = identical colours)
APPEARANCE_EVERY_N = 5       # refresh a ledger's colour signature every N updates
APPEARANCE_EMA = 0.3         # weight of the newest signature in the running mean
_VELOCITY_SAMPLES = 8        # history samples used to estimate velocity


def compute_signature(frame: np.ndarray, bbox) -> np.ndarray | None:
    """HSV colour histogram (H x S, L1-normalised) of the vehicle crop, or None."""
    import cv2

    x, y, w, h = (int(v) for v in bbox)
    fh, fw = frame.shape[:2]
    x1, y1 = max(0, x), max(0, y)
    x2, y2 = min(fw, x + w), min(fh, y + h)
    if x2 - x1 < 8 or y2 - y1 < 8:
        return None
    crop = cv2.resize(frame[y1:y2, x1:x2], (32, 32), interpolation=cv2.INTER_AREA)
    hsv = cv2.cvtColor(crop, cv2.COLOR_BGR2HSV)
    hist = cv2.calcHist([hsv], [0, 1], None, [16, 8], [0, 180, 0, 256])
    cv2.normalize(hist, hist, alpha=1.0, norm_type=cv2.NORM_L1)
    return hist.astype(np.float32)


def hist_distance(a: np.ndarray, b: np.ndarray) -> float:
    import cv2

    return float(cv2.compareHist(a, b, cv2.HISTCMP_BHATTACHARYYA))


def blend_signature(old: np.ndarray | None, new: np.ndarray | None) -> np.ndarray | None:
    """Running mean of colour signatures so one bad frame can't poison the ledger."""
    if new is None:
        return old
    if old is None:
        return new
    mixed = (1.0 - APPEARANCE_EMA) * old + APPEARANCE_EMA * new
    return (mixed / max(float(mixed.sum()), 1e-9)).astype(np.float32)


def _kinematics(history) -> tuple[float, float, float, float, float]:
    """(t, x, y, vx, vy) at the last sample; velocity in px/s over recent samples."""
    samples = list(history)[-_VELOCITY_SAMPLES:]
    t1, x1, y1, _ = samples[-1]
    if len(samples) < 2:
        return t1, x1, y1, 0.0, 0.0
    t0, x0, y0, _ = samples[0]
    dt = t1 - t0
    if dt <= 0:
        return t1, x1, y1, 0.0, 0.0
    return t1, x1, y1, (x1 - x0) / dt, (y1 - y0) / dt


def score_candidate(birth_bbox, birth_cls: str | None, birth_sig, ledger, now: float) -> float | None:
    """Return a match cost (lower = better) or None if any gate rejects the pair."""
    if not ledger.history:
        return None

    t_last, lx, ly, vx, vy = _kinematics(ledger.history)
    gap = now - t_last
    if gap <= 0 or gap > MAX_GAP_SECONDS:
        return None

    # Class gate
    old_cls = ledger.vclass
    if old_cls != "unknown" and birth_cls not in (None, "unknown") and old_cls != birth_cls:
        return None
    # A person is never a vehicle, even while the class has not settled yet (it needs 5 looks): a rider's short-lived
    # record must not swallow its motorcycle's new track (or the other way round).
    if birth_cls not in (None, "unknown") and             ("person" in (old_cls, getattr(ledger, "latest_class", "unknown"))) != (birth_cls == "person"):
        return None

    bx, by, bw, bh = birth_bbox
    nx, ny = bx + bw / 2.0, by + bh  # bottom-center, same anchor as the ledger
    _, _, lw, lh = ledger.history[-1][3]
    if lw <= 0 or lh <= 0 or bw <= 0 or bh <= 0:
        return None

    # Size gate
    ratio = (bw * bh) / (lw * lh)
    if not (AREA_RATIO_RANGE[0] <= ratio <= AREA_RATIO_RANGE[1]):
        return None

    # Spatial gate: compare against where the lost vehicle should be by now
    px, py = lx + vx * gap, ly + vy * gap
    dist = math.hypot(nx - px, ny - py)
    gate = max(MIN_GATE_PX, GATE_BOX_FACTOR * max(lw, lh))
    if dist > gate:
        return None

    # Direction gate: a moving vehicle can't reappear behind where it vanished
    speed = math.hypot(vx, vy)
    sx, sy = nx - lx, ny - ly
    step = math.hypot(sx, sy)
    if speed >= MIN_MOVING_SPEED and step >= MIN_DIRECTION_STEP:
        if (vx * sx + vy * sy) / (speed * step) < 0:
            return None

    # Colour gate
    hd = 0.0
    if birth_sig is not None and getattr(ledger, "appearance", None) is not None:
        hd = hist_distance(ledger.appearance, birth_sig)
        if hd > MAX_HIST_DISTANCE:
            return None

    return dist / gate + hd + 0.1 * abs(math.log(ratio))


def match_births(births, candidates, now: float) -> dict[int, int]:
    """
    Greedy one-to-one assignment of newborn tracks to lost ledgers.

    births:     [(raw_track_id, det, signature_or_None), ...]
    candidates: [(canonical_id, ledger), ...]   (ledgers currently missing)
    Returns {raw_track_id: canonical_id} for every accepted stitch.
    """
    pairs = []
    for raw, det, sig in births:
        for cid, ledger in candidates:
            cost = score_candidate(det.bbox, getattr(det, "cls", None), sig, ledger, now)
            if cost is not None:
                pairs.append((cost, raw, cid))
    pairs.sort(key=lambda p: p[0])

    used_births: set[int] = set()
    used_candidates: set[int] = set()
    result: dict[int, int] = {}
    for _, raw, cid in pairs:
        if raw in used_births or cid in used_candidates:
            continue
        result[raw] = cid
        used_births.add(raw)
        used_candidates.add(cid)
    return result
