"""
The road finder (engine/road_lines.analyse_clip) hands the moving points it tracked to engine/road_flow.py. This goes in the same commit as
that hook in road_lines.py (which needs the finder's `kept` motion points from the road-edges change).
"""
import numpy as np

from engine import road_lines as rl
from tests.engine.test_road_flow import finder_result, together, traffic


def test_the_finder_hands_its_moving_points_to_the_flow_reader(monkeypatch):
    motion = together(traffic(300, 600, 300, +1), traffic(700, 1000, 300, -1, seed=2))

    def top_view(clip, keep_top, trace, detector, kept):
        kept["motion"] = motion
        return finder_result(), np.zeros((8, 8, 3), np.uint8)
    monkeypatch.setattr(rl, "_analyse_top_view", top_view)
    monkeypatch.setattr(rl, "_add_edges", lambda *a, **k: None)
    result, _background = rl.analyse_clip({})
    assert result["flow"]["state"] == "two_way" and len(result["flow"]["bands"]) == 2
