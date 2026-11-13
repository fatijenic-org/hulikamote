"""
Realistic overlay objects (engine/overlay_objects.py): hydrant, no-parking sign, fire station / driveway / no-loading plates, painted kerb.
No model, no video: pictures made of shapes.
"""
import cv2
import numpy as np

from engine import lane_signs, overlay_objects as oo

FRAME = (540, 960, 3)


def grey():
    return np.full(FRAME, 120, dtype=np.uint8)


def drawn(kind, at=(480, 400), **look):
    frame = grey()
    oo.draw_object(frame, at, kind, look, realistic=True)
    return frame


def changed_box(a, b):
    ys, xs = np.nonzero((a != b).any(axis=2))
    return xs.min(), ys.min(), xs.max(), ys.max()


def test_every_kind_draws_something_and_nothing_else_than_near_its_spot():
    for kind in oo.KINDS:
        frame = drawn(kind)
        x0, y0, x1, y1 = changed_box(frame, grey())
        assert x1 > x0 and y1 > y0, kind
        assert x0 > 480 - 120 and x1 < 480 + 120 and y1 < 400 + 40 and y0 > 400 - 200, (kind, x0, y0, x1, y1)


def test_an_unknown_kind_is_a_no_parking_sign():
    assert oo.kind_of("nonsense") == oo.DEFAULT_KIND == "sign"
    assert (drawn("nonsense") == drawn("sign")).all()


def test_the_look_is_kept_inside_what_makes_sense_and_stands_follow_the_kind():
    look = oo.look_of({"scale": 99, "angle": 500, "tilt": -500, "stand": "wrongly"}, "sign")
    assert look == {"scale": lane_signs.MAX_SCALE, "angle": lane_signs.MAX_ANGLE, "tilt": -lane_signs.MAX_TILT, "stand": "post"}
    assert oo.look_of({"stand": "tripod"}, "sign")["stand"] == "tripod"
    assert oo.look_of({"stand": "none"}, "no_loading")["stand"] == "none"
    for alone in ("hydrant", "corner"):                      # a hydrant and a painted kerb stand on their own, whatever is asked
        assert oo.look_of({"stand": "tripod"}, alone)["stand"] == "none"
    assert oo.look_of("junk", "hydrant")["scale"] == 1.0


def test_bigger_turned_and_tilted_objects_look_different_and_a_bigger_one_covers_more():
    plain = drawn("hydrant")
    assert (drawn("hydrant", scale=2.0) != plain).any() and (drawn("hydrant", angle=20) != plain).any() and (drawn("hydrant", tilt=45) != plain).any()
    small, big = changed_box(plain, grey()), changed_box(drawn("hydrant", scale=2.0), grey())
    assert (big[2] - big[0]) > (small[2] - small[0]) * 1.6


def test_a_plate_on_a_post_a_tripod_and_on_the_ground_are_three_different_things():
    post, tripod, none = drawn("sign", stand="post"), drawn("sign", stand="tripod"), drawn("sign", stand="none")
    assert (post != tripod).any() and (post != none).any()
    assert changed_box(none, grey())[1] > changed_box(post, grey())[1]                   # the plate alone stops lower: it has no pole to stand on


def test_realistic_is_softer_than_flat_and_both_are_cached_frame_to_frame():
    flat, filmed = grey(), grey()
    oo.draw_object(flat, (480, 400), "hydrant", {}, realistic=False)
    oo.draw_object(filmed, (480, 400), "hydrant", {}, realistic=True)
    assert (flat != filmed).any()
    again = grey()
    oo.draw_object(again, (480, 400), "hydrant", {}, realistic=True)
    assert (again == filmed).all()                                                       # same input, same pixels: no flicker


def test_the_hydrant_is_red_and_the_plates_have_their_words_colours():
    hydrant = drawn("hydrant")
    crop = hydrant[360:400, 465:495].reshape(-1, 3).astype(int)
    assert (crop[:, 2] > crop[:, 0] + 60).any()
    sign = drawn("sign", scale=2.0)
    ys, xs = np.nonzero((sign != grey()).any(axis=2))
    blue = sign[ys, xs].astype(int)
    assert ((blue[:, 0] > blue[:, 2] + 40)).any()                                        # the blue field of the no-parking sign


def test_drawing_off_the_picture_or_at_the_edge_never_fails():
    for at in ((-500, -500), (0, 0), (959, 539), (5000, 100)):
        for kind in oo.KINDS:
            oo.draw_object(grey(), at, kind, {"scale": 3.0, "angle": 90, "tilt": 70})


def test_the_area_is_a_faint_tint_with_a_dashed_edge_and_never_fails_on_odd_polygons():
    frame = grey()
    oo.draw_area(frame, [[200, 150], [600, 150], [600, 350], [200, 350]], "hydrant")
    assert (frame[250, 400] != 120).any() and abs(int(frame[250, 400, 2]) - 120) < 40      # tinted, but the road still shows
    assert (frame[0, 0] == 120).all()
    for odd in ([], [[1, 1]], [[1, 1], [2, 2]], [[-50, -50], [-10, -50], [-10, -10]], [[5000, 5000], [6000, 5000], [6000, 6000]]):
        oo.draw_area(grey(), odd, "sign")


def test_the_preview_is_a_png_with_see_through_parts_and_an_offset_to_where_it_stands():
    png, ox, oy = oo.preview("hydrant", scale=1.0)
    image = cv2.imdecode(np.frombuffer(png, np.uint8), cv2.IMREAD_UNCHANGED)
    assert image.ndim == 3 and image.shape[2] == 4
    assert image[0, 0, 3] == 0 and image[..., 3].max() > 200                              # empty corner, solid body
    assert ox < 0 and oy < 0                                                              # the top-left pixel is up and left of the ground spot
    assert -ox < image.shape[1] and -oy < image.shape[0]
    bigger = cv2.imdecode(np.frombuffer(oo.preview("hydrant", scale=2.0)[0], np.uint8), cv2.IMREAD_UNCHANGED)
    assert bigger.shape[0] > image.shape[0] * 1.6


def test_the_preview_matches_the_drawing_on_the_photo():
    """The wizard's picture and the evidence photo come from the same sprite: its pixels are where the preview says."""
    png, ox, oy = oo.preview("sign", scale=1.0, frame_width=FRAME[1])
    image = cv2.imdecode(np.frombuffer(png, np.uint8), cv2.IMREAD_UNCHANGED)
    frame = grey()
    oo.draw_object(frame, (480, 400), "sign", {}, realistic=True)
    ys, xs = np.nonzero((frame != grey()).any(axis=2))
    assert xs.min() >= 480 + ox - 1 and ys.min() >= 400 + oy - 1
    assert xs.max() <= 480 + ox + image.shape[1] and ys.max() <= 400 + oy + image.shape[0]


def test_the_endpoint_gives_the_png_and_the_offsets_and_keeps_the_size_in_bounds():
    from routers import forensic
    response = forensic.overlay_object(kind="hydrant", scale=1.0, angle=0.0, tilt=0.0, stand="", realistic=True, frame_width=1920)
    assert response.media_type == "image/png" and response.body[:4] == b"\x89PNG"
    assert int(response.headers["x-offset-x"]) < 0 and int(response.headers["x-offset-y"]) < 0
    tiny = forensic.overlay_object(kind="sign", scale=1.0, angle=0.0, tilt=0.0, stand="tripod", realistic=False, frame_width=1)    # clamped, no crash
    assert tiny.body[:4] == b"\x89PNG"
