"""
engine/road_flow.py - which way traffic goes on each part of the road (incoming = toward the camera, outgoing = away from it), read from
the moving points the road finder tracked. Synthetic points and a plain top view: no video, no model.
"""
import numpy as np

from engine import road_flow as rf

VW, VH = 1280, 720
TW, TH = 1200, 1200
GREY_W = 640                                   # the picture the moving points are in: half the video's width


def finder_result(kind="vanishing point"):
    """What the finder reports: the top view maps to the video by a plain scale, so a point's top-view position is easy to predict."""
    to_video = np.diag([VW / TW, VH / TH, 1.0])
    return {"video_size": [VW, VH], "road_direction": {"kind": kind}, "rectifier": {"top_to_video": to_video.tolist(), "top_size": [TW, TH]}}


def traffic(x0, x1, n, dy, seed=1, wobble=0.05):
    """n moving points between video x0 and x1, all heading along the road: dy = +1 down the picture (toward the camera), -1 up."""
    rng = np.random.default_rng(seed)
    points = np.column_stack([rng.uniform(x0, x1, n), rng.uniform(60, 700, n)]) / 2.0
    directions = np.column_stack([rng.normal(0, wobble, n), np.full(n, float(dy))])
    return points, directions / np.hypot(directions[:, 0], directions[:, 1])[:, None]


def together(*groups):
    return np.vstack([g[0] for g in groups]), np.vstack([g[1] for g in groups]), GREY_W


def test_traffic_going_each_way_gives_an_incoming_and_an_outgoing_side_of_the_road():
    flow = rf.read_flow(finder_result(), together(traffic(300, 600, 300, +1), traffic(700, 1000, 300, -1, seed=2)))
    assert flow["state"] == "two_way" and flow["reason"] is None and flow["points"] == 600
    left, right = flow["bands"]
    assert (left["flow"], right["flow"]) == ("in", "out")
    assert abs(left["polygon"][1][0] - 650) < 30 and abs(right["polygon"][0][0] - 650) < 30      # they meet between the two streams
    assert left["polygon"][0][0] < 300 and right["polygon"][1][0] > 1000                          # the road is a little wider than the traffic
    assert left["arrow"][0][1] < left["arrow"][1][1]                                              # incoming: the arrow points down, toward the camera
    assert right["arrow"][0][1] > right["arrow"][1][1]                                            # outgoing: the arrow points up, away
    assert abs(left["share"] - 0.5) < 0.05


def test_a_one_way_street_is_one_band_and_says_so():
    flow = rf.read_flow(finder_result(), together(traffic(300, 1000, 400, -1)))
    assert flow["state"] == "one_way_out" and [b["flow"] for b in flow["bands"]] == ["out"]
    flow = rf.read_flow(finder_result(), together(traffic(300, 1000, 400, +1)))
    assert flow["state"] == "one_way_in" and len(flow["bands"]) == 1


def test_a_few_vehicles_against_the_stream_do_not_make_another_side():
    flow = rf.read_flow(finder_result(), together(traffic(300, 700, 380, +1), traffic(300, 700, 20, -1, seed=3)))
    assert flow["state"] == "one_way_in" and len(flow["bands"]) == 1


def test_a_small_patch_of_the_other_direction_inside_a_side_is_not_a_side():
    flow = rf.read_flow(finder_result(), together(traffic(300, 500, 150, +1), traffic(500, 540, 12, -1, seed=4), traffic(540, 700, 150, +1, seed=5)))
    assert [b["flow"] for b in flow["bands"]] == ["in"]


def test_there_is_nothing_to_say_without_a_vanishing_point_or_enough_traffic():
    parallel = rf.read_flow(finder_result("parallel"), together(traffic(300, 1000, 400, +1)))
    assert parallel["state"] == "none" and parallel["bands"] == [] and "cannot be told" in parallel["reason"]
    few = rf.read_flow(finder_result(), together(traffic(300, 1000, 30, +1)))
    assert few["state"] == "none" and "Too little" in few["reason"]
    assert rf.read_flow(finder_result(), None)["state"] == "none"
    assert rf.read_flow({"video_size": [VW, VH], "road_direction": None}, together(traffic(300, 1000, 400, +1)))["state"] == "none"


def test_traffic_that_drives_across_the_road_is_not_counted():
    rng = np.random.default_rng(7)
    points = np.column_stack([rng.uniform(300, 1000, 400), rng.uniform(60, 700, 400)]) / 2.0
    sideways = np.column_stack([np.ones(400), np.zeros(400)])                    # along the picture's rows, not along the road
    flow = rf.read_flow(finder_result(), (points, sideways, GREY_W))
    assert flow["state"] == "none" and flow["points"] == 0


def test_add_flow_puts_the_answer_in_the_result_and_never_raises():
    result = finder_result()
    rf.add_flow(result, together(traffic(300, 600, 300, +1), traffic(700, 1000, 300, -1, seed=2)))
    assert result["flow"]["state"] == "two_way"
    broken = finder_result()
    rf.add_flow(broken, (np.zeros((200, 2)), "not directions", 640))
    assert broken["flow"]["state"] == "none" and "flow_error" in broken
