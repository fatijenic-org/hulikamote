"""
The trim step of the Forensic Analyzer: only the chosen part of the video is analyzed (routers/forensic.py), the flow
pre-scan starts there too, and the dashboard finds frames by path instead of uploading the video.
Same tiny generated clip and fake pipeline as the stop tests: 30 frames at 10 fps, frame i is a flat grey of about i * 5.
"""
from types import SimpleNamespace

import cv2
import numpy as np
import pytest
from httpx import ASGITransport, AsyncClient

from engine.flow_prescan import prescan_flow
from tests.routers.test_forensic_stop import FakePipeline, FPS, FRAMES, env  # noqa: F401  (env is a fixture)


class Recording(FakePipeline):
    """Remembers every frame it was given: (number, time, grey level)."""
    seen: list = []

    def process_frame(self, frame, idx, timestamp=None):
        type(self).seen.append((idx, round(timestamp, 2), int(frame[0, 0, 0])))
        return frame, []


@pytest.fixture
def recorded(env, monkeypatch):  # noqa: F811
    Recording.seen = []
    monkeypatch.setattr(env.forensic, "DecoupledPipeline", Recording)
    return env


def grey_of(frame_number):
    return frame_number * 5          # what the generated clip holds in frame `frame_number` (0-based), give or take compression


def numbers(recorded_env):
    return [s[0] for s in Recording.seen]


def test_without_a_trim_every_frame_is_analyzed(recorded):
    recorded.go()
    assert numbers(recorded) == list(range(1, FRAMES + 1))
    assert Recording.seen[0][2] == pytest.approx(grey_of(0), abs=8)


def test_a_start_skips_the_earlier_part_and_counting_starts_again_at_one(recorded):
    recorded.go(trim_start=1.0)                                  # frame 10 at 10 fps
    assert numbers(recorded) == list(range(1, FRAMES - 10 + 1))
    first = Recording.seen[0]
    assert first[1] == pytest.approx(1 / FPS)                    # its time is counted from the chosen start
    assert first[2] == pytest.approx(grey_of(10), abs=8)         # and it really is frame 10


def test_a_start_and_an_end_analyze_only_what_is_between(recorded):
    recorded.go(trim_start=1.0, trim_end=2.0)
    assert numbers(recorded) == list(range(1, 11))
    assert Recording.seen[0][2] == pytest.approx(grey_of(10), abs=8)
    assert Recording.seen[-1][2] == pytest.approx(grey_of(19), abs=8)


def test_an_end_alone_stops_early(recorded):
    recorded.go(trim_end=1.5)
    assert numbers(recorded) == list(range(1, 16))
    assert Recording.seen[0][2] == pytest.approx(grey_of(0), abs=8)


def test_the_run_finishes_normally_and_its_video_is_just_the_chosen_part(recorded):
    task = recorded.go(trim_start=1.0, trim_end=2.0)
    assert task["status"] == "completed" and task["progress"] == 100.0
    clip = cv2.VideoCapture(str(recorded.run_dir / "output" / "evidence_replay.mp4"))
    try:
        assert int(clip.get(cv2.CAP_PROP_FRAME_COUNT)) == 10
    finally:
        clip.release()


@pytest.mark.parametrize("config", [{"trim_start": "x", "trim_end": "y"}, {"trim_start": 2.0, "trim_end": 1.0}, {"trim_start": -3, "trim_end": 0}])
def test_nonsense_trims_analyze_the_whole_video_instead_of_nothing(recorded, config):
    recorded.go(**config)
    assert len(Recording.seen) >= FRAMES - 20 and Recording.seen[0][0] == 1
    assert recorded.forensic.forensic_tasks["11111111-1111-1111-1111-111111111111"]["status"] == "completed"


# ─── the flow pre-scan starts at the chosen part too ─────────────────────────

class ScanPipeline:
    def __init__(self):
        self.learn_only = False
        self.flow = SimpleNamespace(summary=lambda w, h: {"w": w, "h": h})
        self.frames = []

    def process_frame(self, frame, idx, timestamp=None):
        self.frames.append((idx, round(timestamp, 2), int(frame[0, 0, 0])))

    def reset_tracking(self):
        pass


def test_the_flow_is_learned_from_the_chosen_part(env):  # noqa: F811
    video = env.run_dir / "input_video.mp4"
    whole, trimmed = ScanPipeline(), ScanPipeline()
    prescan_flow(whole, video, seconds=1.0, every=1)
    prescan_flow(trimmed, video, seconds=1.0, every=1, start_seconds=1.5)
    assert whole.frames[0][2] == pytest.approx(grey_of(0), abs=8)
    assert trimmed.frames[0][2] == pytest.approx(grey_of(15), abs=8)         # frame 15, not frame 0
    assert trimmed.frames[0][1] == pytest.approx(1 / FPS)                    # still counted from where it started
    assert len(trimmed.frames) == len(whole.frames) == 10


# ─── finding a frame by path (nothing is uploaded) ───────────────────────────

@pytest.fixture
def clip(tmp_path, monkeypatch):
    import engine.pipeline as pipeline_module
    monkeypatch.setattr(pipeline_module, "EVIDENCE_DIR", tmp_path / "evidence")
    path = tmp_path / "street.mp4"
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), FPS, (64, 48))
    for i in range(FRAMES):
        writer.write(np.full((48, 64, 3), i * 5, np.uint8))
    writer.release()
    return path, tmp_path / "evidence"


def stored_grey(evidence_dir, frame_url):
    name = frame_url.rsplit("/", 1)[-1]
    return int(cv2.imread(str(evidence_dir / "forensic" / "temp" / name))[0, 0, 0])


@pytest.mark.anyio
async def test_a_frame_comes_back_with_the_videos_speed_and_length(ac, clip):
    path, evidence = clip
    body = (await ac.get("/api/forensic/video-frame", params={"file_path": str(path)})).json()
    assert body["fps"] == pytest.approx(FPS) and body["frame_count"] == FRAMES and body["duration"] == pytest.approx(FRAMES / FPS)
    assert stored_grey(evidence, body["frame_url"]) == pytest.approx(grey_of(0), abs=8)


@pytest.mark.anyio
async def test_asking_for_a_later_moment_gives_that_frame(ac, clip):
    path, evidence = clip
    body = (await ac.get("/api/forensic/video-frame", params={"file_path": str(path), "seconds": 2.0})).json()
    assert stored_grey(evidence, body["frame_url"]) == pytest.approx(grey_of(20), abs=8)


@pytest.mark.anyio
async def test_a_moment_past_the_end_gives_the_last_frame_not_an_error(ac, clip):
    path, evidence = clip
    response = await ac.get("/api/forensic/video-frame", params={"file_path": str(path), "seconds": 500})
    assert response.status_code == 200
    assert stored_grey(evidence, response.json()["frame_url"]) == pytest.approx(grey_of(FRAMES - 1), abs=8)


@pytest.mark.anyio
async def test_only_existing_video_files_are_read(ac, clip, tmp_path):
    notes = tmp_path / "notes.txt"
    notes.write_text("hi")
    broken = tmp_path / "broken.mp4"
    broken.write_bytes(b"not a video")
    assert (await ac.get("/api/forensic/video-frame", params={"file_path": str(tmp_path / "gone.mp4")})).status_code == 404
    assert (await ac.get("/api/forensic/video-frame", params={"file_path": str(notes)})).status_code == 400
    assert (await ac.get("/api/forensic/video-frame", params={"file_path": str(broken)})).status_code == 400


@pytest.mark.anyio
async def test_a_phone_on_the_wifi_cannot_read_files_by_path(clip):
    from main import app
    async with AsyncClient(transport=ASGITransport(app=app, client=("192.168.68.50", 5555)), base_url="http://test") as phone:
        response = await phone.get("/api/forensic/video-frame", params={"file_path": str(clip[0])})
    assert response.status_code == 403
