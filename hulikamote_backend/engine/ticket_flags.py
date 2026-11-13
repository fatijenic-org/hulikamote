"""
Review flags for forensic tickets (human-in-the-loop support).

Pure functions, no I/O. A ticket carries `evidence_meta`, a list of
{"file", "bbox": [x, y, w, h], "t": video-seconds} in capture order, parallel to
its evidence frames. Flags only *suggest* a review; a human makes the call.

Flag shape: {"type", "detail", "other_uid"?, "frame_index"?}
  identity_jump      one ticket's box leaps between consecutive evidence frames
                     (the tracker probably switched to another car). frame_index is
                     the first evidence frame AFTER the jump, for a split suggestion.
  possible_duplicate another ticket looks like the same car (similar plate, or it
                     starts right where this one ended).
"""
import math
from typing import Callable

from engine.video_clock import retime

# Operator-adjustable sensitivity, 1 (strict, fewest flags) .. 7 (sensitive, most flags).
# (jump_factor, gap_s, min_iou):
#   jump_factor  centre displacement > jump_factor * previous box's longer side = identity_jump
#   gap_s        max seconds between one ticket ending and another starting
#   min_iou      min box overlap (last box of A vs first box of B) for "continues"
SENSITIVITY_LEVELS = {
    1: (1.50, 1.0, 0.60),
    2: (1.25, 1.5, 0.50),
    3: (1.00, 2.0, 0.40),
    4: (0.75, 2.5, 0.30),   # default
    5: (0.60, 3.0, 0.20),
    6: (0.50, 3.5, 0.10),
    7: (0.40, 4.0, 0.05),
}
DEFAULT_SENSITIVITY = 4
_UNIDENTIFIED = ("unidentified", "no_plate_found", "")


def _centre(bbox: list) -> tuple[float, float]:
    x, y, w, h = bbox
    return x + w / 2.0, y + h / 2.0


def _dist(a: list, b: list) -> float:
    (ax, ay), (bx, by) = _centre(a), _centre(b)
    return math.hypot(ax - bx, ay - by)


def _metas(ticket: dict) -> list[dict]:
    return [m for m in ticket.get("evidence_meta", []) if m.get("bbox")]


def _params(sensitivity) -> tuple[float, float, float]:
    try:
        level = int(sensitivity)
    except (TypeError, ValueError):
        level = DEFAULT_SENSITIVITY
    return SENSITIVITY_LEVELS[min(7, max(1, level))]


def _iou(a: list, b: list) -> float:
    ix = max(0.0, min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1]))
    inter = ix * iy
    union = a[2] * a[3] + b[2] * b[3] - inter
    return inter / union if union > 0 else 0.0


def find_identity_jumps(ticket: dict, sensitivity=DEFAULT_SENSITIVITY) -> list[dict]:
    """Flag every spot where the box teleports between consecutive evidence frames."""
    jump_factor = _params(sensitivity)[0]
    metas = _metas(ticket)
    flags = []
    for i in range(1, len(metas)):
        prev, cur = metas[i - 1], metas[i]
        limit = jump_factor * max(prev["bbox"][2], prev["bbox"][3])
        d = _dist(prev["bbox"], cur["bbox"])
        if d > limit:
            flags.append({
                "type": "identity_jump",
                "frame_index": i,
                "detail": f"Box jumped {d:.0f}px between evidence frames {i} and {i + 1} "
                          f"(limit {limit:.0f}px); the tracker may have switched cars.",
            })
    return flags


def _continues(a: dict, b: dict, gap_s: float, min_iou: float) -> bool:
    """True when ticket b starts close (in time and place) to where ticket a ended."""
    ma, mb = _metas(a), _metas(b)
    if not ma or not mb:
        return False
    last, first = ma[-1], mb[0]
    if last.get("t") is None or first.get("t") is None:
        return False
    gap = first["t"] - last["t"]
    if not 0 <= gap <= gap_s:
        return False
    return _iou(last["bbox"], first["bbox"]) >= min_iou


def find_duplicates(tickets: list[dict], distance: Callable[[str, str], int], sensitivity=DEFAULT_SENSITIVITY) -> dict[str, list[dict]]:
    """Map ticket_uid -> possible_duplicate flags against every other ticket."""
    _, gap_s, min_iou = _params(sensitivity)
    out: dict[str, list[dict]] = {t["ticket_uid"]: [] for t in tickets}
    for i, a in enumerate(tickets):
        for b in tickets[i + 1:]:
            # The operator already answered "different car" for this pair.
            if b["ticket_uid"] in a.get("not_same_as", []) or a["ticket_uid"] in b.get("not_same_as", []):
                continue
            reasons = []
            pa, pb = a.get("plate_text", ""), b.get("plate_text", "")
            if pa not in _UNIDENTIFIED and pb not in _UNIDENTIFIED and distance(pa.upper(), pb.upper()) <= 1:
                reasons.append(f"plates {pa} / {pb} are identical or differ by one character")
            if _continues(a, b, gap_s, min_iou) or _continues(b, a, gap_s, min_iou):
                reasons.append("one ticket starts on top of where the other ended")
            if not reasons:
                continue
            detail = "; ".join(reasons)
            out[a["ticket_uid"]].append({"type": "possible_duplicate", "other_uid": b["ticket_uid"], "detail": detail})
            out[b["ticket_uid"]].append({"type": "possible_duplicate", "other_uid": a["ticket_uid"], "detail": detail})
    return out


def find_time_flags(ticket: dict) -> list[dict]:
    """A ticket of a rule that only holds at certain hours, from a video whose time is not known: a human must check the time."""
    time = ticket.get("time") or {}
    if not time.get("needs_check"):
        return []
    return [{"type": "time_unconfirmed",
             "detail": f"{time.get('note') or 'The time of this video is not known.'} "
                       "This rule only holds at certain hours: check the time before confirming."}]


def annotate_tickets(tickets: list[dict], distance: Callable[[str, str], int], sensitivity=DEFAULT_SENSITIVITY) -> None:
    """Give every ticket a `ticket_uid` and a `flags` list (in place). A ticket's time follows its first photo."""
    import uuid
    for t in tickets:
        t.setdefault("ticket_uid", uuid.uuid4().hex[:12])
        retime(t)
    dupes = find_duplicates(tickets, distance, sensitivity)
    for t in tickets:
        t["flags"] = find_identity_jumps(t, sensitivity) + dupes[t["ticket_uid"]] + find_time_flags(t)
