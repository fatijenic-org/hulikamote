"""
The time of day of a video (engine/video_clock.py): the ladder of sources, ban hours, and the clocks the pipeline reads.
Real tiny videos are made on the fly; the screen-clock logic is tested with a scripted reader, and once with the real OCR.
"""
import shutil
import subprocess
from datetime import datetime, timedelta

import cv2
import numpy as np
import pytest

from engine import video_clock as vc


def make_video(path, seconds=10, fps=10, size=(640, 360), brightness=0, draw=None):
    """A plain video. `draw(frame, second)` can paint on each frame (e.g. a clock)."""
    writer = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), fps, size)
    for i in range(int(seconds * fps)):
        frame = np.full((size[1], size[0], 3), brightness, dtype=np.uint8)
        if draw:
            draw(frame, i / fps)
        writer.write(frame)
    writer.release()
    return path


def tag_video(src, dst, creation_time):
    subprocess.run(["ffmpeg", "-y", "-v", "quiet", "-i", str(src), "-c", "copy", "-metadata", f"creation_time={creation_time}", str(dst)],
                   check=True)
    return dst


class Script:
    """A reader that "reads" a scripted text from the first corner of every picture and nothing from the other three."""

    def __init__(self, texts):
        self.texts, self.calls = list(texts), 0

    def readtext(self, crop, detail=0, allowlist=None, **kwargs):
        i, self.calls = self.calls, self.calls + 1
        if i % 4 == 0 and self.texts:
            return [self.texts.pop(0)]
        return []


# ─── ban hours ──────────────────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("text,minutes", [("06:00", 360), ("6", 360), ("6:30", 390), ("6 AM", 360), ("4:30 pm", 990),
                                          ("12 AM", 0), ("12 PM", 720), ("18.15", 1095), ("24:00", 1440)])
def test_times_of_day_are_read_in_every_usual_way(text, minutes):
    assert vc.parse_minutes(text) == minutes


@pytest.mark.parametrize("text", ["", "abc", "25:00", "6:99", "13 PM", "0 AM", None, "24:30"])
def test_things_that_are_not_a_time_of_day_are_refused(text):
    assert vc.parse_minutes(text) is None


def test_windows_drop_what_cannot_be_used_and_keep_the_rest():
    raw = [["06:00", "09:00"], ["16:00", "19:00"], ["junk", "09:00"], ["07:00", "07:00"], ["only one"], None]
    assert vc.parse_windows(raw) == [(360, 540), (960, 1140)]
    assert vc.parse_windows(None) == [] and vc.parse_windows([]) == []


def test_a_time_is_inside_a_window_from_its_start_up_to_but_not_including_its_end():
    w = vc.parse_windows([["06:00", "09:00"], ["16:00", "19:00"]])
    day = datetime(2026, 11, 5)
    inside = [day.replace(hour=6), day.replace(hour=8, minute=59), day.replace(hour=16, minute=30), day.replace(hour=18, minute=59)]
    outside = [day.replace(hour=5, minute=59), day.replace(hour=9), day.replace(hour=12), day.replace(hour=19), day.replace(hour=23)]
    assert all(vc.in_windows(m, w) for m in inside)
    assert not any(vc.in_windows(m, w) for m in outside)


def test_a_window_can_run_past_midnight():
    w = vc.parse_windows([["22:00", "05:00"]])
    day = datetime(2026, 11, 5)
    assert vc.in_windows(day.replace(hour=23), w) and vc.in_windows(day.replace(hour=2), w)
    assert not vc.in_windows(day.replace(hour=5), w) and not vc.in_windows(day.replace(hour=12), w)


def test_windows_are_described_in_plain_words():
    assert vc.describe_windows([["06:00", "09:00"], ["16:00", "19:00"]]) == "6:00 AM-9:00 AM and 4:00 PM-7:00 PM"
    assert vc.describe_windows([]) == ""


# ─── reading a time from text ───────────────────────────────────────────────────────────────────────────

def test_a_screen_clock_with_a_date_is_read():
    moment, seconds = vc.parse_clock_text("2026-11-05 07:42:13")
    assert moment == datetime(2026, 11, 5, 7, 42, 13) and seconds is True


def test_a_12_hour_screen_clock_is_read():
    assert vc.parse_clock_text("11/05/2026 7:42:13 PM")[0] == datetime(2026, 11, 5, 19, 42, 13)
    assert vc.parse_clock_text("2026-11-05 12:05:00 AM")[0] == datetime(2026, 11, 5, 0, 5, 0)


def test_the_usual_ocr_slips_are_forgiven():
    assert vc.parse_clock_text("2026-11-05 O7:42:13")[0] == datetime(2026, 11, 5, 7, 42, 13)    # the letter O for zero
    assert vc.parse_clock_text("2026-11-05 07.42.13")[0] == datetime(2026, 11, 5, 7, 42, 13)    # dots for colons
    assert vc.parse_clock_text("2026-11-05 07;42;13")[0] == datetime(2026, 11, 5, 7, 42, 13)


def test_a_clock_without_seconds_is_read_and_said_to_have_none():
    moment, seconds = vc.parse_clock_text("2026-11-05 07:42")
    assert moment == datetime(2026, 11, 5, 7, 42) and seconds is False


def test_a_day_first_date_is_read_when_it_can_only_be_that():
    assert vc.parse_clock_text("25/11/2026 07:42:13")[0] == datetime(2026, 11, 25, 7, 42, 13)


def test_text_that_is_not_a_clock_is_refused():
    for text in ["", "CAM 01", "25:99:00", "2026-11-05 07:99:00", "12345"]:
        assert vc.parse_clock_text(text) is None, text


def test_a_missing_date_is_taken_from_today():
    today = datetime(2026, 12, 24, 9, 0)
    assert vc.parse_clock_text("07:42:13", today)[0] == datetime(2026, 12, 24, 7, 42, 13)


def test_what_the_operator_types_is_understood():
    today = datetime(2026, 11, 5, 15, 0)
    assert vc.start_from_text("7:40", today) == datetime(2026, 11, 5, 7, 40)
    assert vc.start_from_text("7:40 AM", today) == datetime(2026, 11, 5, 7, 40)
    assert vc.start_from_text("2026-11-03 07:40", today) == datetime(2026, 11, 3, 7, 40)
    assert vc.start_from_text("2026-11-03T07:40:00", today) == datetime(2026, 11, 3, 7, 40)
    assert vc.start_from_text("2026-11-03T00:40:00Z", today) == datetime(2026, 11, 3, 8, 40)      # UTC -> Philippine time
    assert vc.start_from_text("", today) is None and vc.start_from_text("morning", today) is None and vc.start_from_text(None) is None


@pytest.mark.parametrize("name", ["20261105_074000.mp4", "REC_20261105-074000.avi", "2026-11-05 07-40-00.mp4", "cam1_2026_11_05_07_40_00.mkv"])
def test_a_time_in_the_file_name_is_read(name):
    assert vc.start_from_filename(name) == datetime(2026, 11, 5, 7, 40, 0)


@pytest.mark.parametrize("name", ["street.mp4", "IMG_1234.mp4", "20261305_074000.mp4", "19701231_235959.mp4", "", None])
def test_a_file_name_without_a_real_time_gives_none(name):
    assert vc.start_from_filename(name) is None


# ─── the clock objects ──────────────────────────────────────────────────────────────────────────────────

def test_a_clock_adds_the_seconds_into_the_video_to_its_start():
    clock = vc.ClockInfo(start=datetime(2026, 11, 5, 7, 59, 30), source="metadata", confirmed=True)
    assert clock.at(0) == datetime(2026, 11, 5, 7, 59, 30)
    assert clock.at(45.5) == datetime(2026, 11, 5, 8, 0, 15, 500000)
    assert vc.ClockInfo(start=None).at(10) is None


def test_a_clock_survives_being_saved_in_the_run_config():
    clock = vc.ClockInfo(start=datetime(2026, 11, 5, 7, 40), source="screen", confirmed=True, note="n", daylight=None)
    again = vc.ClockInfo.from_dict(clock.to_dict())
    assert again == clock
    assert clock.to_dict()["label"] == "read from the clock in the picture"
    assert vc.ClockInfo.from_dict(None) is None and vc.ClockInfo.from_dict({}) is None


def test_a_ticket_gets_the_time_of_its_first_photo_and_where_it_came_from():
    clock = vc.ClockInfo(start=datetime(2026, 11, 5, 7, 59, 30), source="operator", confirmed=True).to_dict()
    assert vc.ticket_time(clock, 45) == {"at": "2026-11-05T08:00:15", "source": "operator",
                                        "label": "typed by the operator", "confirmed": True, "start": "2026-11-05T07:59:30"}
    assert vc.ticket_time(vc.ClockInfo(start=None, source="estimate").to_dict(), 5) is None      # no real time: no time on the ticket
    assert vc.ticket_time(None, 5) is None and vc.ticket_time(clock, None) is None


def test_the_live_clock_is_now_and_a_pretend_clock_runs_from_its_start():
    assert abs((vc.WallClock().at(123) - vc.now_ph()).total_seconds()) < 2
    pretend = vc.OffsetClock(datetime(2026, 11, 5, 7, 30))
    assert 0 <= (pretend.at(999) - datetime(2026, 11, 5, 7, 30)).total_seconds() < 2          # the seconds passed in are ignored


# ─── the video's own information ────────────────────────────────────────────────────────────────────────

needs_ffmpeg = pytest.mark.skipif(not (shutil.which("ffmpeg") and shutil.which("ffprobe")), reason="ffmpeg is not installed")


@needs_ffmpeg
def test_the_creation_tag_is_read_as_utc_and_shown_in_philippine_time(tmp_path):
    plain = make_video(tmp_path / "plain.mp4", seconds=2)
    tagged = tag_video(plain, tmp_path / "tagged.mp4", "2026-11-05T01:40:00.000000Z")
    assert vc.start_from_metadata(tagged) == datetime(2026, 11, 5, 9, 40)


@needs_ffmpeg
def test_a_clock_that_was_never_set_is_not_believed(tmp_path):
    plain = make_video(tmp_path / "plain.mp4", seconds=2)
    for bad in ("1970-01-01T00:00:00Z", "2000-01-01T00:00:00Z", "2099-01-01T00:00:00Z"):
        assert vc.start_from_metadata(tag_video(plain, tmp_path / "bad.mp4", bad)) is None, bad


def test_a_video_that_is_not_there_gives_no_metadata(tmp_path):
    assert vc.start_from_metadata(tmp_path / "missing.mp4") is None


# ─── the clock printed in the picture ───────────────────────────────────────────────────────────────────

def test_two_readings_that_fit_the_time_that_passed_give_the_start(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=10)
    reader = Script(["2026-11-05 07:40:00", "2026-11-05 07:40:05", "2026-11-05 07:40:09"])
    start, note = vc.start_from_screen(video, reader)
    # the first picture is at 0.5 s showing 07:40:00 (a clock shows whole seconds: really about 07:40:00.5), so the file began at 07:40:00
    assert abs((start - datetime(2026, 11, 5, 7, 40, 0)).total_seconds()) <= 1.0
    assert "agree" in note


def test_readings_that_do_not_fit_the_time_that_passed_are_refused(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=10)
    assert vc.start_from_screen(video, Script(["2026-11-05 07:40:00", "2026-11-05 07:41:30", "2026-11-05 09:00:00"])) is None


def test_one_reading_is_not_enough(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=10)
    assert vc.start_from_screen(video, Script(["2026-11-05 07:40:00"])) is None


def test_a_picture_with_no_clock_gives_nothing(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=10)
    assert vc.start_from_screen(video, Script([])) is None


def test_a_video_too_short_to_read_twice_gives_nothing(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=2)
    assert vc.start_from_screen(video, Script(["2026-11-05 07:40:00"] * 3)) is None


def test_a_clock_without_seconds_is_accepted_with_a_looser_fit(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=10)
    start, _ = vc.start_from_screen(video, Script(["2026-11-05 07:40", "2026-11-05 07:40", "2026-11-05 07:40"]))
    assert abs((start - datetime(2026, 11, 5, 7, 40)).total_seconds()) <= 70


def test_the_real_ocr_reads_a_clock_painted_in_the_picture(tmp_path):
    """The whole path with the real EasyOCR: a camera-style clock in the top-left corner, ticking with the video."""
    from yolo_inference import get_easyocr_reader
    reader = get_easyocr_reader()
    if reader is None:
        pytest.skip("EasyOCR is not installed")
    begin = datetime(2026, 11, 5, 7, 40, 0)

    def clock(frame, second):
        text = (begin + timedelta(seconds=second)).strftime("%Y-%m-%d %H:%M:%S")
        cv2.putText(frame, text, (12, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2, cv2.LINE_AA)

    video = make_video(tmp_path / "osd.mp4", seconds=12, fps=10, draw=clock)
    found = vc.start_from_screen(video, reader)
    assert found is not None, "the real OCR could not read a clean painted clock twice"
    assert abs((found[0] - begin).total_seconds()) <= 2


# ─── no clock anywhere ──────────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("level,label", [(15, "night"), (70, "twilight"), (150, "day")])
def test_the_brightness_of_the_picture_says_day_twilight_or_night(tmp_path, level, label):
    assert vc.estimate_daylight(make_video(tmp_path / "v.mp4", seconds=3, brightness=level)) == label


def test_an_unreadable_video_has_no_daylight(tmp_path):
    (tmp_path / "bad.mp4").write_bytes(b"not a video")
    assert vc.estimate_daylight(tmp_path / "bad.mp4") is None


# ─── the ladder ─────────────────────────────────────────────────────────────────────────────────────────

@pytest.fixture
def quiet(monkeypatch):
    """No source answers unless a test sets it."""
    monkeypatch.setattr(vc, "start_from_screen", lambda path, reader=None, today=None: None)
    monkeypatch.setattr(vc, "start_from_metadata", lambda path: None)


def test_what_the_operator_typed_wins_over_everything(tmp_path, monkeypatch, quiet):
    monkeypatch.setattr(vc, "start_from_metadata", lambda path: datetime(2026, 11, 5, 15, 0))
    info = vc.resolve_clock(make_video(tmp_path / "20261105_150000.mp4", seconds=3), start_text="7:30")
    assert info.source == "operator" and info.confirmed and info.start.hour == 7 and info.start.minute == 30


def test_the_screen_clock_comes_before_the_file_information(tmp_path, monkeypatch, quiet):
    monkeypatch.setattr(vc, "start_from_screen", lambda path, reader=None, today=None: (datetime(2026, 11, 5, 7, 40), "Two readings agree."))
    monkeypatch.setattr(vc, "start_from_metadata", lambda path: datetime(2026, 11, 5, 7, 41))
    info = vc.resolve_clock(make_video(tmp_path / "v.mp4", seconds=3))
    assert info.source == "screen" and info.start == datetime(2026, 11, 5, 7, 40)
    assert "matches the video's own information" in info.note


def test_when_the_screen_and_the_file_tag_disagree_the_screen_wins_and_it_says_so(tmp_path, monkeypatch, quiet):
    monkeypatch.setattr(vc, "start_from_screen", lambda path, reader=None, today=None: (datetime(2026, 11, 5, 7, 40), "Two readings agree."))
    monkeypatch.setattr(vc, "start_from_metadata", lambda path: datetime(2026, 11, 5, 15, 40))      # local time stored as if it were UTC
    info = vc.resolve_clock(make_video(tmp_path / "v.mp4", seconds=3))
    assert info.source == "screen" and info.start.hour == 7
    assert "3:40 PM" in info.note and "not used" in info.note


def test_the_file_information_is_used_when_the_picture_has_no_clock(tmp_path, monkeypatch, quiet):
    monkeypatch.setattr(vc, "start_from_metadata", lambda path: datetime(2026, 11, 5, 7, 40))
    info = vc.resolve_clock(make_video(tmp_path / "v.mp4", seconds=3))
    assert info.source == "metadata" and info.confirmed and info.start == datetime(2026, 11, 5, 7, 40)


def test_the_file_name_is_used_when_nothing_else_has_a_time(tmp_path, quiet):
    info = vc.resolve_clock(make_video(tmp_path / "x.mp4", seconds=3), name="cam2_20261105_074000.mp4")
    assert info.source == "filename" and info.start == datetime(2026, 11, 5, 7, 40)


def test_the_trim_start_moves_the_start_to_the_first_analysed_frame(tmp_path, quiet):
    info = vc.resolve_clock(make_video(tmp_path / "x.mp4", seconds=3), start_text="2026-11-05 07:40", trim_start=90)
    assert info.start == datetime(2026, 11, 5, 7, 41, 30)
    assert info.at(30) == datetime(2026, 11, 5, 7, 42, 0)


def test_with_no_clock_anywhere_there_is_no_time_only_a_daylight_hint(tmp_path, quiet):
    info = vc.resolve_clock(make_video(tmp_path / "x.mp4", seconds=3, brightness=150))
    assert info.start is None and not info.confirmed and info.source == "estimate" and info.daylight == "day"
    assert "No time was found" in info.note and "daytime" in info.note
    assert info.at(5) is None


def test_a_video_that_cannot_be_read_at_all_says_none(tmp_path, quiet):
    (tmp_path / "bad.mp4").write_bytes(b"not a video")
    info = vc.resolve_clock(tmp_path / "bad.mp4")
    assert info.start is None and info.source == "none" and not info.confirmed


def test_a_typed_time_that_makes_no_sense_falls_through_to_the_video(tmp_path, monkeypatch, quiet):
    monkeypatch.setattr(vc, "start_from_metadata", lambda path: datetime(2026, 11, 5, 7, 40))
    info = vc.resolve_clock(make_video(tmp_path / "v.mp4", seconds=3), start_text="morning-ish")
    assert info.source == "metadata"


def test_resolving_the_clock_never_raises(tmp_path, monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("ocr exploded")
    monkeypatch.setattr(vc, "start_from_screen", boom)
    info = vc.resolve_clock(make_video(tmp_path / "v.mp4", seconds=3, brightness=150))
    assert info.start is None and info.source == "estimate"


def test_the_screen_is_skipped_when_asked(tmp_path, monkeypatch):
    monkeypatch.setattr(vc, "start_from_screen", lambda *a, **k: pytest.fail("the OCR must not run"))
    monkeypatch.setattr(vc, "start_from_metadata", lambda path: datetime(2026, 11, 5, 7, 40))
    assert vc.resolve_clock(make_video(tmp_path / "v.mp4", seconds=3), use_screen=False).source == "metadata"


# ─── what a real OCR does to a clock ────────────────────────────────────────────────────────────────────

def test_mixed_separators_from_an_ocr_are_forgiven():
    assert vc.parse_clock_text("2026-11-05 07:40.06")[0] == datetime(2026, 11, 5, 7, 40, 6)
    assert vc.parse_clock_text("2026-11-05 07.40:11")[0] == datetime(2026, 11, 5, 7, 40, 11)
    assert vc.parse_clock_text("05.11.2026 07:40:11")[0] == datetime(2026, 5, 11, 7, 40, 11)       # dotted date: its dots are not a time


def test_a_torn_piece_of_a_clock_is_not_a_clock():
    for piece in ["2:11", ":06", "07:", "07:40", "2026-11-05 07:"]:
        assert vc.parse_clock_text(piece) is None, piece
    assert vc.parse_clock_text("07:40:11")[0].second == 11                  # seconds make it a clock on its own
    assert vc.parse_clock_text("2026-11-05 07:40")[0].minute == 40          # so does a date next to it
    assert vc.parse_clock_text("07:40", loose=True)[0].minute == 40         # what a person typed may be bare


# ─── a real OCR on real footage garbles the clock: what is forgiven, and what is still not believed ──────

def test_a_misread_colon_glued_between_the_minutes_and_the_seconds_is_forgiven():
    assert vc.read_clock_text("2026-11-05 07.402112").seconds == 7 * 3600 + 40 * 60 + 12      # the last colon read as a digit
    assert vc.read_clock_text("2026-11-05 07:40315").seconds == 7 * 3600 + 40 * 60 + 15
    assert vc.read_clock_text("07:40:12").seconds == 7 * 3600 + 40 * 60 + 12


def test_a_dropped_date_separator_leaves_the_time_and_no_date():
    reading = vc.read_clock_text("2026-11 05 07.40.06 1")
    assert reading.seconds == 7 * 3600 + 40 * 60 + 6 and reading.has_seconds and reading.day is None


def test_the_date_is_kept_when_it_is_read():
    reading = vc.read_clock_text("2026-11-05 07:40:06")
    assert reading.day == datetime(2026, 11, 5).date()
    assert vc.read_clock_text("2026-13-45 07:40:06").day is None                                  # not a real date: no date


def test_the_trailing_junk_pieces_of_a_real_ocr_do_not_matter():
    assert vc.read_clock_text("0 2026-11-05 07.40:06 1 P").seconds == 7 * 3600 + 40 * 60 + 6


def test_readings_agree_on_the_time_of_day_even_when_only_one_has_a_date(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=10)
    start, _ = vc.start_from_screen(video, Script(["2026-11 05 07:40:00", "2026-11-05 07:40:05"]))   # the first lost its date
    assert start.date() == datetime(2026, 11, 5).date()                                               # the date comes from the one that has it
    assert abs((start - datetime(2026, 11, 5, 7, 40, 0)).total_seconds()) <= 1.0


def test_a_clock_that_passes_midnight_is_followed(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=10)
    start, _ = vc.start_from_screen(video, Script(["2026-11-05 23:59:58", "2026-11-06 00:00:03"]))   # the second is already the next day
    assert start == datetime(2026, 11, 5, 23, 59, 58)                                                      # the date of the first picture is kept


def test_garbled_pictures_are_skipped_until_two_good_ones_agree(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=20)
    # the pictures are looked at at 0.5 s, 10 s, 19 s, 5 s ...: the first two give nothing usable, the 3rd and 4th agree
    reader = Script(["garbage", "07:4", "2026-11-05 07:40:19", "2026-11-05 07:40:05"])
    start, _ = vc.start_from_screen(video, reader)
    assert abs((start - datetime(2026, 11, 5, 7, 40, 0)).total_seconds()) <= 1.5
    assert reader.calls == 4 * 4                    # four pictures, four corners each: it stopped at the first agreeing pair


def test_up_to_eight_pictures_are_looked_at_and_never_less_than_two_seconds_apart():
    times = vc._sample_times(60)
    assert times == [0.5, 30, 59, 15, 45, 7.5, 37.5, 52.5] and len(times) == vc.MAX_SCREEN_LOOKS
    assert all(abs(a - b) >= 2.0 for i, a in enumerate(times) for b in times[i + 1:])
    assert vc._sample_times(2) == []
    assert 2 <= len(vc._sample_times(6)) < 8                      # a short video has fewer places to look


def test_two_agreeing_readings_far_apart_in_the_video_still_count(tmp_path):
    video = make_video(tmp_path / "v.mp4", seconds=40)
    # picture 1 (0.5 s) shows 07:40:00, picture 2 (20 s) is garbage, picture 3 (39 s) shows 07:40:38.5 -> they agree
    reader = Script(["2026-11-05 07:40:00", "garbage", "2026-11-05 07:40:39"])
    start, _ = vc.start_from_screen(video, reader)
    assert abs((start - datetime(2026, 11, 5, 7, 40, 0)).total_seconds()) <= 2.5
