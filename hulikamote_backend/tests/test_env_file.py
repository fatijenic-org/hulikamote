"""env_file.py - change a few lines of .env and leave everything else (other secrets, comments) alone."""
import os

import pytest

from env_file import update_env


def test_it_replaces_a_line_adds_a_missing_one_and_keeps_everything_else(tmp_path, monkeypatch):
    monkeypatch.delenv("HK_A", raising=False)
    monkeypatch.delenv("HK_B", raising=False)
    path = tmp_path / ".env"
    path.write_text("# my secrets\nGITHUB_TOKEN=keep-me\n\nHK_A=old\n")
    update_env(path, {"HK_A": "new", "HK_B": "added"})
    assert path.read_text() == "# my secrets\nGITHUB_TOKEN=keep-me\n\nHK_A=new\nHK_B=added\n"
    assert os.environ["HK_A"] == "new" and os.environ["HK_B"] == "added"           # no restart needed
    monkeypatch.delenv("HK_A")
    monkeypatch.delenv("HK_B")


def test_it_creates_the_file_when_there_is_none(tmp_path, monkeypatch):
    monkeypatch.delenv("HK_C", raising=False)
    path = tmp_path / ".env"
    update_env(path, {"HK_C": "1"})
    assert path.read_text() == "HK_C=1\n" and not list(tmp_path.glob("*.tmp"))
    monkeypatch.delenv("HK_C")


def test_a_commented_out_line_is_not_taken_for_the_setting(tmp_path, monkeypatch):
    monkeypatch.delenv("HK_D", raising=False)
    path = tmp_path / ".env"
    path.write_text("# HK_D=commented\n")
    update_env(path, {"HK_D": "real"})
    assert path.read_text() == "# HK_D=commented\nHK_D=real\n"
    monkeypatch.delenv("HK_D")


@pytest.mark.parametrize("key,value", [("HK_E", "a\nGITHUB_TOKEN=stolen"), ("HK_E", "a\rb"), ("not a name", "x")])
def test_a_value_cannot_smuggle_in_another_line(tmp_path, key, value):
    path = tmp_path / ".env"
    with pytest.raises(ValueError):
        update_env(path, {key: value})
    assert not path.exists()
