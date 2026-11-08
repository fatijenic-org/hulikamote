"""
database.py - Async SQLite connection and table setup.
"""
import os
from pathlib import Path

import databases
import sqlalchemy

# HK_DB=demo.db starts the backend on the demo data (tools/make_demo_data.py) instead of the real database.
DB_FILE = Path(os.environ.get("HK_DB") or "hulikamote.db").as_posix()
DATABASE_URL = f"sqlite+aiosqlite:///{DB_FILE}"

database = databases.Database(DATABASE_URL)

metadata = sqlalchemy.MetaData()

users_table = sqlalchemy.Table(
    "users",
    metadata,
    sqlalchemy.Column("id", sqlalchemy.String, primary_key=True),
    sqlalchemy.Column("name", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("license_no", sqlalchemy.String, nullable=False, unique=True),
    sqlalchemy.Column("license_type", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("restrictions", sqlalchemy.String, default=""),
    sqlalchemy.Column("expiry", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("address", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("password", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("email", sqlalchemy.String, nullable=False, server_default=""),   # the database fills it: `databases` skips Python defaults
)

# Which motorist a plate belongs to (one motorist can have several plates). The notification goes to its owner.
vehicles_table = sqlalchemy.Table(
    "vehicles",
    metadata,
    sqlalchemy.Column("plate_key", sqlalchemy.String, primary_key=True),   # ABC1234: capitals and digits only
    sqlalchemy.Column("plate", sqlalchemy.String, nullable=False),         # as people write it
    sqlalchemy.Column("user_id", sqlalchemy.String, nullable=False),
)

violations_table = sqlalchemy.Table(
    "violations",
    metadata,
    sqlalchemy.Column("id", sqlalchemy.String, primary_key=True),
    sqlalchemy.Column("user_id", sqlalchemy.String, nullable=False),   # owner
    sqlalchemy.Column("cls", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("confidence", sqlalchemy.Float, nullable=False),
    sqlalchemy.Column("timestamp", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("image_path", sqlalchemy.String, default=""),
    sqlalchemy.Column("status", sqlalchemy.String, default="pending"),
    # JSON-encoded list of evidence frame paths captured across the ROI dwell,
    # not just one frame — lets reviewers see the full trajectory to rule out
    # a false positive. image_path stays as the first frame for thumbnails.
    sqlalchemy.Column("evidence_paths", sqlalchemy.Text, default="[]"),
    # Tracker-assigned vehicle ID, so a log entry can be traced back to the
    # exact tracked vehicle that produced it.
    sqlalchemy.Column("track_id", sqlalchemy.Integer, default=-1),
    sqlalchemy.Column("source", sqlalchemy.String, default="live"),
    sqlalchemy.Column("session_id", sqlalchemy.String, default="default"),
    sqlalchemy.Column("plate_text", sqlalchemy.String, default="unidentified"),
)

fcm_tokens_table = sqlalchemy.Table(
    "fcm_tokens",
    metadata,
    sqlalchemy.Column("token", sqlalchemy.String, primary_key=True),
    sqlalchemy.Column("user_id", sqlalchemy.String, nullable=False),
)

# A motorist's appeal against a confirmed ticket, filed from the phone app. A reviewer decides it later.
appeals_table = sqlalchemy.Table(
    "appeals",
    metadata,
    sqlalchemy.Column("id", sqlalchemy.String, primary_key=True),
    sqlalchemy.Column("violation_id", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("user_id", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("reason", sqlalchemy.Text, nullable=False),
    sqlalchemy.Column("status", sqlalchemy.String, nullable=False),         # pending | accepted | rejected
    sqlalchemy.Column("created_at", sqlalchemy.String, nullable=False),
)

# Every notice the system wrote to a motorist (the laptop's mailbox, opened from a phone in offline mode).
notices_table = sqlalchemy.Table(
    "notices",
    metadata,
    sqlalchemy.Column("id", sqlalchemy.String, primary_key=True),
    sqlalchemy.Column("user_id", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("to_email", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("subject", sqlalchemy.String, nullable=False),
    sqlalchemy.Column("body", sqlalchemy.Text, nullable=False),
    sqlalchemy.Column("status", sqlalchemy.String, nullable=False),        # sent | failed | local
    sqlalchemy.Column("detail", sqlalchemy.String, nullable=False),        # why it failed
    sqlalchemy.Column("frames", sqlalchemy.Text, nullable=False, server_default="[]"),   # JSON list of photo file names
    sqlalchemy.Column("created_at", sqlalchemy.String, nullable=False),
)

engine = sqlalchemy.create_engine(
    DATABASE_URL.replace("+aiosqlite", ""),
    connect_args={"check_same_thread": False},
)


def create_tables():
    """Create all tables if they don't exist."""
    metadata.create_all(engine)


def run_migrations():
    """
    Apply incremental schema changes that create_all() won't handle
    (it never alters existing tables). Safe to run on every startup —
    each ALTER TABLE is wrapped in a try/except so duplicates are ignored.
    """
    migrations = [
        "ALTER TABLE violations ADD COLUMN user_id TEXT NOT NULL DEFAULT 'unknown'",
        "ALTER TABLE fcm_tokens  ADD COLUMN user_id TEXT NOT NULL DEFAULT 'unknown'",
        "ALTER TABLE violations ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
        "ALTER TABLE violations ADD COLUMN evidence_paths TEXT NOT NULL DEFAULT '[]'",
        "ALTER TABLE violations ADD COLUMN track_id INTEGER NOT NULL DEFAULT -1",
        "ALTER TABLE violations ADD COLUMN source TEXT NOT NULL DEFAULT 'live'",
        "ALTER TABLE violations ADD COLUMN session_id TEXT NOT NULL DEFAULT 'default'",
        "ALTER TABLE violations ADD COLUMN plate_text TEXT NOT NULL DEFAULT 'unidentified'",
        "ALTER TABLE users ADD COLUMN email TEXT NOT NULL DEFAULT ''",
        "ALTER TABLE notices ADD COLUMN frames TEXT NOT NULL DEFAULT '[]'",
    ]
    with engine.connect() as conn:
        for sql in migrations:
            try:
                conn.execute(sqlalchemy.text(sql))
                conn.commit()
                print(f"Migration applied: {sql}")
            except Exception:
                # Column already exists — safe to ignore
                pass
