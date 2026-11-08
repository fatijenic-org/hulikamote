"""
routers/forensic.py - operator plate edit: POST /api/forensic/tickets/set-plate.
The report is a temp file and the DB write is recorded, so this touches no real data.
"""
import asyncio
import json

import pytest


@pytest.fixture
def run(tmp_path, monkeypatch):
    import engine.pipeline as pipeline
    import store
    from routers import forensic

    monkeypatch.setattr(pipeline, "EVIDENCE_DIR", tmp_path)
    out = tmp_path / "forensic" / "task1" / "output"
    out.mkdir(parents=True)
    tickets = [
        {"ticket_uid": "u1", "track_id": 1, "violations": ["counterflow"], "plate_text": "unidentified",
         "evidence_paths": ["a.jpg"], "db_ids": ["r1", "r2"], "flags": [],
         "evidence_meta": [{"file": "a.jpg", "t": 1.0, "bbox": [0, 0, 10, 10]}],
         "metadata": {"plate_format": "ph_standard"}},
        {"ticket_uid": "u2", "track_id": 2, "violations": ["red_light"], "plate_text": "KMO5221",
         "vote_tally": {"KMO5221": 9.0}, "evidence_paths": ["b.jpg"], "db_ids": ["r3"], "flags": [],
         "evidence_meta": [{"file": "b.jpg", "t": 5.0, "bbox": [0, 0, 10, 10]}],
         "metadata": {"plate_format": "ph_standard"}},
    ]
    report = out / "report.json"
    report.write_text(json.dumps(tickets))
    rows = []

    async def fake_update(ids, plate, user_id):
        rows.append((list(ids), plate, user_id))
        return len(ids)

    async def fake_owner(plate):
        return {"id": "user_001"} if plate == "N0112345678" else None

    monkeypatch.setattr(store, "update_violation_plate", fake_update, raising=False)
    monkeypatch.setattr(forensic, "get_user_by_plate", fake_owner)
    forensic.forensic_tasks.pop("task1", None)

    def call(uid, plate="", revert=False, task="task1"):
        req = forensic.TicketPlateRequest(task_id=task, ticket_uid=uid, plate_text=plate, revert=revert)
        return asyncio.run(forensic.set_ticket_plate(req))

    def saved(uid):
        return next(t for t in json.loads(report.read_text()) if t["ticket_uid"] == uid)

    return call, saved, rows


def test_typed_plate_lands_on_the_ticket_the_report_and_every_row(run):
    call, saved, rows = run
    res = call("u1", "hle 150")
    t = next(x for x in res["tickets"] if x["ticket_uid"] == "u1")
    assert (t["plate_text"], t["plate_manual"], t["plate_ocr"]) == ("HLE150", True, "unidentified")
    assert saved("u1")["plate_text"] == "HLE150"
    assert rows == [(["r1", "r2"], "HLE150", "unregistered")]    # a plate with no known owner
    assert saved("u2")["plate_text"] == "KMO5221"                # the other ticket is untouched


def test_empty_plate_means_no_readable_plate(run):
    call, saved, rows = run
    call("u2", "")
    t = saved("u2")
    assert (t["plate_text"], t["plate_manual"], t["plate_ocr"]) == ("unidentified", True, "KMO5221")
    assert rows == [(["r3"], "unidentified", "no_plate_found")]


def test_revert_restores_what_the_ocr_read(run):
    call, saved, rows = run
    call("u2", "ABC1234")
    call("u2", revert=True)
    t = saved("u2")
    assert t["plate_text"] == "KMO5221" and "plate_manual" not in t and "plate_ocr" not in t
    assert rows[-1] == (["r3"], "KMO5221", "unregistered")


def test_owner_follows_the_plate_like_it_does_after_an_analysis(run):
    call, saved, rows = run
    call("u1", "N01-12-345678")      # the one rule the analysis has: plate text equals a license number
    assert rows == [(["r1", "r2"], "N0112345678", "user_001")]


def test_unknown_ticket_or_report_and_too_long_plates_are_refused(run):
    call, saved, rows = run
    assert call("nope", "ABC1234").status_code == 404
    assert call("u1", "ABC1234", task="missing").status_code == 404
    assert call("u1", "A" * 13).status_code == 400
    assert rows == []


def test_link_crops_to_frames_uses_nearest_crop_within_tolerance():
    import sys, types
    from routers.forensic import _link_crops_to_frames
    t = {
        "evidence_meta": [{"file": "a", "t": 1.1}, {"file": "b", "t": 9.0}, {"file": "c", "t": None}],
        "crop_results": [{"image_raw": "c1", "cleaned": "ZZ", "t": 1.0}, {"image_raw": "c2", "cleaned": "YY", "t": 3.0}],
    }
    _link_crops_to_frames(t)
    m = t["evidence_meta"]
    assert (m[0]["crop"], m[0]["plate"]) == ("c1", "ZZ")
    assert m[1]["crop"] is None      # too far from any crop
    assert m[2]["crop"] is None      # frame has no time


# ─── live-config: the wizard's zones and settings become the Live Monitor's rules ───────────

@pytest.fixture
def live(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient

    from main import app
    from routers import forensic, stream

    cfg = tmp_path / "camera_config.json"
    cfg.write_text(json.dumps({"camera_profiles": [{"name": "Laptop B", "url": "rtsp://192.168.1.20:8554/cam1"}],
                               "active_source": {"profile": "Laptop B"}, "camera_id": "barangay_1"}))
    calls = {"reload": 0, "inference": []}
    monkeypatch.setattr(stream, "CONFIG_PATH", cfg)
    monkeypatch.setattr(stream, "reload_pipeline", lambda: calls.__setitem__("reload", calls["reload"] + 1))
    monkeypatch.setattr(forensic, "get_inference", lambda **kw: calls["inference"].append(kw))
    gen = stream._stream_generation
    return TestClient(app), cfg, calls, gen, stream


WIZARD = {"active_violations": ["counterflow", "pickup_passengers"], "tracker": "deepsort", "plate_model": "plate_specialist.onnx",
          "per_violation_configs": {
              "counterflow": {"rois": [{"polygon": [[0, 0], [1920, 0], [1920, 1080], [0, 1080]], "vector": {"x_dir": 0.0, "y_dir": 5.0}}]},
              "pickup_passengers": {"rois": [], "bed_passengers_allowed": 1}}}


def test_live_config_writes_zones_keeps_the_cameras_and_restarts_the_live_view(live):
    client, cfg, calls, gen, stream = live
    r = client.post("/api/forensic/live-config", json=WIZARD)
    assert r.status_code == 200 and r.json()["violations"] == ["counterflow", "pickup_passengers"]
    saved = json.loads(cfg.read_text())
    assert saved["regions_of_interest"]["counterflow_zones"][0]["legal_flow_vector"] == {"x_dir": 0.0, "y_dir": 1.0}
    assert saved["active_violations"] == ["counterflow", "pickup_passengers"] and saved["video_native_width"] == 1920
    assert saved["camera_profiles"][0]["name"] == "Laptop B" and saved["active_source"] == {"profile": "Laptop B"}   # kept
    assert saved["camera_id"] == "barangay_1"
    assert calls["reload"] == 1 and calls["inference"] == [{"force_reload": True, "tracker_type": "deepsort"}]
    assert stream._stream_generation == gen + 1


def test_live_config_keeps_what_the_camera_learned_about_its_road(live):
    client, cfg, calls, gen, stream = live
    saved = json.loads(cfg.read_text())
    saved["learned_road"] = {"profile:Laptop B": {"zones": {"pedestrian_lane": [{"polygon": [[0, 0], [10, 0], [10, 10]]}]}}}
    saved["learned_lines_as_rules"] = True
    cfg.write_text(json.dumps(saved))
    assert client.post("/api/forensic/live-config", json=WIZARD).status_code == 200
    after = json.loads(cfg.read_text())
    assert after["learned_road"] == saved["learned_road"] and after["learned_lines_as_rules"] is True


def test_live_config_needs_at_least_one_violation(live):
    client, cfg, calls, gen, stream = live
    before = cfg.read_text()
    r = client.post("/api/forensic/live-config", json={"active_violations": [], "per_violation_configs": {}})
    assert r.status_code == 400 and cfg.read_text() == before and calls["reload"] == 0


def test_the_forensic_task_and_live_config_share_one_conversion():
    from routers.forensic import prepare_pipeline_config
    out = prepare_pipeline_config({"per_violation_configs": {"overloading": {"max_riders": 3}}})
    assert out["max_riders"] == 3 and out["regions_of_interest"] == {} and out["video_native_height"] == 1080
