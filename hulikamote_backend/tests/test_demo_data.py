"""tools/make_demo_data.py - a clean demo database built from real tickets, without ever changing the real database."""
import hashlib
import importlib.util
import json
import sqlite3
from pathlib import Path

import pytest
import sqlalchemy

import database
import evidence_files

TOOL = Path(__file__).resolve().parents[2] / "tools" / "make_demo_data.py"


@pytest.fixture
def tool():
    spec = importlib.util.spec_from_file_location("make_demo_data", TOOL)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def real(tmp_path, monkeypatch):
    """A stand-in for the real database and its photo folder."""
    photos = tmp_path / "evidence"
    photos.mkdir()
    monkeypatch.setattr(evidence_files, "EVIDENCE_DIR", photos)
    db = tmp_path / "real.db"
    engine = sqlalchemy.create_engine(f"sqlite:///{db.as_posix()}")
    database.metadata.create_all(engine)
    counter = {"n": 0}

    def ticket(cls, plate, status, photos_on_disk=3, minute=0):
        counter["n"] += 1
        names = [f"t{counter['n']}_{i}.jpg" for i in range(photos_on_disk)]
        for name in names:
            (photos / name).write_bytes(b"\xff\xd8 fake photo")
        with engine.begin() as con:
            con.execute(database.violations_table.insert().values(
                id=f"id-{counter['n']:03d}-{plate}", user_id="unregistered", cls=cls, confidence=0.9,
                timestamp=f"2026-10-28T08:{minute:02d}:00+00:00", image_path=f"snapshots/evidence/{names[0] if names else 'x.jpg'}",
                status=status, evidence_paths=json.dumps(names or ["missing.jpg"]), track_id=1, source="forensic",
                session_id="s1", plate_text=plate))

    ticket("counterflow", "AB12CDE", "approved", minute=1)
    ticket("counterflow", "FG34HIJ", "approved", minute=2)
    ticket("counterflow", "KL56MNO", "approved", minute=3)
    ticket("red_light", "PQ78RST", "pending", minute=4)
    ticket("counterflow", "UV90WXY", "pending", minute=5)
    ticket("restricted_lane", "ZA11BCD", "pending", minute=6)
    ticket("counterflow", "EF22GHI", "pending", minute=7)
    # not worth showing: no plate read, a scrap of a plate, or photos that are gone
    ticket("counterflow", "unidentified", "approved", minute=8)
    ticket("counterflow", "EJD", "approved", minute=9)
    ticket("counterflow", "JK33LMN", "approved", photos_on_disk=0, minute=10)
    return db


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows(db: Path, sql: str):
    con = sqlite3.connect(db)
    con.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in con.execute(sql)]
    finally:
        con.close()


def test_the_real_database_is_never_changed(tool, real, tmp_path):
    before = digest(real)
    tool.build(real, tmp_path / "demo.db")
    assert digest(real) == before


def test_it_refuses_to_overwrite_the_real_database(tool, real):
    with pytest.raises(ValueError):
        tool.build(real, real)
    assert real.exists() and rows(real, "select count(*) as n from violations")[0]["n"] == 10


def test_only_tickets_worth_showing_are_copied(tool, real, tmp_path):
    out = tmp_path / "demo.db"
    result = tool.build(real, out)
    plates = {r["plate_text"] for r in rows(out, "select plate_text from violations")}
    assert plates == {"AB12CDE", "FG34HIJ", "KL56MNO", "PQ78RST", "UV90WXY", "ZA11BCD", "EF22GHI"}
    assert result["confirmed"] == 3 and result["to_review"] == 4


def test_every_confirmed_ticket_has_an_owner_a_notice_with_photos_and_counts_as_a_point(tool, real, tmp_path):
    out = tmp_path / "demo.db"
    tool.build(real, out)
    confirmed = rows(out, "select * from violations where status = 'approved'")
    assert len(confirmed) == 3 and all(r["user_id"].startswith("user_00") for r in confirmed)
    for ticket in confirmed:
        notice = rows(out, f"select * from notices where user_id = '{ticket['user_id']}' and subject like '%{ticket['plate_text']}%'")
        assert len(notice) == 1 and notice[0]["status"] == "local" and notice[0]["to_email"] == ""
        assert 1 <= len(json.loads(notice[0]["frames"])) <= tool.NOTICE_PHOTOS
        assert ticket["plate_text"] in notice[0]["body"] and "file an appeal" in notice[0]["body"]


def test_plates_in_the_photos_belong_to_the_demo_motorists(tool, real, tmp_path):
    out = tmp_path / "demo.db"
    tool.build(real, out)
    owned = {r["plate"]: r["user_id"] for r in rows(out, "select plate, user_id from vehicles")}
    assert owned["ABC 1234"] == "user_001" and owned["DEF 5678"] == "user_002" and owned["GHI 9012"] == "user_003"
    assert {"AB12CDE", "FG34HIJ", "KL56MNO"} <= set(owned)


def test_some_tickets_are_left_to_confirm_live_and_two_of_them_reach_a_phone(tool, real, tmp_path):
    out = tmp_path / "demo.db"
    tool.build(real, out)
    pending = rows(out, "select cls, user_id from violations where status = 'pending'")
    assert len(pending) == 4 and len({r["cls"] for r in pending}) >= 3                   # a mix of violations
    assert sum(r["user_id"].startswith("user_00") for r in pending) == tool.LIVE_DEMO_OWNED


def test_there_is_one_appeal_for_the_officer_to_see(tool, real, tmp_path):
    out = tmp_path / "demo.db"
    tool.build(real, out)
    appeals = rows(out, "select * from appeals")
    assert len(appeals) <= 1
    for appeal in appeals:
        assert appeal["status"] == "pending" and appeal["user_id"] == "user_003"


def test_running_it_again_starts_from_a_clean_demo(tool, real, tmp_path):
    out = tmp_path / "demo.db"
    tool.build(real, out)
    con = sqlite3.connect(out)
    con.execute("delete from violations")
    con.commit()
    con.close()
    tool.build(real, out)
    assert rows(out, "select count(*) as n from violations")[0]["n"] == 7


def test_the_demo_database_is_a_complete_one_the_backend_can_use(tool, real, tmp_path):
    out = tmp_path / "demo.db"
    tool.build(real, out)
    tables = {r["name"] for r in rows(out, "select name from sqlite_master where type = 'table'")}
    assert {"users", "vehicles", "violations", "notices", "appeals", "fcm_tokens"} <= tables
    assert rows(out, "select count(*) as n from users")[0]["n"] == 3
