"""The time of a video is read once, in the background, as soon as the video is picked; everything later reuses the answer."""
import shutil
import threading
import time
from datetime import datetime

from engine import video_clock as vc
from tests.engine.test_video_clock import make_video


def count_reads(monkeypatch, gate=None):
    calls = []

    def read(path, name, reader=None, use_screen=True):
        calls.append(path)
        if gate is not None:
            gate.wait(5)
        return vc.FileClock("screen", datetime(2026, 11, 5, 7, 40), "Read from the clock.")

    monkeypatch.setattr(vc, "_read_file_clock", read)
    return calls


def test_the_time_is_read_once_for_every_later_question(monkeypatch, tmp_path):
    calls = count_reads(monkeypatch)
    video = make_video(tmp_path / "cam.mp4", seconds=2)
    first = vc.resolve_clock(video)
    second = vc.resolve_clock(video, trim_start=30)                       # a trim only moves the start
    assert len(calls) == 1
    assert first.start == datetime(2026, 11, 5, 7, 40) and second.start == datetime(2026, 11, 5, 7, 40, 30)


def test_the_uploaded_copy_of_the_picked_video_finds_the_answer(monkeypatch, tmp_path):
    calls = count_reads(monkeypatch)
    video = make_video(tmp_path / "cam.mp4", seconds=2)
    vc.resolve_clock(video)
    (tmp_path / "up").mkdir()
    copy = tmp_path / "up" / "input_video.mp4"
    shutil.copyfile(video, copy)                                          # what /upload makes: another path, the same bytes
    assert vc.resolve_clock(copy, name="cam.mp4").start == datetime(2026, 11, 5, 7, 40)
    assert len(calls) == 1


def test_look_ahead_returns_at_once_and_a_question_waits_for_that_same_look(monkeypatch, tmp_path):
    gate = threading.Event()
    calls = count_reads(monkeypatch, gate)
    video = make_video(tmp_path / "cam.mp4", seconds=2)
    began = time.monotonic()
    vc.look_ahead(video)
    vc.look_ahead(video)                                                  # a second call starts nothing new
    assert time.monotonic() - began < 1.0                                 # nobody waited
    answer = []
    asker = threading.Thread(target=lambda: answer.append(vc.resolve_clock(video)))
    asker.start()
    time.sleep(0.2)
    assert asker.is_alive() and len(calls) == 1                           # it joined the look that is running
    gate.set()
    asker.join(5)
    assert answer and answer[0].start == datetime(2026, 11, 5, 7, 40) and len(calls) == 1


def test_a_typed_time_never_waits_for_the_video(monkeypatch, tmp_path):
    calls = count_reads(monkeypatch)
    info = vc.resolve_clock(make_video(tmp_path / "cam.mp4", seconds=2), start_text="9:15")
    assert info.source == "operator" and not calls


def test_look_ahead_ignores_a_file_that_is_not_there(tmp_path):
    vc.look_ahead(tmp_path / "missing.mp4")                               # no error, nothing started
