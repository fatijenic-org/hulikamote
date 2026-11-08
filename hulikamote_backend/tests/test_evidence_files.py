"""evidence_files.py - which photos belong to a ticket, and how many of them an e-mail may carry."""
import json

import pytest

import emailer
import evidence_files


@pytest.fixture
def folder(tmp_path, monkeypatch):
    monkeypatch.setattr(evidence_files, "EVIDENCE_DIR", tmp_path)
    for name, size in (("a.jpg", 10), ("b.jpg", 20), ("c.jpg", 30)):
        (tmp_path / name).write_bytes(b"x" * size)
    return tmp_path


def test_a_ticket_lists_its_photos_that_are_still_on_disk_in_order(folder):
    ticket = {"evidence_paths": json.dumps(["b.jpg", "gone.jpg", "a.jpg", "b.jpg"])}
    assert evidence_files.frames_of(ticket) == ["b.jpg", "a.jpg"]            # no duplicates, nothing missing


def test_a_stored_path_can_never_point_outside_the_evidence_folder(folder, tmp_path_factory):
    outside = tmp_path_factory.mktemp("outside") / "secret.jpg"
    outside.write_bytes(b"secret")
    ticket = {"evidence_paths": [str(outside), "../a.jpg", "sub/dir/a.jpg"]}
    # only the bare file name counts and it is looked for inside the evidence folder: the outside file is never found
    assert evidence_files.frames_of(ticket) == ["a.jpg"]


@pytest.mark.parametrize("raw", [None, "", "[]", "not json", 5])
def test_a_ticket_without_usable_photos_has_none(folder, raw):
    assert evidence_files.frames_of({"evidence_paths": raw if raw != 5 else []}) == []


def test_photos_are_read_in_order_until_the_size_limit_and_never_cut(folder):
    assert [n for n, _ in evidence_files.read_within(["a.jpg", "b.jpg", "c.jpg"], 100)] == ["a.jpg", "b.jpg", "c.jpg"]
    assert [n for n, _ in evidence_files.read_within(["a.jpg", "b.jpg", "c.jpg"], 35)] == ["a.jpg", "b.jpg"]     # 10 + 20 fit, +30 does not
    assert evidence_files.read_within(["c.jpg"], 5) == []


def test_every_photo_is_attached_to_the_email_and_the_text_says_how_many(folder):
    owner = {"name": "Juan", "email": "juan@example.test"}
    ticket = {"id": "ab12cd34-0000", "cls": "no_helmet", "plate_text": "ABC 1234", "timestamp": "2026-10-29T08:00:00+00:00"}
    msg = emailer.build_message(owner, ticket, ["a.jpg", "b.jpg", "c.jpg"])
    names = [part.get_filename() for part in msg.iter_attachments()]
    assert names == ["a.jpg", "b.jpg", "c.jpg"]
    assert "Photos:        3 attached" in msg.get_body(("plain",)).get_content()


def test_when_the_photos_are_too_big_for_one_mail_the_rest_stay_in_the_app(folder, monkeypatch):
    monkeypatch.setattr(emailer, "MAX_ATTACHMENT_BYTES", 35)
    owner = {"name": "Juan", "email": "juan@example.test"}
    ticket = {"id": "ab12cd34-0000", "cls": "no_helmet", "plate_text": "ABC 1234", "timestamp": "2026-10-29T08:00:00+00:00"}
    msg = emailer.build_message(owner, ticket, ["a.jpg", "b.jpg", "c.jpg"])
    assert [p.get_filename() for p in msg.iter_attachments()] == ["a.jpg", "b.jpg"]
    assert "2 attached (all 3 are in the app)" in msg.get_body(("plain",)).get_content()


def test_a_ticket_with_no_photos_has_no_photo_line(folder):
    msg = emailer.build_message({"name": "Juan", "email": "j@example.test"},
                                {"id": "ab12cd34-0000", "cls": "no_helmet", "plate_text": "ABC", "timestamp": "2026-10-29T08:00:00+00:00"})
    assert "Photos:" not in msg.get_content() and not list(msg.iter_attachments())
