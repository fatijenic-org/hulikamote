"""clip_cutter.py - file names, ffmpeg commands, the background queue (with a stand-in ffmpeg) and one real cut."""
import json
import shutil
import subprocess
import threading
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

import clip_cutter as cc


def wait_until(condition, seconds=3.0):
    end = time.time() + seconds
    while time.time() < end:
        if condition():
            return True
        time.sleep(0.01)
    return False


# ─── names and commands ──────────────────────────────────────────────────────

def test_labels_become_safe_file_name_parts():
    assert cc.clean_label("  Red light / lane 2! ") == "Red-light-lane-2"
    assert cc.clean_label("../../etc") == "etc"
    assert cc.clean_label("x" * 100) == "x" * 40
    assert cc.clean_label("") == ""


@pytest.mark.parametrize("seconds,text", [(0, "00m00s"), (65.9, "01m05s"), (3599, "59m59s"), (3725, "1h02m05s")])
def test_times_in_file_names(seconds, text):
    assert cc.stamp(seconds) == text


def test_the_output_sits_next_to_the_video_and_never_replaces_a_file(tmp_path):
    source = tmp_path / "street.mp4"
    first = cc.output_path(source, None, "helmet", 65, 80)
    assert first == tmp_path / "street_helmet_01m05s-01m20s.mp4"
    first.write_bytes(b"x")
    assert cc.output_path(source, None, "helmet", 65, 80).name == "street_helmet_01m05s-01m20s-2.mp4"
    other = tmp_path / "out"
    assert cc.output_path(source, other, "", 0, 5) == other / "street_00m00s-00m05s.mp4"


def test_a_fast_cut_copies_and_an_exact_cut_re_encodes():
    fast = cc.build_command(Path("in.mp4"), Path("out.mp4"), 10, 25.5, exact=False)
    assert fast[fast.index("-ss") + 1] == "10.000" and fast[fast.index("-t") + 1] == "15.500"
    assert fast[fast.index("-c") + 1] == "copy" and "libx264" not in fast
    exact = cc.build_command(Path("in.mp4"), Path("out.mp4"), 10, 25.5, exact=True)
    assert "libx264" in exact and "copy" not in exact
    assert exact[-1] == "out.mp4" and fast[-1] == "out.mp4"


@pytest.mark.parametrize("line,expected", [
    ("out_time_us=5000000\n", 0.5), ("out_time_ms=10000000", 1.0), ("out_time_us=99000000", 1.0),
    ("progress=continue", None), ("frame=12", None), ("out_time_us=N/A", None),
])
def test_progress_is_read_from_ffmpeg_output(line, expected):
    assert cc.progress_from_line(line, duration=10) == expected


# ─── probing ─────────────────────────────────────────────────────────────────

def fake_probe_run(payload=None, returncode=0):
    def run(cmd, **_):
        return SimpleNamespace(stdout=json.dumps(payload if payload is not None else {}), returncode=returncode)
    return run


def test_probe_reads_length_speed_and_size(tmp_path):
    payload = {"streams": [{"width": 1920, "height": 1080, "r_frame_rate": "30000/1001", "duration": "125.5"}]}
    info = cc.probe(tmp_path / "a.mp4", run=fake_probe_run(payload))
    assert info == {"duration": 125.5, "fps": 29.97, "width": 1920, "height": 1080}


def test_probe_falls_back_to_the_container_length(tmp_path):
    payload = {"streams": [{"width": 640, "height": 480, "r_frame_rate": "25/1"}], "format": {"duration": "60.0"}}
    assert cc.probe(tmp_path / "a.mp4", run=fake_probe_run(payload))["duration"] == 60.0


@pytest.mark.parametrize("payload", [{}, {"streams": []}, {"streams": [{"width": 1, "height": 1, "r_frame_rate": "0/0"}]}])
def test_probe_refuses_what_is_not_a_readable_video(tmp_path, payload):
    with pytest.raises(ValueError, match="cannot read"):
        cc.probe(tmp_path / "a.mp4", run=fake_probe_run(payload))


# ─── the queue, with a stand-in ffmpeg ───────────────────────────────────────

class FakeProc:
    """Stands in for an ffmpeg process: reports progress, then succeeds or fails; can be held until released or stopped."""

    def __init__(self, cmd, code=0, error="", hold=None, writes=True):
        self.out = Path(cmd[-1])
        self.code, self.error, self.hold, self.stopped = code, error, hold, threading.Event()
        self.stderr = SimpleNamespace(read=lambda: self.error)
        if writes:
            self.out.write_bytes(b"clip")
        self.stdout = self._lines()

    def _lines(self):
        yield "out_time_us=1000000\n"
        if self.hold is not None:
            while not (self.hold.is_set() or self.stopped.is_set()):
                time.sleep(0.005)
        if not self.stopped.is_set():
            yield "out_time_us=2000000\n"
            yield "progress=end\n"

    def wait(self):
        return 143 if self.stopped.is_set() else self.code

    def terminate(self):
        self.stopped.set()


def manager_with(factory, workers=2):
    return cc.JobManager(workers=workers, popen=lambda cmd, **_: factory(cmd))


def clips(*spans):
    return [{"start": s, "end": e, "label": f"c{i}"} for i, (s, e) in enumerate(spans, 1)]


def test_a_finished_cut_is_done_and_its_file_exists(tmp_path):
    manager = manager_with(lambda cmd: FakeProc(cmd))
    [job] = manager.submit(tmp_path / "v.mp4", clips((0, 2)), exact=False, out_dir=None)
    assert wait_until(lambda: manager.get(job.id)["status"] == "done")
    done = manager.get(job.id)
    assert done["progress"] == 1.0 and Path(done["output"]).exists() and done["finished_at"] > 0


def test_a_failed_cut_reports_why_and_leaves_no_half_file(tmp_path):
    manager = manager_with(lambda cmd: FakeProc(cmd, code=1, error="Invalid data found when processing input"))
    [job] = manager.submit(tmp_path / "v.mp4", clips((0, 2)), exact=False, out_dir=None)
    assert wait_until(lambda: manager.get(job.id)["status"] == "failed")
    failed = manager.get(job.id)
    assert "Invalid data" in failed["error"] and not Path(failed["output"]).exists()


def test_ffmpeg_missing_is_a_failed_job_not_a_crash(tmp_path):
    def no_ffmpeg(cmd, **_):
        raise FileNotFoundError("ffmpeg")
    manager = cc.JobManager(popen=no_ffmpeg)
    [job] = manager.submit(tmp_path / "v.mp4", clips((0, 2)), exact=False, out_dir=None)
    assert wait_until(lambda: manager.get(job.id)["status"] == "failed")
    assert "Could not start ffmpeg" in manager.get(job.id)["error"]


def test_each_clip_gets_its_own_job_and_its_own_file(tmp_path):
    manager = manager_with(lambda cmd: FakeProc(cmd))
    jobs = manager.submit(tmp_path / "v.mp4", clips((0, 2), (0, 2), (5, 9)), exact=False, out_dir=None)
    assert len({j.output for j in jobs}) == 3                                  # same range twice still gets two names
    assert wait_until(lambda: all(j["status"] == "done" for j in manager.jobs()))
    assert all(Path(j.output).exists() for j in jobs)


def test_two_cuts_run_at_the_same_time_and_the_rest_wait(tmp_path):
    release, running, peak = threading.Event(), set(), []
    lock = threading.Lock()

    def factory(cmd):
        with lock:
            running.add(cmd[-1])
            peak.append(len(running))
        proc = FakeProc(cmd, hold=release)
        original = proc.wait
        proc.wait = lambda: (running.discard(cmd[-1]), original())[1]
        return proc

    manager = manager_with(factory, workers=2)
    manager.submit(tmp_path / "v.mp4", clips((0, 2), (3, 5), (6, 8)), exact=False, out_dir=None)
    assert wait_until(lambda: sum(j["status"] == "running" for j in manager.jobs()) == 2)
    assert sum(j["status"] == "queued" for j in manager.jobs()) == 1           # the third is waiting its turn
    release.set()
    assert wait_until(lambda: all(j["status"] == "done" for j in manager.jobs()))
    assert max(peak) == 2


def test_a_waiting_job_can_be_cancelled_and_never_runs(tmp_path):
    release, started = threading.Event(), []

    def factory(cmd):
        started.append(cmd[-1])
        return FakeProc(cmd, hold=release)

    manager = manager_with(factory, workers=1)
    first, second = manager.submit(tmp_path / "v.mp4", clips((0, 2), (3, 5)), exact=False, out_dir=None)
    assert wait_until(lambda: manager.get(first.id)["status"] == "running")
    assert manager.cancel(second.id) and manager.get(second.id)["status"] == "cancelled"
    release.set()
    assert wait_until(lambda: manager.get(first.id)["status"] == "done")
    time.sleep(0.05)
    assert started == [first.output]                                           # the cancelled one was never started


def test_a_running_job_can_be_stopped_and_its_partial_file_is_removed(tmp_path):
    manager = manager_with(lambda cmd: FakeProc(cmd, hold=threading.Event()))
    [job] = manager.submit(tmp_path / "v.mp4", clips((0, 2)), exact=False, out_dir=None)
    assert wait_until(lambda: manager.get(job.id)["status"] == "running" and Path(job.output).exists())
    assert manager.cancel(job.id)
    assert wait_until(lambda: not Path(job.output).exists())
    assert manager.get(job.id)["status"] == "cancelled"


def test_finished_jobs_cannot_be_cancelled_and_can_be_cleared(tmp_path):
    manager = manager_with(lambda cmd: FakeProc(cmd))
    [job] = manager.submit(tmp_path / "v.mp4", clips((0, 2)), exact=False, out_dir=None)
    assert wait_until(lambda: manager.get(job.id)["status"] == "done")
    assert manager.cancel(job.id) is False and manager.cancel("nope") is False
    assert manager.clear_finished() == 1 and manager.jobs() == []
    assert Path(job.output).exists()                                           # only the list is cleared, not the file


# ─── one real cut ────────────────────────────────────────────────────────────

@pytest.mark.skipif(not (shutil.which("ffmpeg") and shutil.which("ffprobe")), reason="ffmpeg is not installed")
def test_a_real_video_is_cut_fast_and_exactly(tmp_path):
    source = tmp_path / "test.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=25",
                    "-f", "lavfi", "-i", "sine=frequency=440", "-t", "8", "-g", "25", "-c:v", "libx264", "-c:a", "aac",
                    "-shortest", str(source)], check=True)
    assert 7.5 < cc.probe(source)["duration"] < 8.5

    manager = cc.JobManager()
    fast, exact = manager.submit(source, clips((2, 5)), exact=False, out_dir=None) + manager.submit(source, clips((2, 5)), exact=True, out_dir=tmp_path / "exact")
    assert wait_until(lambda: all(j["status"] in ("done", "failed") for j in manager.jobs()), seconds=60)
    for job in (fast, exact):
        assert manager.get(job.id)["status"] == "done", manager.get(job.id)["error"]
    assert 2.5 < cc.probe(Path(fast.output))["duration"] < 3.6                 # keyframes every second: within about a second
    assert 2.8 < cc.probe(Path(exact.output))["duration"] < 3.2                # exact
    picture = cc.filmstrip(source, 8, tmp_path / "cache")
    assert picture.exists() and picture.stat().st_size > 1000
