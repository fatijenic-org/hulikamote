"""routers/settings.py - choosing the detection model."""
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_model_selection_endpoint_updates_backend_model(tmp_path, monkeypatch):
    """The video-analysis screen should be able to choose a model before inference starts."""
    import yolo_inference

    # set_model_path() swaps module globals and saves the choice to models/active_model.txt.
    # Point the file at a temp path and let monkeypatch restore the globals afterwards.
    monkeypatch.setattr(yolo_inference, "ACTIVE_MODEL_FILE", tmp_path / "active_model.txt")
    for name in ("MODEL_PATH", "VIOLATION_CLASS_NAMES", "_inference"):
        monkeypatch.setattr(yolo_inference, name, getattr(yolo_inference, name))

    response = client.post("/settings/model?name=yolov8n.onnx")
    assert response.status_code == 200
    assert response.json()["model"] == "yolov8n.onnx"


# ─── Camera input: sources, connection test, saved profiles ──────────────────

import pytest

from routers import settings as settings_router


@pytest.fixture
def camera_env(tmp_path, monkeypatch):
    """Profiles go to a temp config and 'use' is recorded instead of reloading the real pipeline."""
    monkeypatch.setattr(settings_router, "CONFIG_PATH", tmp_path / "camera_config.json")
    applied = []
    monkeypatch.setattr(settings_router, "_apply_video_source", applied.append)
    return applied


def test_source_endpoint_accepts_an_rtsp_address_and_hides_its_password(camera_env):
    response = client.post("/settings/video/source", params={"path": "rtsp://admin:s3cret@192.168.1.10/ch1"})
    assert response.status_code == 200
    assert response.json()["kind"] == "rtsp" and "s3cret" not in response.text
    assert camera_env == ["rtsp://admin:s3cret@192.168.1.10/ch1"]          # the real address is what gets used


@pytest.mark.parametrize("bad", ["file:///etc/passwd", "concat:a.mp4|b.mp4", "ftp://host/x"])
def test_source_endpoint_rejects_unsupported_addresses(camera_env, bad):
    assert client.post("/settings/video/source", params={"path": bad}).status_code == 400
    assert camera_env == []


def test_status_endpoint_reports_the_live_source():
    body = client.get("/settings/video/status").json()
    assert "state" in body and "label" in body


def test_profiles_are_saved_listed_masked_and_used(camera_env):
    saved = client.put("/settings/camera-profiles", json={"profiles": [
        {"name": "Barangay CCTV", "url": "rtsp://admin:s3cret@192.168.1.10/ch1"},
        {"name": "Laptop B", "url": "rtsp://192.168.1.20:8554/cam1"},
    ]})
    assert saved.status_code == 200 and saved.json()["count"] == 2

    listed = client.get("/settings/camera-profiles")
    assert "s3cret" not in listed.text
    assert [(p["name"], p["kind"]) for p in listed.json()["profiles"]] == [("Barangay CCTV", "rtsp"), ("Laptop B", "rtsp")]

    used = client.post("/settings/camera-profiles/use", params={"name": "Barangay CCTV"})
    assert used.status_code == 200 and "s3cret" not in used.text
    assert camera_env == ["rtsp://admin:s3cret@192.168.1.10/ch1"]


def test_saving_a_masked_address_back_keeps_the_stored_password(camera_env):
    client.put("/settings/camera-profiles", json={"profiles": [{"name": "CCTV", "url": "rtsp://admin:s3cret@10.0.0.5/ch1"}]})
    masked = client.get("/settings/camera-profiles").json()["profiles"]          # what the dashboard holds
    client.put("/settings/camera-profiles", json={"profiles": masked})
    client.post("/settings/camera-profiles/use", params={"name": "CCTV"})
    assert camera_env == ["rtsp://admin:s3cret@10.0.0.5/ch1"]


def test_profiles_reject_bad_input(camera_env):
    assert client.put("/settings/camera-profiles", json={"profiles": [{"name": "x", "url": "file:///etc/passwd"}]}).status_code == 400
    assert client.put("/settings/camera-profiles", json={"profiles": [{"name": "", "url": "rtsp://h/x"}]}).status_code == 400
    assert client.post("/settings/camera-profiles/use", params={"name": "nope"}).status_code == 404


def test_connection_test_by_address_and_by_profile(camera_env, monkeypatch):
    tried = []
    monkeypatch.setattr(settings_router, "test_connection", lambda address: tried.append(address) or {"ok": True})
    client.put("/settings/camera-profiles", json={"profiles": [{"name": "Phone", "url": "rtsp://10.0.0.7:8080/h264"}]})
    assert client.post("/settings/video/test", params={"path": "rtsp://1.2.3.4/x"}).json() == {"ok": True}
    assert client.post("/settings/video/test", params={"name": "Phone"}).json() == {"ok": True}
    assert tried == ["rtsp://1.2.3.4/x", "rtsp://10.0.0.7:8080/h264"]


# ─── the chosen camera survives a backend restart ────────────────────────────────────────────

def read_cfg(path):
    import json
    return json.loads(path.read_text())


def test_a_plain_address_is_remembered_but_a_password_never_is(camera_env, tmp_path):
    client.post("/settings/video/source", params={"path": "rtsp://192.168.1.20:8554/cam1"})
    assert read_cfg(tmp_path / "camera_config.json")["active_source"] == {"url": "rtsp://192.168.1.20:8554/cam1"}
    client.post("/settings/video/source", params={"path": "rtsp://admin:s3cret@192.168.1.10/ch1"})
    assert "active_source" not in read_cfg(tmp_path / "camera_config.json")           # saved as a profile instead
    assert "s3cret" not in (tmp_path / "camera_config.json").read_text()


def test_a_profile_is_remembered_by_name_and_resolved_on_start(camera_env, tmp_path):
    from routers import stream
    client.put("/settings/camera-profiles", json={"profiles": [{"name": "Laptop B", "url": "rtsp://192.168.1.20:8554/cam1"}]})
    client.post("/settings/camera-profiles/use", params={"name": "Laptop B"})
    cfg = tmp_path / "camera_config.json"
    assert read_cfg(cfg)["active_source"] == {"profile": "Laptop B"}
    assert stream.saved_source(cfg) == "rtsp://192.168.1.20:8554/cam1"
    client.put("/settings/camera-profiles", json={"profiles": []})                      # the profile was deleted
    assert stream.saved_source(cfg) == stream.DEFAULT_SOURCE


def test_saved_source_falls_back_when_nothing_or_a_missing_file_was_saved(tmp_path):
    import json

    from routers import stream
    assert stream.saved_source(tmp_path / "nope.json") == stream.DEFAULT_SOURCE
    cfg = tmp_path / "c.json"
    cfg.write_text(json.dumps({"active_source": {"url": str(tmp_path / "gone.mp4")}}))
    assert stream.saved_source(cfg) == stream.DEFAULT_SOURCE                              # the file no longer exists
    clip = tmp_path / "clip.mp4"
    clip.write_bytes(b"x")
    cfg.write_text(json.dumps({"active_source": {"url": str(clip)}}))
    assert stream.saved_source(cfg) == str(clip)


def test_saving_zones_does_not_erase_the_saved_cameras(camera_env, tmp_path, monkeypatch):
    from routers import stream
    monkeypatch.setattr(stream, "reload_pipeline", lambda: None)
    client.put("/settings/camera-profiles", json={"profiles": [{"name": "Laptop B", "url": "rtsp://192.168.1.20:8554/cam1"}]})
    client.post("/settings/camera-profiles/use", params={"name": "Laptop B"})
    client.post("/settings/camera-config", json={"regions_of_interest": {"counterflow_zones": []}})
    saved = read_cfg(tmp_path / "camera_config.json")
    assert saved["camera_profiles"][0]["name"] == "Laptop B" and saved["active_source"] == {"profile": "Laptop B"}
    assert "regions_of_interest" in saved


# ─── the road the Live Monitor learns by itself ──────────────────────────────

def test_status_endpoint_carries_the_road_learner():
    body = client.get("/settings/video/status").json()
    assert {"state", "message", "progress_s", "found", "zones", "hints"} <= set(body["road"])
    assert client.get("/settings/video/road").json()["state"] == body["road"]["state"]


def test_relearn_and_forget_act_on_the_connected_camera(tmp_path, monkeypatch):
    from engine.live_calibrator import LiveCalibrator
    from routers import stream
    cal = LiveCalibrator(config_path=tmp_path / "camera_config.json")
    monkeypatch.setattr(stream, "road", cal)

    assert client.post("/settings/video/road/relearn").json()["ok"] is False     # no camera connected yet: nothing to do
    assert client.post("/settings/video/road/forget").json()["ok"] is False

    cal.attach("rtsp://cam/1")
    again = client.post("/settings/video/road/relearn").json()
    assert again["ok"] is True and again["road"]["state"] == "learning"
    gone = client.post("/settings/video/road/forget").json()
    assert gone["ok"] is True and gone["road"]["state"] == "off"
