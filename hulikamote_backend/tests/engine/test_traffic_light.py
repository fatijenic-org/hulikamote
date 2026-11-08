"""engine/traffic_light.py - reading the light colour, the simulated light timer, and blink detection."""
import numpy as np

from engine.traffic_light import LightReader, amber_fraction, is_blinking, read_light_colour, timer_state
from tests.helpers import FPS


def lamp(bgr):
    img = np.zeros((40, 20, 3), dtype=np.uint8)
    img[5:15, 5:15] = bgr
    return img


def test_light_colour_reading():
    assert read_light_colour(lamp((0, 0, 255))) == "red"
    assert read_light_colour(lamp((0, 255, 255))) == "yellow"
    assert read_light_colour(lamp((0, 255, 0))) == "green"
    assert read_light_colour(np.zeros((40, 20, 3), dtype=np.uint8)) == "unknown"   # light off / dark


def test_light_reader_needs_two_reads_to_change():
    reader = LightReader()
    assert reader.update(lamp((0, 0, 255))) == "unknown"   # one red read is not enough
    assert reader.update(lamp((0, 0, 255))) == "red"
    assert reader.update(lamp((0, 255, 0))) == "red"       # one green flicker keeps red
    assert reader.update(lamp((0, 255, 0))) == "green"


def test_light_timer():
    cycle = {"red_start": 10, "red": 30, "green": 25, "yellow": 5}   # 60 s cycle
    assert timer_state(10, cycle) == "red"
    assert timer_state(39.9, cycle) == "red"
    assert timer_state(40, cycle) == "green"
    assert timer_state(66, cycle) == "yellow"
    assert timer_state(70, cycle) == "red"          # next cycle
    assert timer_state(5, cycle) == "yellow"        # before red_start: cycle runs backwards too
    assert timer_state(5, {"red": 0, "green": 0, "yellow": 0}) == "unknown"


def test_timer_phase_countdown():
    from engine.traffic_light import timer_phase
    cycle = {"red_start": 10, "red": 30, "green": 25, "yellow": 5}
    assert timer_phase(15, cycle) == ("red", 25)
    assert timer_phase(60, cycle) == ("green", 5)


def blink_series(on_value=0.05, period=0.8, seconds=4.0, fps=FPS):
    return [(i / fps, on_value if (i / fps) % period < period / 2 else 0.0) for i in range(int(seconds * fps))]


def test_blink_detection():
    assert is_blinking(blink_series())
    assert not is_blinking([(t, 0.05) for t, _ in blink_series()])            # always amber (yellow car)
    assert not is_blinking([(t, 0.001 * (i % 2)) for i, (t, _) in enumerate(blink_series())])   # noise
    assert not is_blinking(blink_series(period=0.1, fps=30))                   # flicker too fast
    amber = np.zeros((10, 10, 3), dtype=np.uint8)
    amber[:5] = (0, 170, 255)                                                  # BGR amber
    assert 0.45 < amber_fraction(amber) < 0.55
