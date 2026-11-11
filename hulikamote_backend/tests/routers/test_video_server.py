"""routers/settings.py /video-server - tells the dashboard whether the video relay (MediaMTX) is up."""
import pytest


@pytest.mark.anyio
async def test_synced_pictures_need_no_relay(ac, monkeypatch):
    monkeypatch.setattr("routers.stream.PICTURE_MODE", "synced")
    monkeypatch.setattr("routers.settings.server_status", lambda: pytest.fail("the relay must not be asked about"))
    assert (await ac.get("/settings/video-server")).json() == {"ready": True, "message": "", "mode": "synced"}


@pytest.mark.anyio
async def test_the_dashboard_is_told_when_the_relay_is_up(ac, monkeypatch):
    monkeypatch.setattr("routers.stream.PICTURE_MODE", "relay")
    monkeypatch.setattr("routers.settings.server_status", lambda: (True, ""))
    assert (await ac.get("/settings/video-server")).json() == {"ready": True, "message": "", "mode": "relay"}


@pytest.mark.anyio
async def test_the_dashboard_is_told_why_when_it_is_not(ac, monkeypatch):
    monkeypatch.setattr("routers.stream.PICTURE_MODE", "relay")
    monkeypatch.setattr("routers.settings.server_status", lambda: (False, "The video relay (MediaMTX) is not running."))
    body = (await ac.get("/settings/video-server")).json()
    assert body["ready"] is False and "MediaMTX" in body["message"]
