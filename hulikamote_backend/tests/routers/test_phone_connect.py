"""POST /settings/phone/connect - "Connect phone": found -> saved as the camera "Phone" and used; not found -> a plain answer."""
import json

import pytest
from fastapi.testclient import TestClient

from engine import phone_link
from main import app
from routers import settings as settings_router

client = TestClient(app)


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setattr(settings_router, "CONFIG_PATH", tmp_path / "camera_config.json")
    applied = []
    monkeypatch.setattr(settings_router, "_apply_video_source", applied.append)
    return applied, tmp_path / "camera_config.json"


def test_a_found_phone_becomes_the_saved_camera_and_the_live_source(env, monkeypatch):
    applied, cfg = env
    monkeypatch.setattr(phone_link, "connect", lambda: {"ok": True, "via": "wifi", "host": "192.168.1.77", "url": "http://192.168.1.77:8080/video", "message": "found", "steps": []})
    body = client.post("/settings/phone/connect").json()
    assert body["ok"] and body["url"] == "http://192.168.1.77:8080/video" and body["label"]
    assert applied == ["http://192.168.1.77:8080/video"]
    saved = json.loads(cfg.read_text(encoding="utf-8"))
    assert saved["camera_profiles"] == [{"name": "Phone", "url": "http://192.168.1.77:8080/video"}]
    assert saved["active_source"] == {"profile": "Phone"}


def test_connecting_again_replaces_the_old_address_and_keeps_other_cameras(env, monkeypatch):
    applied, cfg = env
    client.put("/settings/camera-profiles", json={"profiles": [{"name": "CCTV", "url": "rtsp://10.0.0.5/ch1"}, {"name": "Phone", "url": "http://192.168.1.10:8080/video"}]})
    monkeypatch.setattr(phone_link, "connect", lambda: {"ok": True, "via": "tethering", "host": "192.168.42.129", "url": "http://192.168.42.129:8080/video", "message": "found", "steps": []})
    client.post("/settings/phone/connect")
    profiles = json.loads(cfg.read_text(encoding="utf-8"))["camera_profiles"]
    assert profiles == [{"name": "CCTV", "url": "rtsp://10.0.0.5/ch1"}, {"name": "Phone", "url": "http://192.168.42.129:8080/video"}]


def test_no_phone_is_a_normal_answer_that_changes_nothing(env, monkeypatch):
    applied, cfg = env
    monkeypatch.setattr(phone_link, "connect", lambda: {"ok": False, "message": "No phone found.", "steps": [{"text": "x", "ok": False}]})
    response = client.post("/settings/phone/connect")
    assert response.status_code == 200 and response.json()["ok"] is False and response.json()["message"] == "No phone found."
    assert applied == [] and not cfg.exists()
