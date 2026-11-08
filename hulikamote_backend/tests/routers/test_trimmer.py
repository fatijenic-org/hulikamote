"""routers/trimmer.py - the video trimmer's endpoints: probing, queuing cuts, watching and stopping them."""
import time
from pathlib import Path
from types import SimpleNamespace

import pytest
from httpx import ASGITransport, AsyncClient

import clip_cutter
from routers import trimmer as router


class QuickProc:
    def __init__(self, cmd):
        Path(cmd[-1]).write_bytes(b"clip")
        self.stdout, self.stderr = iter(["progress=end\n"]), SimpleNamespace(read=lambda: "")

    def wait(self):
        return 0

    def terminate(self):
        pass


@pytest.fixture
def video(tmp_path, monkeypatch):
    """A pretend 60 s video, and a job manager whose ffmpeg just writes the output file."""
    path = tmp_path / "street.mp4"
    path.write_bytes(b"not really a video")
    monkeypatch.setattr(clip_cutter, "probe", lambda p, run=None: {"duration": 60.0, "fps": 25.0, "width": 640, "height": 480})
    monkeypatch.setattr(router, "_manager", clip_cutter.JobManager(popen=lambda cmd, **_: QuickProc(cmd)))
    return path


def body(path, *spans, **extra):
    return {"file_path": str(path), "clips": [{"start": s, "end": e, "label": f"c{i}"} for i, (s, e) in enumerate(spans, 1)], **extra}


async def settled(ac):
    for _ in range(300):
        jobs = (await ac.get("/api/trimmer/jobs")).json()["jobs"]
        if jobs and all(j["status"] in ("done", "failed", "cancelled") for j in jobs):
            return jobs
        time.sleep(0.01)
    raise AssertionError("jobs did not settle")


@pytest.mark.anyio
async def test_probe_gives_the_length_of_the_video(ac, video):
    response = await ac.get("/api/trimmer/probe", params={"file_path": str(video)})
    assert response.status_code == 200 and response.json()["duration"] == 60.0


@pytest.mark.anyio
async def test_only_existing_video_files_are_accepted(ac, video, tmp_path):
    notes = tmp_path / "notes.txt"
    notes.write_text("hi")
    assert (await ac.get("/api/trimmer/probe", params={"file_path": str(tmp_path / "missing.mp4")})).status_code == 404
    assert (await ac.get("/api/trimmer/probe", params={"file_path": str(notes)})).status_code == 400
    assert (await ac.post("/api/trimmer/jobs", json=body(notes, (0, 5)))).status_code == 400


@pytest.mark.anyio
async def test_several_clips_become_several_jobs_with_their_own_files(ac, video):
    response = await ac.post("/api/trimmer/jobs", json=body(video, (0, 10), (10, 20), (30, 45.5)))
    assert response.status_code == 202
    jobs = response.json()["jobs"]
    assert [(j["start"], j["end"]) for j in jobs] == [(0, 10), (10, 20), (30, 45.5)]
    assert len({j["output"] for j in jobs}) == 3
    done = await settled(ac)
    assert [j["status"] for j in done] == ["done"] * 3 and all(Path(j["output"]).exists() for j in done)
    assert (await ac.post("/api/trimmer/jobs/clear")).json() == {"cleared": 3}
    assert (await ac.get("/api/trimmer/jobs")).json() == {"jobs": []}


@pytest.mark.anyio
async def test_the_output_folder_is_used_and_created(ac, video, tmp_path):
    folder = tmp_path / "exports" / "today"
    await ac.post("/api/trimmer/jobs", json=body(video, (0, 5), output_dir=str(folder)))
    [job] = await settled(ac)
    assert Path(job["output"]).parent == folder and Path(job["output"]).exists()
    await ac.post("/api/trimmer/jobs/clear")


@pytest.mark.anyio
@pytest.mark.parametrize("spans,reason", [
    ([(5, 5)], "at least"), ([(-1, 5)], "start at 0"), ([(0, 0.05)], "at least"), ([(50, 90)], "ends after the video"), ([], "between 1 and"),
])
async def test_clips_that_make_no_sense_are_refused_before_anything_starts(ac, video, spans, reason):
    response = await ac.post("/api/trimmer/jobs", json=body(video, *spans))
    assert response.status_code == 400 and reason in response.json()["detail"]
    assert (await ac.get("/api/trimmer/jobs")).json() == {"jobs": []}


@pytest.mark.anyio
async def test_a_video_ffprobe_cannot_read_is_refused(ac, video, monkeypatch):
    def unreadable(path, run=None):
        raise ValueError("ffmpeg cannot read this file (no video found)")
    monkeypatch.setattr(clip_cutter, "probe", unreadable)
    response = await ac.post("/api/trimmer/jobs", json=body(video, (0, 5)))
    assert response.status_code == 400 and "cannot read" in response.json()["detail"]


@pytest.mark.anyio
async def test_cancelling_an_unknown_or_finished_job_is_a_404(ac, video):
    await ac.post("/api/trimmer/jobs", json=body(video, (0, 5)))
    [job] = await settled(ac)
    assert (await ac.delete(f"/api/trimmer/jobs/{job['id']}")).status_code == 404
    assert (await ac.delete("/api/trimmer/jobs/nope")).status_code == 404
    await ac.post("/api/trimmer/jobs/clear")


@pytest.mark.anyio
async def test_the_filmstrip_is_a_jpeg(ac, video, tmp_path, monkeypatch):
    picture = tmp_path / "strip.jpg"
    picture.write_bytes(b"\xff\xd8jpeg")
    monkeypatch.setattr(clip_cutter, "filmstrip", lambda path, count, cache: picture)
    response = await ac.get("/api/trimmer/filmstrip", params={"file_path": str(video), "count": 12})
    assert response.status_code == 200 and response.headers["content-type"] == "image/jpeg"


@pytest.mark.anyio
async def test_a_phone_on_the_wifi_cannot_use_the_video_tools(video):
    from main import app
    async with AsyncClient(transport=ASGITransport(app=app, client=("192.168.68.50", 5555)), base_url="http://test") as phone:
        for call in (phone.get("/api/trimmer/jobs"), phone.post("/api/trimmer/jobs", json=body(video, (0, 5)))):
            assert (await call).status_code == 403
