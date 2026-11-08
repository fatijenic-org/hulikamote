import json


from fastapi.testclient import TestClient
from main import app
from routers import stream

client = TestClient(app)


def test_websocket_video_feed_returns_json_frame(monkeypatch):
    """WS must return at least one valid JSON frame with expected keys."""
    # the bundled sample video, not whatever camera the operator saved in camera_config.json (it may be offline)
    monkeypatch.setattr(stream, "VIDEO_SOURCE", stream.DEFAULT_SOURCE)
    with client.websocket_connect("/ws/video-feed") as ws:
        raw = ws.receive_text()

    frame = json.loads(raw)
    assert frame["type"] == "frame"
    assert "detections" in frame
    assert "timestamp" in frame
    assert isinstance(frame["detections"], list)


