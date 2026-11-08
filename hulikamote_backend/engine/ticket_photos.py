"""
ticket_photos.py - the photos a ticket's database row lists.

A forensic ticket keeps its evidence photos in `evidence_paths`, in step with `evidence_meta` (one entry per photo). A
photo's entry may also carry `details`: close-ups of what a specialist model looked at (the helmet crop, the cabin crop ...)
that were kept as extra evidence (engine/pipeline.py keep_detail). The Inbox, the phone app and the mailbox read the row's
`evidence_paths`, so the row lists the close-ups too: right after the first photo, whose place (the Inbox thumbnail) must not
change, so they are also the first to be sent when a ticket is too big to send whole.
"""
from pathlib import Path

DETAIL_PREFIX = "detail_"                  # file names of close-ups start like this: the apps recognise them by it


def detail_files(ticket: dict) -> list[str]:
    """File names of the ticket's close-ups, in photo order, each once."""
    names = []
    for meta in ticket.get("evidence_meta", []):
        for detail in meta.get("details") or []:
            name = Path(str(detail.get("file") or "")).name
            if name and name not in names:
                names.append(name)
    return names


def photo_names(ticket: dict) -> list[str]:
    """The photo list for the ticket's database row: evidence photos in order, the close-ups after the first one."""
    frames = [Path(str(p)).name for p in ticket.get("evidence_paths", []) if str(p).strip()]
    extra = [n for n in detail_files(ticket) if n not in frames]
    return frames[:1] + extra + frames[1:]
