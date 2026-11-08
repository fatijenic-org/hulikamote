"""engine/video_window.py - which frames of a video an analysis covers when the operator trimmed it."""
import pytest

from engine.video_window import frame_window, number_or_none


@pytest.mark.parametrize("value,expected", [(5, 5.0), ("7.5", 7.5), (0, 0.0), (None, None), ("abc", None), (True, None),
                                            (float("nan"), None), (float("inf"), None), ([], None)])
def test_a_trim_value_is_a_number_or_nothing(value, expected):
    assert number_or_none(value) == expected


def test_no_trim_means_the_whole_video():
    assert frame_window(25, 500) == (0, None)
    assert frame_window(25, 500, None, None) == (0, None)


def test_a_start_skips_frames_and_an_end_limits_how_many():
    assert frame_window(25, 500, 2.0, None) == (50, None)
    assert frame_window(25, 500, None, 4.0) == (0, 100)
    assert frame_window(25, 500, 2.0, 4.0) == (50, 50)


def test_the_end_cannot_go_past_the_video():
    assert frame_window(25, 500, 10.0, 99.0) == (250, 250)


def test_nonsense_never_makes_an_empty_analysis():
    assert frame_window(25, 500, 4.0, 2.0) == (100, None)        # end before start: to the end instead
    assert frame_window(25, 500, 4.0, 4.0) == (100, None)
    assert frame_window(25, 500, -5, 0) == (0, None)
    assert frame_window(25, 500, "x", "y") == (0, None)


def test_an_unknown_frame_rate_falls_back_to_30():
    assert frame_window(0, 0, 1.0, 2.0) == (30, 30)
    assert frame_window(-1, 900, 2.0, None) == (60, None)


def test_a_video_that_does_not_say_how_many_frames_it_has_still_gets_its_end():
    assert frame_window(10, 0, 1.0, 3.0) == (10, 20)
