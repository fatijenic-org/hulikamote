"""
conftest.py — Shared async test fixtures with fresh schema + seeded users.
"""
import sys
import os

# Windows quirk: if onnxruntime is imported before torch, torch's cuDNN DLL fails to load (WinError 127).
# Importing torch first (the real server does too) makes test collection independent of file order.
try:
    import torch  # noqa: F401
except ImportError:
    pass

import pytest
import pytest_asyncio
import databases
import sqlalchemy

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import database as db_module
from database import metadata
from httpx import AsyncClient, ASGITransport

@pytest.fixture(autouse=True)
def no_real_email(monkeypatch, tmp_path):
    """No test may send a real e-mail or touch the real .env: the settings file is a temp one, and every mail setting
    starts empty (set but empty, so nothing overrides it, and whatever a test changes is undone afterwards)."""
    import emailer
    monkeypatch.setattr(emailer, "ENV_FILE", tmp_path / ".env")
    for key in emailer.ENV_KEYS:
        monkeypatch.setenv(key, "")


@pytest.fixture(autouse=True)
def evidence_in_a_temp_folder(monkeypatch, tmp_path):
    """No test may write evidence photos or close-ups into the real snapshots/evidence folder."""
    import engine.pipeline as pipeline_mod
    monkeypatch.setattr(pipeline_mod, "EVIDENCE_DIR", tmp_path / "evidence")


@pytest_asyncio.fixture(scope="module")
async def ac(tmp_path_factory):
    # Point to an isolated test DB in a temp folder (never the tracked test_hulikamote.db)
    db_file = (tmp_path_factory.mktemp("testdb") / "test_hulikamote.db").as_posix()
    TEST_DB_URL = f"sqlite+aiosqlite:///{db_file}"
    TEST_DB_SYNC = f"sqlite:///{db_file}"
    db_module.DATABASE_URL = TEST_DB_URL
    db_module.database = databases.Database(TEST_DB_URL)
    db_module.engine = sqlalchemy.create_engine(
        TEST_DB_SYNC, connect_args={"check_same_thread": False}
    )

    # Drop and recreate tables to pick up schema changes
    metadata.drop_all(db_module.engine)
    metadata.create_all(db_module.engine)

    # Connect and seed users
    await db_module.database.connect()
    from store import seed_users
    await seed_users()

    from main import app
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        yield client

    await db_module.database.disconnect()
