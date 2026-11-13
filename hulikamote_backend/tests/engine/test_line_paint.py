"""
Painted road line overlay (engine/line_paint.py) for "Crossing a solid line", and how a saved line with a look reaches the rule.
No model, no video: pictures made of shapes, scripted vehicles.
"""
from types import SimpleNamespace

import cv2
import numpy as np
import pytest

from engine import line_paint
from engine.ledger import ActiveLedgerManager
from engine.violations import REGISTRY
from routers.forensic import prepare_pipeline_config
from tests.helpers import FPS, drive

FRAME = (540, 960, 3)
LINE = [[300, 500], [320, 100]]                                   # up the picture, nearly vertical
SOLID = REGISTRY["crossing_solid_line"]


def grey():
    return np.full(FRAME, 110, dtype=np.uint8)


def painted(points=LINE, **look):
    frame = grey()
    line_paint.draw(frame, points, look, realistic=True)
    return frame


def row_width(frame, y):
    return int((frame[y] != 110).any(axis=1).sum())


def test_look_is_kept_inside_what_makes_sense():
    assert line_paint.look_of({}) == line_paint.DEFAULTS
    look = line_paint.look_of({"style": "wavy", "width": 99, "wear": -3, "taper": 7})
    assert look == {"style": "solid_yellow", "width": line_paint.MAX_WIDTH, "wear": 0.0, "taper": 1.0}
    assert line_paint.look_of("junk") == line_paint.DEFAULTS
    assert line_paint.look_of({"width": float("nan")})["width"] == 1.0
    assert line_paint.look_of({"style": "dashed_white"})["style"] == "dashed_white"


def test_a_line_needs_two_finite_points():
    assert line_paint.usable_line(LINE) == [[300.0, 500.0], [320.0, 100.0]]
    for bad in (None, [], [[1, 1]], [[1, 1], ["a", 2]], [[1, 1], [float("inf"), 2]], "xy", 5):
        assert line_paint.usable_line(bad) is None, bad


def test_paint_lies_along_the_line_and_nowhere_else():
    frame = painted(wear=0.0)
    ys, xs = np.nonzero((frame != 110).any(axis=2))
    assert len(xs) > 200
    assert xs.min() >= 280 and xs.max() <= 340 and ys.min() >= 90 and ys.max() <= 510
    assert (frame[:, :200] == 110).all() and (frame[:, 500:] == 110).all()


def test_paint_is_thinner_farther_up_the_picture_unless_taper_is_off():
    near, far = row_width(painted(wear=0.0, taper=1.0), 480), row_width(painted(wear=0.0, taper=1.0), 130)
    assert near > far, (near, far)
    flat_near, flat_far = row_width(painted(wear=0.0, taper=0.0), 480), row_width(painted(wear=0.0, taper=0.0), 130)
    assert abs(flat_near - flat_far) <= 2, (flat_near, flat_far)


def test_wider_paint_covers_more_and_worn_paint_covers_less():
    covered = lambda f: int(np.abs(f.astype(int) - 110).sum())             # how much paint, not how many pixels it touches
    assert covered(painted(width=2.5, wear=0.0)) > covered(painted(width=1.0, wear=0.0)) * 1.3
    assert covered(painted(wear=1.0)) < covered(painted(wear=0.0)) * 0.9


def test_the_styles_look_different_white_and_yellow_and_dashes_and_two_lines():
    frames = {s: painted(style=s, wear=0.0) for s in line_paint.STYLES}
    for a in line_paint.STYLES:
        for b in line_paint.STYLES:
            if a < b:
                assert (frames[a] != frames[b]).any(), (a, b)
    white, yellow = frames["solid_white"][300, 310], frames["solid_yellow"][300, 310]
    assert int(white[2]) > 150 and int(white[0]) > 150                          # white: all channels high
    assert int(yellow[2]) > int(yellow[0]) + 60                                  # yellow: much more red than blue
    dashed = frames["dashed_white"]
    on = [bool((dashed[y] != 110).any()) for y in range(110, 490)]
    assert any(on) and not all(on)                                               # dashes have gaps
    double = frames["double_yellow"]
    cols = np.abs(double[300].astype(int) - 110).max(axis=1) > 40
    runs = int(np.count_nonzero(np.diff(cols.astype(int)) == 1))
    assert runs == 2, runs                                                       # two separate stripes across the road


def test_realistic_paint_is_soft_and_both_looks_are_the_same_on_every_frame():
    flat, filmed = grey(), grey()
    line_paint.draw(flat, LINE, {}, realistic=False)
    line_paint.draw(filmed, LINE, {}, realistic=True)
    assert (flat != filmed).any()
    again = grey()
    line_paint.draw(again, LINE, {}, realistic=True)
    assert (again == filmed).all()


def test_vehicles_drive_over_the_paint():
    frame = grey()
    line_paint.draw(frame, LINE, {"wear": 0.0}, realistic=True, occluders=[[270, 250, 90, 100]])      # a car box across the line
    free = grey()
    line_paint.draw(free, LINE, {"wear": 0.0}, realistic=True)
    assert (frame[290:310, 300:320] == 110).all() and (free[290:310, 300:320] != 110).any()
    assert (frame[450] == free[450]).all()                                       # the rest of the line is still there


def test_drawing_never_fails_off_the_picture_or_on_nonsense():
    for points in ([[-500, -500], [-100, -90]], [[5000, 100], [6000, 900]], [[480, 270], [480, 270]], [[0, 0], [959, 539]], [[10, 10]], None, "x"):
        line_paint.draw(grey(), points, {"style": "double_yellow", "width": 3}, True)
    line_paint.draw(grey(), [[0, 0], [959, 539], [0, 539], [959, 0]], {"style": "dashed_white", "wear": 1.0, "taper": 0.0}, False)


def test_the_preview_is_a_png_with_see_through_parts_and_an_offset():
    png, ox, oy = line_paint.preview([[960, 1000], [1000, 400], [1100, 200]], {"style": "double_yellow"}, True)
    image = cv2.imdecode(np.frombuffer(png, np.uint8), cv2.IMREAD_UNCHANGED)
    assert image.ndim == 3 and image.shape[2] == 4 and image[..., 3].max() > 200 and image[0, 0, 3] == 0
    assert 800 < ox + image.shape[1] and ox < 1100 and oy < 400
    assert line_paint.preview([[1, 1]], {}, True) == (b"", 0, 0)


def test_the_preview_matches_the_drawing_on_the_photo():
    frame = grey()
    line_paint.draw(frame, LINE, {"wear": 0.0}, realistic=True)
    png, ox, oy = line_paint.preview(LINE, {"wear": 0.0}, True, frame_size=(FRAME[1], FRAME[0]), light=int(min(3, grey()[::16, ::16].mean() / 64.0)))
    image = cv2.imdecode(np.frombuffer(png, np.uint8), cv2.IMREAD_UNCHANGED)
    ys, xs = np.nonzero((frame != 110).any(axis=2))
    assert xs.min() >= ox - 1 and ys.min() >= oy - 1 and xs.max() <= ox + image.shape[1] and ys.max() <= oy + image.shape[0]


def test_the_endpoint_gives_the_png_and_refuses_a_line_with_one_point():
    from fastapi import HTTPException
    from routers import forensic
    response = forensic.overlay_line(forensic.OverlayLineRequest(points=[[300, 900], [400, 300]], look={"style": "solid_white"}, realistic=False))
    assert response.media_type == "image/png" and response.body[:4] == b"\x89PNG" and "x-offset-x" in response.headers
    with pytest.raises(HTTPException) as e:
        forensic.overlay_line(forensic.OverlayLineRequest(points=[[300, 900]]))
    assert e.value.status_code == 422


# ─── in the rule ────────────────────────────────────────────────────────────

def test_a_saved_line_with_a_look_is_painted_and_one_without_is_not():
    raw = SOLID.from_wizard({"rois": [{"line": [[100, 800], [200, 300]], "look": {"style": "dashed_white", "width": 2}},
                                      {"line": [[900, 800], [1000, 300]]}], "lines_realistic": False})
    plain = SOLID.parse_zone(raw[1])
    painted_zone = SOLID.parse_zone(raw[0])
    assert plain is not None and "look" not in plain and "realistic" not in plain
    assert painted_zone["look"] == line_paint.look_of({"style": "dashed_white", "width": 2}) and painted_zone["realistic"] is False
    assert SOLID.parse_zone({"stop_line": [[1, 1], [5, 5]], "look": {"wear": 0.5}})["realistic"] is True


def test_an_empty_look_still_means_paint_with_the_defaults():
    (raw,) = SOLID.from_wizard({"rois": [{"line": [[100, 800], [200, 300]], "look": {}}]})
    assert raw["look"] == line_paint.DEFAULTS and raw["realistic"] is True


def test_the_wizard_payload_carries_the_look_into_the_saved_rules():
    config = prepare_pipeline_config({"per_violation_configs": {"crossing_solid_line": {"rois": [{"line": [[100, 800], [200, 300]], "look": {"style": "double_yellow"}}]}}})
    (raw,) = config["regions_of_interest"]["solid_line_zones"]
    assert raw["look"]["style"] == "double_yellow" and raw["stop_line"] == [[100, 800], [200, 300]]


def test_painting_a_line_does_not_change_what_the_rule_judges():
    cross = [(480 - 3 * i, 400 - 3 * i) for i in range(0, 100, 2)]               # a car driving across the line from right to left
    for look in (None, {"style": "double_yellow", "wear": 0.9}):
        zone = SOLID.parse_zone({"stop_line": [[300, 100], [300, 500]], **({"look": look} if look is not None else {})})
        mgr = ActiveLedgerManager()
        flagged = drive(mgr, [(x, y) for x, y in cross for _ in range(1)], lambda tid: SOLID.evaluate(mgr, tid, [zone]))
        assert flagged
        away = ActiveLedgerManager()
        assert not drive(away, [(600, 400)] * 40, lambda tid: SOLID.evaluate(away, tid, [zone]))


def test_the_rule_draws_the_paint_under_the_vehicles_and_a_plain_line_as_before():
    zone = SOLID.parse_zone({"stop_line": LINE, "look": {"wear": 0.0}})
    pipe = SimpleNamespace(_draw_dets=[SimpleNamespace(cls="car", bbox=[270, 250, 90, 100])], line_colour=lambda *_: (0, 0, 255),
                           ledger_manager=None)
    painted_frame, plain_frame = grey(), grey()
    SOLID.draw_zone(pipe, painted_frame, 0, zone)
    SOLID.draw_zone(pipe, plain_frame, 0, {"polygon": [], "stop_line": LINE})
    assert row_width(painted_frame, 450) > row_width(plain_frame, 450)             # the paint is wider than the thin state line
    assert (painted_frame[290:310, 300:320] != 110).any()                           # the state line is still on top
    assert (plain_frame != 110).any()
