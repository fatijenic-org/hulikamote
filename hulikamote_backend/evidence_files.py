"""
evidence_files.py - the photos that belong to a ticket (snapshots/evidence/) and how many bytes of them may be sent.

A ticket stores its photos as file names in `evidence_paths`. Only a bare file name is ever used, so a stored value
cannot point outside the evidence folder.
"""
import json
from pathlib import Path

EVIDENCE_DIR = Path(__file__).resolve().parent / "snapshots" / "evidence"


def frames_of(violation: dict) -> list[str]:
    """The file names of this ticket's photos that are still on disk, in the order they were taken."""
    raw = violation.get("evidence_paths") or []
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except ValueError:
            raw = []
    names = [Path(str(p)).name for p in raw if str(p).strip()]
    return [n for n in dict.fromkeys(names) if (EVIDENCE_DIR / n).is_file()]


def privacy_ok(violation: dict) -> bool:
    """False only when the ticket this row belongs to was made with the privacy blur switched OFF (its photos then show faces and other
    vehicles' plates, so they must never leave the laptop). The ticket says so in its report (`privacy_blurred`); a row whose ticket
    cannot be found is let through."""
    session = Path(str(violation.get("session_id") or "")).name
    if not session or session == "default":
        return True
    try:
        tickets = json.loads((EVIDENCE_DIR / "forensic" / session / "output" / "report.json").read_text())
    except (OSError, ValueError):
        return True
    rid = violation.get("id")
    for ticket in tickets if isinstance(tickets, list) else []:
        if isinstance(ticket, dict) and rid in (ticket.get("db_ids") or []):
            return ticket.get("privacy_blurred", True) is not False
    return True


def read_within(names: list[str], max_bytes: int) -> list[tuple[str, bytes]]:
    """(name, bytes) for as many photos as fit in `max_bytes`, in order. The rest are left out, never cut."""
    chosen, used = [], 0
    for name in names:
        data = (EVIDENCE_DIR / name).read_bytes()
        if used + len(data) > max_bytes:
            break
        chosen.append((name, data))
        used += len(data)
    return chosen
