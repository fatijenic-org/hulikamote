"""reid_ab.py: counting suspected ID jumps and merges (pure logic, plus the replay with a stand-in tracker; no GPU, no model)."""
import importlib.util
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "reid_ab.py"
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
spec = importlib.util.spec_from_file_location("reid_ab", SCRIPT)
ab = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ab)
from harvest_tool.pairs import look  # noqa: E402

RED, BLUE, GREEN = (30, 30, 200), (200, 40, 30), (40, 200, 40)
FPS = 30.0


def desc(bgr):
    return look(np.full((120, 60, 3), bgr, np.uint8))


def track(first, last, box_first, box_last=None, colour=RED, samples=None):
    frames = list(range(first, last + 1))
    return {"frames": frames, "boxes": [list(box_first)] + [list(box_last or box_first)] * (len(frames) - 1),
            "first": desc(colour), "last": desc(colour), "samples": samples or [desc(colour)] * 3}


def test_a_car_that_vanishes_as_a_look_alike_appears_close_by_is_a_suspected_jump():
    tracks = {
        1: track(0, 29, (100, 100, 200, 200)),                       # red car, 1 s
        2: track(40, 70, (110, 105, 210, 205)),                      # a red car appears 0.37 s later, right there
        3: track(5, 60, (600, 300, 700, 400), colour=BLUE),          # another car far away
    }
    r = ab.summarise(tracks, FPS)
    assert r["tracks"] == 3 and r["suspected_jumps"] == 1 and r["suspected_merges"] == 0 and r["suspected_errors"] == 1
    assert r["jumps"][0]["ended"] == 1 and r["jumps"][0]["started"] == 2


def test_a_jump_needs_all_of_time_place_size_and_look():
    base = track(0, 29, (100, 100, 200, 200))
    cases = {
        "too long ago": track(29 + int(3 * FPS), 150, (110, 105, 210, 205)),
        "far away": track(40, 70, (700, 500, 800, 600)),
        "much bigger": track(40, 70, (60, 60, 400, 400)),
        "other colour": track(40, 70, (110, 105, 210, 205), colour=GREEN),
        "before it ended": track(10, 70, (110, 105, 210, 205)),
    }
    for name, other in cases.items():
        assert ab.summarise({1: base, 2: other}, FPS)["suspected_jumps"] == 0, name


def test_one_old_track_is_matched_to_one_new_track_only():
    tracks = {1: track(0, 29, (100, 100, 200, 200)), 2: track(40, 70, (110, 105, 210, 205)), 3: track(41, 80, (105, 100, 205, 200))}
    assert ab.summarise(tracks, FPS)["suspected_jumps"] == 1


def test_a_track_whose_look_changes_abruptly_is_a_suspected_merge_but_a_steady_one_or_a_short_one_is_not():
    steady = track(0, 60, (100, 100, 200, 200), samples=[desc(RED)] * 4)
    swapped = track(0, 60, (400, 100, 500, 200), samples=[desc(RED), desc(RED), desc(BLUE), desc(BLUE)])
    too_few = track(0, 60, (700, 100, 800, 200), samples=[desc(RED), desc(BLUE)])
    r = ab.summarise({1: steady, 2: swapped, 3: too_few}, FPS)
    assert r["suspected_merges"] == 1 and r["merges"][0]["track"] == 2 and r["suspected_jumps"] == 0


def test_fragments_and_the_median_track_length_are_counted():
    tracks = {1: track(0, 9, (0, 0, 50, 50)), 2: track(100, 399, (200, 0, 250, 50)), 3: track(0, 59, (400, 0, 450, 50))}
    r = ab.summarise(tracks, FPS)
    assert r["short_tracks"] == 1 and r["median_track_seconds"] == 2.0         # 10 / 300 / 60 frames
    assert ab.summarise({}, FPS) == {"tracks": 0, "short_tracks": 0, "median_track_seconds": 0.0, "suspected_jumps": 0,
                                     "suspected_merges": 0, "suspected_errors": 0, "jumps": [], "merges": []}


class StandInTracker:
    """Gives every box the id of its column and remembers how often it was asked."""

    def __init__(self):
        self.calls = 0

    def update(self, boxes, conf, rgb):
        self.calls += 1
        assert rgb.shape[2] == 3 and boxes.shape[1] == 4 and len(conf) == len(boxes)
        out = [[int(cx - w / 2), int(cy - h / 2), int(cx + w / 2), int(cy + h / 2), 1 + int(cx // 200)] for cx, cy, w, h in boxes]
        return np.array(out, dtype=np.int32) if out else [], None


def test_the_replay_hands_boxes_to_the_tracker_as_the_app_does_and_skips_frames_with_no_vehicle(tmp_path):
    video = tmp_path / "clip.mp4"
    out = cv2.VideoWriter(str(video), cv2.VideoWriter_fourcc(*"mp4v"), 10, (320, 240))
    for i in range(12):
        out.write(np.full((240, 320, 3), 40 + i, np.uint8))
    out.release()
    clip = {"fps": 10.0, "size": [320, 240], "frames": [[[20, 20, 90, 90, 0.9]] if i not in (3, 4) else [] for i in range(12)]}
    tracker = StandInTracker()
    tracks = ab.track_video(video, clip, lambda: tracker, sample_every=4)
    assert tracker.calls == 10                                                    # frames 3 and 4 had no vehicle: not asked
    t = tracks[1]
    assert len(t["frames"]) == 10 and 3 not in t["frames"] and t["boxes"][0] == [20, 20, 90, 90]
    assert 2 <= len(t["samples"]) <= 4 and t["first"] is not None and t["last"] is not None
    r = ab.summarise(tracks, 10.0)
    assert r["tracks"] == 1 and r["suspected_errors"] == 0


def test_the_table_and_the_command_line():
    old = {"tracks": 40, "short_tracks": 9, "median_track_seconds": 2.5, "suspected_jumps": 7, "suspected_merges": 2, "suspected_errors": 9}
    new = dict(old, tracks=34, short_tracks=5, suspected_jumps=3, suspected_errors=5)
    text = ab.table(old, new)
    assert "suspected errors in all" in text and text.splitlines()[0].split() == ["old", "new"]
    assert text.splitlines()[-1].split()[-2:] == ["9", "5"]
    r = subprocess.run([sys.executable, str(SCRIPT), "--help"], capture_output=True, text=True, timeout=120)
    assert r.returncode == 0 and "--new" in r.stdout and "suspected" in r.stdout
