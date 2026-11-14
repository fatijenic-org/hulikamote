"""The raw replay video is written in short pieces so a crash loses at most the open piece."""
import shutil
import subprocess

import cv2
import numpy as np
import pytest

from engine.segment_writer import SegmentedVideoWriter

FPS, SIZE = 10, (64, 48)


def frames_in(path) -> int:
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        return 0
    n = 0
    while cap.read()[0]:
        n += 1
    cap.release()
    return n


def write_frames(writer, count: int) -> None:
    for i in range(count):
        writer.write(np.full((SIZE[1], SIZE[0], 3), i % 255, np.uint8))


def test_a_piece_is_closed_every_few_seconds_and_each_piece_plays(tmp_path):
    closed = []
    w = SegmentedVideoWriter(tmp_path, FPS, SIZE, seconds=2, on_part_closed=lambda *a: closed.append(a))
    write_frames(w, 70)                                 # 20 frames per piece -> 20, 20, 20, 10
    w.release()
    assert [frames_in(p) for p in w.parts] == [20, 20, 20, 10]
    assert closed == [(1, 1, 20), (2, 21, 40), (3, 41, 60), (4, 61, 70)]


def test_after_a_crash_every_closed_piece_still_plays(tmp_path):
    w = SegmentedVideoWriter(tmp_path, FPS, SIZE, seconds=2)
    write_frames(w, 70)                                 # the run dies here: no release()
    assert [frames_in(p) for p in w.parts[:3]] == [20, 20, 20]
    assert frames_in(w.parts[3]) == 0                   # only the open piece is lost


@pytest.mark.skipif(shutil.which("ffmpeg") is None, reason="ffmpeg is not installed")
def test_ffmpeg_joins_the_pieces_into_one_video_with_every_frame(tmp_path):
    w = SegmentedVideoWriter(tmp_path, FPS, SIZE, seconds=2)
    write_frames(w, 70)
    w.release()
    joined = tmp_path / "joined.mp4"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *w.ffmpeg_input(), "-c:v", "libx264", "-preset", "ultrafast",
                    str(joined)], check=True)
    assert frames_in(joined) == 70


def test_removing_the_pieces_leaves_nothing_behind(tmp_path):
    w = SegmentedVideoWriter(tmp_path, FPS, SIZE, seconds=2)
    write_frames(w, 30)
    w.release()
    w.ffmpeg_input()
    w.remove_parts()
    assert list(tmp_path.iterdir()) == []


def test_a_video_shorter_than_one_piece_makes_one_piece(tmp_path):
    w = SegmentedVideoWriter(tmp_path, FPS, SIZE, seconds=30)
    write_frames(w, 15)
    w.release()
    assert len(w.parts) == 1 and frames_in(w.parts[0]) == 15
