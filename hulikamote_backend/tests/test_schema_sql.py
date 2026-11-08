"""supabase/schema.sql - the SQL pasted into Supabase must parse and keep the phone safe.
Needs the PostgreSQL parser (`pip install pglast`); without it this test is skipped. The same check runs from the command
line: python tools/check_schema.py"""
import importlib.util
from pathlib import Path

import pytest

pytest.importorskip("pglast")

TOOLS = Path(__file__).resolve().parents[2] / "tools"


@pytest.fixture
def checker():
    spec = importlib.util.spec_from_file_location("check_schema", TOOLS / "check_schema.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_the_schema_parses_and_the_safety_rules_hold(checker):
    assert checker.check(checker.SCHEMA.read_text(encoding="utf-8")) == []


def test_the_checker_catches_a_table_without_security_and_a_typo(checker):
    sql = checker.SCHEMA.read_text(encoding="utf-8")
    no_security = sql.replace("alter table public.tickets        enable row level security;", "")
    assert any("tickets has no row-level security" in p for p in checker.check(no_security))
    typo = sql.replace("if auth.uid() is null then", "iff auth.uid() is null then")
    assert any("does not parse" in p for p in checker.check(typo))
