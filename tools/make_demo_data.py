"""
make_demo_data.py - build a small, clean demo database for showing the system to an officer.

    hulikamote_backend/venv/Scripts/python.exe tools/make_demo_data.py

It writes hulikamote_backend/demo.db (git ignores it) from tickets and photos that already exist, and only READS the
real database, which is never changed. Start the backend on the demo data with tools/run_demo_backend.bat.

What the demo holds:
  - the three mock motorists (Juan, Maria, Pedro), each with the plate of a car in a real confirmed ticket, so the
    photo, the plate on the record and the owner all agree;
  - those confirmed tickets, each with its notice (what the motorist's phone shows), and one appeal;
  - a few unreviewed tickets of different violations to confirm live. Two belong to registered plates, so confirming
    them sends a notice to a motorist's phone.
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "hulikamote_backend"
sys.path.insert(0, str(BACKEND))

from demerit_points import normalize_plate  # noqa: E402  (needs the backend folder on the path)

APPROVED_WANTED = 6          # confirmed tickets to show
PENDING_WANTED = 6           # tickets left for the officer or presenter to confirm
LIVE_DEMO_OWNED = 2          # of the pending ones, how many belong to a registered plate (confirming one notifies a phone)
NOTICE_PHOTOS = 8            # photos shown per notice (a ticket can hold dozens); evenly spaced through the clip
APPEAL_REASON = "I was not the one driving the vehicle at that time."


def _clean_plate(plate: str) -> bool:
    """A plate worth showing: 6 to 8 letters and digits, both kinds (not an OCR scrap like "EJD")."""
    key = normalize_plate(plate)
    return 6 <= len(key) <= 8 and any(c.isdigit() for c in key) and any(c.isalpha() for c in key)


def _pick(rows: list[dict], wanted: int, one_per: str | None) -> list[dict]:
    """Newest first; one ticket per plate, and (when asked) one per violation type before repeating a type."""
    chosen, plates, kinds = [], set(), set()
    for round_ in (0, 1):
        for row in rows:
            plate = normalize_plate(row["plate_text"])
            if row in chosen or plate in plates:
                continue
            if round_ == 0 and one_per and row[one_per] in kinds:
                continue
            chosen.append(row)
            plates.add(plate)
            kinds.add(row.get(one_per))
            if len(chosen) == wanted:
                return chosen
    return chosen


def _real_tickets(real_db: Path, status: str, frames_of) -> list[dict]:
    con = sqlite3.connect(f"file:{real_db.as_posix()}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    try:
        rows = [dict(r) for r in con.execute("SELECT * FROM violations WHERE status = ? ORDER BY timestamp DESC", (status,))]
    finally:
        con.close()
    return [r for r in rows if _clean_plate(r["plate_text"]) and frames_of(r)]


def build(real_db: Path, out_db: Path) -> dict:
    """Make `out_db` from `real_db`. Returns what it holds."""
    import sqlalchemy

    import database
    import emailer
    import evidence_files
    from store import DEMO_PLATES, MOCK_USERS

    if out_db.resolve() == real_db.resolve():
        raise ValueError("The demo database must be a different file from the real one.")
    for leftover in (out_db, out_db.with_name(out_db.name + "-journal"), out_db.with_name(out_db.name + "-wal")):
        leftover.unlink(missing_ok=True)

    engine = sqlalchemy.create_engine(f"sqlite:///{out_db.as_posix()}")
    database.metadata.create_all(engine)
    frames_of = evidence_files.frames_of

    approved = _pick(_real_tickets(real_db, "approved", frames_of), APPROVED_WANTED, None)
    pending = _pick(_real_tickets(real_db, "pending", frames_of), PENDING_WANTED, "cls")

    motorists = [dict(u) for u in MOCK_USERS]
    owner_cycle = [m["id"] for m in motorists]
    owner_of: dict[str, str] = {}                    # plate key -> motorist id
    plates_of: dict[str, list[str]] = {m["id"]: [DEMO_PLATES[m["id"]]] if m["id"] in DEMO_PLATES else [] for m in motorists}

    def give(ticket: dict, motorist_id: str) -> None:
        key = normalize_plate(ticket["plate_text"])
        owner_of[key] = motorist_id
        plates_of[motorist_id].append(ticket["plate_text"].strip().upper())

    for i, ticket in enumerate(approved):
        give(ticket, owner_cycle[i % len(owner_cycle)])
    for i, ticket in enumerate(pending[:LIVE_DEMO_OWNED]):
        give(ticket, owner_cycle[i % len(owner_cycle)])

    columns = ("id", "cls", "confidence", "timestamp", "image_path", "status", "evidence_paths", "track_id", "source", "session_id", "plate_text")
    now = datetime.now(timezone.utc).isoformat()
    with engine.begin() as con:
        for m in motorists:
            con.execute(database.users_table.insert().values(**{**m, "email": ""}))
        for motorist_id, plates in plates_of.items():
            for plate in dict.fromkeys(plates):
                con.execute(database.vehicles_table.insert().values(plate_key=normalize_plate(plate), plate=plate, user_id=motorist_id))

        notices = appeals = 0
        last_pedro = None
        for ticket in approved + pending:
            row = {c: ticket[c] for c in columns}
            row["user_id"] = owner_of.get(normalize_plate(ticket["plate_text"]), "unregistered")
            con.execute(database.violations_table.insert().values(**row))
            if ticket in approved:
                owner = next(m for m in motorists if m["id"] == row["user_id"])
                frames = frames_of(ticket)
                frames = frames[:: max(1, -(-len(frames) // NOTICE_PHOTOS))][:NOTICE_PHOTOS]
                msg = emailer.build_message(owner, row, frames)
                body = msg.get_body(preferencelist=("plain",)).get_content()
                con.execute(database.notices_table.insert().values(
                    id=str(uuid.uuid4()), user_id=owner["id"], to_email="", subject=msg["Subject"], body=body, status="local",
                    detail="", frames=json.dumps(frames), created_at=row["timestamp"]))
                notices += 1
                if owner["id"] == "user_003":
                    last_pedro = row
        if last_pedro:
            con.execute(database.appeals_table.insert().values(
                id=str(uuid.uuid4()), violation_id=last_pedro["id"], user_id="user_003", reason=APPEAL_REASON, status="pending", created_at=now))
            appeals = 1
    engine.dispose()
    return {
        "confirmed": len(approved), "to_review": len(pending), "notices": notices, "appeals": appeals,
        "motorists": {m["name"]: plates_of[m["id"]] for m in motorists},
        "classes_to_review": sorted({t["cls"] for t in pending}),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the demo database from the real one (the real one is only read).")
    parser.add_argument("--real", type=Path, default=BACKEND / "hulikamote.db")
    parser.add_argument("--out", type=Path, default=BACKEND / "demo.db")
    args = parser.parse_args()
    if not args.real.exists():
        print(f"No database at {args.real}")
        return 1
    result = build(args.real, args.out)
    print(f"Demo data written to {args.out}")
    print(f"  {result['confirmed']} confirmed tickets with photos and notices, {result['appeals']} appeal")
    print(f"  {result['to_review']} tickets to review: {', '.join(result['classes_to_review'])}")
    for name, plates in result["motorists"].items():
        print(f"  {name}: {', '.join(plates)}")
    print("Start the backend on it with tools/run_demo_backend.bat")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
