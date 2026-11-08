"""
demerit_points.py - the demerit point counter: how many confirmed violations each plate has.

The proposal defines the counter as "accumulated violation counts per vehicle plate number", so one
approved (human-confirmed) ticket is one point. Pending and rejected tickets never count, and the total is
worked out from the tickets every time it is asked, so rejecting or re-reviewing a ticket fixes it by itself.
"""
from engine.ticket_merge import normalize_plate as _letters_and_digits

UNREAD_PLATES = {"", "UNIDENTIFIED", "NO_PLATE_FOUND", "SCANNING"}     # no plate was read, so nobody to charge


def normalize_plate(text) -> str:
    """'abc 1234' and 'ABC-1234' are the same plate. Returns '' when no plate was read."""
    raw = str(text or "").strip().upper()
    return "" if raw in UNREAD_PLATES else _letters_and_digits(raw)


def _empty(plate: str) -> dict:
    return {"plate": plate, "points": 0, "by_class": {}, "last_at": None}


def tally(rows: list[dict]) -> list[dict]:
    """rows: approved tickets (id, plate_text, cls, timestamp). One entry per plate, most points first."""
    plates: dict[str, dict] = {}
    for row in sorted(rows, key=lambda r: r["timestamp"]):         # oldest first, so the newest spelling wins
        key = normalize_plate(row.get("plate_text"))
        if not key:
            continue
        entry = plates.setdefault(key, _empty(key))
        entry["plate"] = str(row["plate_text"]).strip().upper()
        entry["points"] += 1
        entry["by_class"][row["cls"]] = entry["by_class"].get(row["cls"], 0) + 1
        entry["last_at"] = row["timestamp"]
    recent_first = sorted(plates.values(), key=lambda p: p["last_at"], reverse=True)
    return sorted(recent_first, key=lambda p: -p["points"])         # stable: ties stay most recent first


def for_plate(rows: list[dict], plate: str) -> dict:
    """The counter of one plate plus its tickets, newest first. An unknown plate has 0 points."""
    key = normalize_plate(plate)
    mine = [r for r in rows if key and normalize_plate(r.get("plate_text")) == key]
    found = tally(mine)
    result = found[0] if found else _empty(str(plate).strip().upper())
    result["violations"] = [{"id": r["id"], "cls": r["cls"], "timestamp": r["timestamp"]}
                            for r in sorted(mine, key=lambda r: r["timestamp"], reverse=True)]
    return result
