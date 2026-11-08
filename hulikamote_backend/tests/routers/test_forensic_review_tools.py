"""
routers/forensic.py - the review tools: take photos out of a ticket, read the plate again, read a plate drawn by hand.
The report is a temp file; the database writes are recorded; the plate model and OCR are replaced by fakes.
"""
import asyncio
import json

import cv2
import numpy as np
import pytest


def crop_result(file, text):
    return {"image_raw": file, "image_sr": None, "image_context": None, "t": 1.0, "raw": text, "cleaned": text, "confidence": 0.9}


@pytest.fixture
def review(tmp_path, monkeypatch):
    import engine.pipeline as pipeline
    import store
    from routers import forensic

    monkeypatch.setattr(pipeline, "EVIDENCE_DIR", tmp_path)
    out = tmp_path / "forensic" / "task1" / "output"
    out.mkdir(parents=True)
    ticket = {
        "ticket_uid": "u1", "track_id": 1, "violations": ["counterflow"], "plate_text": "AAA1111", "db_ids": ["r1", "r2"], "flags": [],
        "evidence_paths": ["p1.jpg", "p2.jpg", "p3.jpg"],
        "evidence_meta": [{"file": "p1.jpg", "t": 1.0, "crop": "c1.jpg", "plate": "AAA1111"},
                          {"file": "p2.jpg", "t": 2.0, "crop": "c2.jpg", "plate": "AAA1111"},
                          {"file": "p3.jpg", "t": 3.0, "crop": "c3.jpg", "plate": "BBB2222"}],
        "crop_results": [crop_result("c1.jpg", "AAA1111"), crop_result("c2.jpg", "AAA1111"), crop_result("c3.jpg", "BBB2222")],
        "plate_crop_paths": ["c1.jpg", "c2.jpg", "c3.jpg"], "metadata": {"plate_format": "ph_standard"},
    }
    report = out / "report.json"
    report.write_text(json.dumps([ticket]))
    (out / "forensic_config.json").write_text(json.dumps({"plate_format": "ph_standard", "flag_sensitivity": 4}))

    evidence_rows, plate_rows = [], []

    async def fake_evidence(ids, paths):
        evidence_rows.append((list(ids), list(paths)))
        return len(ids)

    async def fake_plate(ids, plate, user_id):
        plate_rows.append((list(ids), plate, user_id))
        return len(ids)

    async def fake_owner(plate):
        return {"id": "user_001"} if plate == "BBB2222" else None

    monkeypatch.setattr(store, "set_violation_evidence", fake_evidence, raising=False)
    monkeypatch.setattr(store, "update_violation_plate", fake_plate, raising=False)
    monkeypatch.setattr(forensic, "get_user_by_plate", fake_owner)
    forensic.forensic_tasks.pop("task1", None)

    def saved():
        return json.loads(report.read_text())[0]
    return forensic, saved, evidence_rows, plate_rows, tmp_path


def test_removed_photos_leave_the_ticket_the_report_and_every_row(review):
    forensic, saved, evidence_rows, plate_rows, _ = review
    res = asyncio.run(forensic.remove_ticket_frames(forensic.TicketFramesRequest(task_id="task1", ticket_uid="u1", frames=["p3.jpg"])))
    assert res["tickets"][0]["evidence_paths"] == ["p1.jpg", "p2.jpg"]
    assert saved()["evidence_paths"] == ["p1.jpg", "p2.jpg"]
    assert evidence_rows == [(["r1", "r2"], ["p1.jpg", "p2.jpg"])]                  # what a notice will carry from now on
    assert plate_rows == []                                                         # the plate did not change


def test_removing_the_photos_that_gave_the_plate_moves_the_plate_and_its_owner(review):
    forensic, saved, evidence_rows, plate_rows, _ = review
    asyncio.run(forensic.remove_ticket_frames(forensic.TicketFramesRequest(task_id="task1", ticket_uid="u1", frames=["p1.jpg", "p2.jpg"])))
    assert saved()["plate_text"] == "BBB2222"
    assert plate_rows == [(["r1", "r2"], "BBB2222", "user_001")]                    # the registered owner of the new plate


def test_a_ticket_cannot_lose_all_its_photos(review):
    forensic, saved, evidence_rows, _, _ = review
    res = asyncio.run(forensic.remove_ticket_frames(
        forensic.TicketFramesRequest(task_id="task1", ticket_uid="u1", frames=["p1.jpg", "p2.jpg", "p3.jpg"])))
    assert res.status_code == 400 and "at least one to keep" in json.loads(res.body)["error"]
    assert evidence_rows == [] and len(saved()["evidence_paths"]) == 3


@pytest.mark.parametrize("call,uid,task", [("remove_ticket_frames", "u1", "nope"), ("remove_ticket_frames", "ghost", "task1"),
                                           ("reread_ticket_plate", "u1", "nope"), ("reread_ticket_plate", "ghost", "task1")])
def test_an_unknown_analysis_or_ticket_is_a_404(review, call, uid, task):
    forensic = review[0]
    res = asyncio.run(getattr(forensic, call)(forensic.TicketFramesRequest(task_id=task, ticket_uid=uid, frames=["p1.jpg"])))
    assert res.status_code == 404


def test_reading_again_saves_the_new_plate_and_tells_the_owner_lookup_about_it(review, monkeypatch):
    forensic, saved, _, plate_rows, _ = review
    seen = {}

    def fake_reread(ticket, frames, config, plate_format):
        seen.update(frames=frames, plate_format=plate_format)
        new = dict(ticket, plate_text="BBB2222")
        return new, {"checked": 3, "found": 2, "no_picture": 1, "no_plate": 0, "suggested": "BBB2222", "kept_manual": False}

    monkeypatch.setattr(forensic, "_reread_with_models", fake_reread)
    res = asyncio.run(forensic.reread_ticket_plate(forensic.TicketFramesRequest(task_id="task1", ticket_uid="u1", frames=["p2.jpg"])))
    assert seen == {"frames": ["p2.jpg"], "plate_format": "ph_standard"}
    assert res["reread"]["found"] == 2 and res["tickets"][0]["plate_text"] == "BBB2222"
    assert saved()["plate_text"] == "BBB2222"
    assert plate_rows == [(["r1", "r2"], "BBB2222", "user_001")]


def test_when_the_read_finds_the_same_plate_no_row_is_touched(review, monkeypatch):
    forensic, _, _, plate_rows, _ = review
    monkeypatch.setattr(forensic, "_reread_with_models", lambda t, f, c, p: (dict(t), {"checked": 3, "found": 0, "suggested": "AAA1111", "kept_manual": False}))
    asyncio.run(forensic.reread_ticket_plate(forensic.TicketFramesRequest(task_id="task1", ticket_uid="u1")))
    assert plate_rows == []


def test_reading_again_with_nothing_to_read_is_a_400(review, monkeypatch):
    forensic = review[0]

    def nothing(*_):
        raise ValueError("There are no photos to read")
    monkeypatch.setattr(forensic, "_reread_with_models", nothing)
    res = asyncio.run(forensic.reread_ticket_plate(forensic.TicketFramesRequest(task_id="task1", ticket_uid="u1", frames=["x.jpg"])))
    assert res.status_code == 400


# ─── a plate drawn by hand ───────────────────────────────────────────────────

def test_a_drawn_box_is_read_and_the_crop_saved_without_touching_any_ticket(review, monkeypatch):
    import engine.pipeline as pipeline
    forensic, saved, evidence_rows, plate_rows, tmp_path = review
    cv2.imwrite(str(tmp_path / "photo.jpg"), np.full((100, 200, 3), 120, np.uint8))
    seen = {}

    def fake_ocr(crop, plate_format, engine, enhancement):
        seen["shape"], seen["format"] = crop.shape[:2], plate_format
        return "ab 1234", "AB1234", crop, crop, 0.88

    monkeypatch.setattr(pipeline, "_extract_plate_text", fake_ocr)
    before = saved()
    res = asyncio.run(forensic.read_plate_box(forensic.PlateBoxRequest(task_id="task1", image="photo.jpg", box=[0.25, 0.5, 0.75, 0.9])))

    assert (res["text"], res["raw"], res["confidence"]) == ("AB1234", "ab 1234", 0.88)
    assert (tmp_path / res["crop"]).is_file()                                       # so the reviewer's number can train the OCR
    assert seen == {"shape": (40, 100), "format": "ph_standard"}
    assert saved() == before and evidence_rows == [] and plate_rows == []


def test_a_drawn_box_the_ocr_cannot_read_gives_an_empty_text(review, monkeypatch):
    import engine.pipeline as pipeline
    forensic, _, _, _, tmp_path = review
    cv2.imwrite(str(tmp_path / "photo.jpg"), np.full((100, 200, 3), 120, np.uint8))
    monkeypatch.setattr(pipeline, "_extract_plate_text", lambda crop, f, e, h: ("", "unidentified", crop, crop, 0.0))
    res = asyncio.run(forensic.read_plate_box(forensic.PlateBoxRequest(image="photo.jpg", box=[0.1, 0.1, 0.9, 0.9])))
    assert res["text"] == ""                                                        # not "unidentified": the box simply has no plate


@pytest.mark.parametrize("image,box,code", [("gone.jpg", [0.1, 0.1, 0.9, 0.9], 404), ("photo.jpg", [0.1, 0.1, 0.11, 0.9], 400)])
def test_a_missing_photo_or_a_tiny_box_is_refused(review, image, box, code):
    forensic, _, _, _, tmp_path = review
    cv2.imwrite(str(tmp_path / "photo.jpg"), np.full((100, 200, 3), 120, np.uint8))
    res = asyncio.run(forensic.read_plate_box(forensic.PlateBoxRequest(image=image, box=box)))
    assert res.status_code == code


def test_the_photo_name_cannot_reach_outside_the_evidence_folder(review, tmp_path_factory):
    forensic = review[0]
    outside = tmp_path_factory.mktemp("outside")
    cv2.imwrite(str(outside / "secret.jpg"), np.full((100, 200, 3), 9, np.uint8))
    res = asyncio.run(forensic.read_plate_box(forensic.PlateBoxRequest(image=str(outside / "secret.jpg"), box=[0.1, 0.1, 0.9, 0.9])))
    assert res.status_code == 404                                                   # only the bare name is used, inside the folder
