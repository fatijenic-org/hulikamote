"""
Operator-driven ticket merge ("Same car"). Pure functions, no I/O.
"""
import re

_UNIDENTIFIED = ("unidentified", "no_plate_found", "")


def _time_key(m: dict) -> float:
    return m["t"] if m.get("t") is not None else 0.0


def _plate_score(t: dict) -> float:
    """Strength of a ticket's plate read: its best vote score, 0 when unidentified.
    A plate the reviewer typed outranks any OCR vote."""
    if t.get("plate_manual"):
        return 1e9
    if t.get("plate_text", "") in _UNIDENTIFIED:
        return -1.0
    return max((t.get("vote_tally") or {}).values(), default=0.0)


def _unique(items: list) -> list:
    return list(dict.fromkeys(items))


def merge_tickets(keep: dict, drop: dict) -> dict:
    """Return `keep` with `drop` folded in (neither input is mutated). The plate with
    the stronger vote score wins; evidence is re-ordered chronologically."""
    best = drop if _plate_score(drop) > _plate_score(keep) else keep
    out = dict(keep)

    meta = sorted(keep.get("evidence_meta", []) + drop.get("evidence_meta", []), key=_time_key)
    out["evidence_meta"] = meta
    files = [m["file"] for m in meta]
    # frames that have no meta (older reports) are appended so nothing is lost
    out["evidence_paths"] = _unique(files + keep.get("evidence_paths", []) + drop.get("evidence_paths", []))

    out["violations"] = _unique(list(keep.get("violations", [])) + list(drop.get("violations", [])))
    out["plate_crop_paths"] = _unique(best.get("plate_crop_paths", []) +
                                      [p for p in keep.get("plate_crop_paths", []) + drop.get("plate_crop_paths", [])])
    out["crop_results"] = best.get("crop_results", []) + [
        c for c in (drop if best is keep else keep).get("crop_results", [])]
    for field in ("plate_text", "plate_raw", "vote_tally", "winning_crop", "plate_length_warning"):
        if field in best:
            out[field] = best[field]
    for field in ("plate_manual", "plate_ocr"):      # a typed plate travels with its flag
        if field in best:
            out[field] = best[field]
        else:
            out.pop(field, None)

    ids = _unique(list(keep.get("merged_track_ids", [keep.get("track_id")])) +
                  list(drop.get("merged_track_ids", [drop.get("track_id")])))
    out["merged_track_ids"] = ids
    # same display convention as the forensic pre-merge: "3 & 7"; ids stay in merged_track_ids
    out["track_id"] = " & ".join(str(i) for i in ids)
    out["db_ids"] = _unique(list(keep.get("db_ids", [])) + list(drop.get("db_ids", [])))
    out["flags"] = []   # recomputed by the caller
    return out


def split_ticket(ticket: dict, files: list[str]) -> tuple[dict, dict]:
    """
    Operator "Split": move the evidence frames named in `files` to a new ticket.
    Returns (remaining, new); the inputs are not mutated. Plate crops linked to a moved
    frame (evidence_meta `crop`) move with it and each side re-votes its plate. Reports
    without those links keep the old behaviour: plate stays with `remaining`, the new
    ticket starts 'unidentified'. The caller assigns the new ticket's uid.
    """
    moving = set(files)
    meta = ticket.get("evidence_meta", [])
    paths = ticket.get("evidence_paths", [])
    all_files = {m["file"] for m in meta} | set(paths)
    if not moving or not moving <= all_files or moving >= all_files:
        raise ValueError("Split needs at least one frame to move and at least one to keep")

    def part(keep_moving: bool) -> dict:
        t = dict(ticket)
        t["evidence_meta"] = [m for m in meta if (m["file"] in moving) == keep_moving]
        t["evidence_paths"] = [p for p in paths if (p in moving) == keep_moving]
        t["flags"] = []
        return t

    remaining, new = part(False), part(True)
    for k in ("ticket_uid", "plate_crop_paths", "crop_results", "vote_tally", "winning_crop",
              "plate_raw", "plate_length_warning", "db_ids", "plate_manual", "plate_ocr"):
        new.pop(k, None)
    new["plate_text"] = "unidentified"
    new["plate_crop_paths"], new["crop_results"], new["db_ids"] = [], [], []
    new["violations"] = list(ticket.get("violations", []))
    new["track_id"] = f"{ticket.get('track_id')} (split)"

    # Plate crops follow the evidence frames they are linked to (`crop` in evidence_meta).
    moving_crops = {m["crop"] for m in meta if m["file"] in moving and m.get("crop")}
    if moving_crops:
        all_results = ticket.get("crop_results", [])
        new["crop_results"] = [c for c in all_results if c["image_raw"] in moving_crops]
        new["plate_crop_paths"] = [p for p in ticket.get("plate_crop_paths", []) if p in moving_crops]
        remaining["crop_results"] = [c for c in all_results if c["image_raw"] not in moving_crops]
        remaining["plate_crop_paths"] = [p for p in ticket.get("plate_crop_paths", []) if p not in moving_crops]
        plate_format = (ticket.get("metadata") or {}).get("plate_format", "ph_standard")
        _revote(new, plate_format)
        if not ticket.get("plate_manual"):          # a plate the reviewer typed is not re-voted
            _revote(remaining, plate_format)
    return remaining, new


def _revote(t: dict, plate_format: str) -> None:
    """Re-pick a ticket's plate from the per-crop reads it still has (same scoring as forensic Pass 2)."""
    votes, conf = {}, {}
    for c in t.get("crop_results", []):
        text = c.get("cleaned", "")
        if text in _UNIDENTIFIED or text == "OCR_NOT_INSTALLED":
            continue
        votes[text] = votes.get(text, 0) + 1
        conf[text] = max(conf.get(text, 0.0), c.get("confidence", 0.0))
    for k in ("vote_tally", "winning_crop", "plate_raw", "plate_length_warning"):
        t.pop(k, None)
    if not votes:
        t["plate_text"], t["plate_raw"] = "unidentified", "unidentified"
        return

    def score(item):
        text, n = item
        sc = n + conf[text]
        if plate_format == "uk_standard" and len(text) == 7:
            sc += 20
        elif plate_format == "ph_standard" and len(text) in (6, 7):
            sc += 20
        return sc

    best = max(votes.items(), key=score)[0]
    t["plate_text"] = best
    t["vote_tally"] = {text: round(score((text, n)), 3) for text, n in votes.items()}
    matching = [c for c in t["crop_results"] if c.get("cleaned") == best]
    top = max(matching, key=lambda c: c.get("confidence", 0.0))
    t["plate_raw"] = top.get("raw", best)
    t["winning_crop"] = top["image_raw"]
    t["crop_results"].sort(key=lambda c: 0 if c["image_raw"] == top["image_raw"] else 1)
    t["plate_crop_paths"].sort(key=lambda p: 0 if p == top["image_raw"] else 1)
    expected = 7 if plate_format in ("ph_standard", "uk_standard") else None
    t["plate_length_warning"] = expected is not None and len(best) != expected


def normalize_plate(text) -> str:
    """A plate the way the OCR writes it: capitals and digits only."""
    return re.sub(r"[^0-9A-Z]", "", str(text or "").upper())


def _length_warning(plate: str, plate_format: str) -> bool:
    expected = 7 if plate_format in ("ph_standard", "uk_standard") else None
    return expected is not None and plate not in _UNIDENTIFIED and len(plate) != expected


def apply_plate_edit(ticket: dict, plate: str, revert: bool = False, plate_format: str = "ph_standard") -> dict:
    """
    Operator plate edit. Returns a copy of `ticket` that carries the plate the reviewer typed
    (`plate_manual` = True; the system's read is kept in `plate_ocr` for undo and training).
    An empty `plate` means "no readable plate". `revert` restores the system's read.
    The per-crop OCR evidence (crop_results, vote_tally ...) is left as it was.
    """
    out = dict(ticket)
    if revert:
        if not ticket.get("plate_manual"):
            return out                               # nothing was edited
        out["plate_text"] = ticket.get("plate_ocr") or "unidentified"
        out.pop("plate_manual", None)
        out.pop("plate_ocr", None)
    else:
        new = normalize_plate(plate) or "unidentified"
        current = ticket.get("plate_text") or "unidentified"
        if not ticket.get("plate_manual"):
            if new == current:
                return out                           # typed what is already there: not an edit
            out["plate_ocr"] = current               # remember the system's read once
        out["plate_manual"] = True
        out["plate_text"] = new
    out["plate_length_warning"] = _length_warning(out["plate_text"], plate_format)
    return out


revote = _revote        # the same plate vote, under a public name for engine/plate_reread.py


def remove_frames(ticket: dict, files: list[str]) -> dict:
    """
    Operator "Remove photos": drop the evidence frames named in `files` from the ticket, with the plate crops that
    were read from them, and re-vote the plate (a plate the reviewer typed is not re-voted). The removed frames are
    kept in `removed_frames` for the record; their files stay on disk. The input is not mutated.
    """
    gone = set(files)
    meta = ticket.get("evidence_meta", [])
    paths = ticket.get("evidence_paths", [])
    all_files = {m["file"] for m in meta} | set(paths)
    if not gone or not gone <= all_files or gone >= all_files:
        raise ValueError("Remove needs at least one photo to remove and at least one to keep")

    out = dict(ticket)
    out["evidence_meta"] = [m for m in meta if m["file"] not in gone]
    out["evidence_paths"] = [p for p in paths if p not in gone]
    out["removed_frames"] = list(ticket.get("removed_frames", [])) + [m for m in meta if m["file"] in gone]
    out["flags"] = []
    gone_crops = {m["crop"] for m in meta if m["file"] in gone and m.get("crop")}
    if gone_crops:
        out["crop_results"] = [c for c in ticket.get("crop_results", []) if c["image_raw"] not in gone_crops]
        out["plate_crop_paths"] = [p for p in ticket.get("plate_crop_paths", []) if p not in gone_crops]
        if not ticket.get("plate_manual"):
            revote(out, (ticket.get("metadata") or {}).get("plate_format", "ph_standard"))
    return out
