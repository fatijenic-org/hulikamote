"""
How the dashboard wizard's settings become the pipeline's zones (each violation maps its own: from_wizard),
and the guard that all 25 violations are registered with unique keys.
"""
import math

from engine.violations import ALL, REGISTRY, ZONE_COLORS, ZONE_RULES, ZONE_VIOLATIONS

POLY = [[0, 0], [100, 0], [100, 100], [0, 100]]
LINE = [[10, 50], [90, 50]]


def wizard(key, cfg):
    return REGISTRY[key].from_wizard(cfg)


# ─── the 25 violations (the 20 of the thesis list + 5 Philippine road rules) ─

THESIS_KEYS = {
    # movement and position
    "counterflow", "illegal_parking", "restricted_lane", "pedestrian_lane", "illegal_turn", "swerving",
    "illegal_u_turn", "blocking_intersection", "crossing_solid_line",
    # signals and signs
    "red_light", "disregarding_signs", "signal_light",
    # vehicle and riders
    "overloading", "pickup_passengers", "riding_outside_vehicle", "no_plate", "no_helmet", "no_seatbelt",
    "missing_side_mirror", "distracted_driving",
}
# added after the consultation: Philippine road rules, each judged from a drawn zone
PH_RULE_KEYS = {"illegal_loading", "truck_ban", "tricycle_on_highway", "sidewalk_driving", "double_parking"}


def test_twenty_five_violations_are_registered():
    assert len(ALL) == 25
    assert {v.key for v in ALL} == THESIS_KEYS | PH_RULE_KEYS
    assert len(REGISTRY) == 25                                  # no two share a key


def test_zone_violations_have_their_own_zone_list_and_colour():
    assert len({v.zone_key for v in ZONE_VIOLATIONS}) == len(ZONE_VIOLATIONS)
    assert set(ZONE_RULES) == set(ZONE_COLORS) == {v.key for v in ZONE_VIOLATIONS}


# ─── wizard -> camera_config zones ───────────────────────────────────────────

def test_counterflow_arrow_is_normalised_and_defaults_to_down():
    zones = wizard("counterflow", {"rois": [
        {"polygon": POLY, "vector": {"x_dir": 0.0, "y_dir": 5.0}},
        {"polygon": POLY, "vector": {"x_dir": 0.0, "y_dir": 0.0}},     # a zero arrow
        {"polygon": POLY},                                             # no arrow at all
        {"vector": {"x_dir": 1.0, "y_dir": 0.0}},                      # no polygon: dropped
    ]})
    assert [z["legal_flow_vector"] for z in zones] == [{"x_dir": 0.0, "y_dir": 1.0}] * 3
    assert all(z["coordinates"] == POLY for z in zones)
    assert math.isclose(wizard("counterflow", {"rois": [{"polygon": POLY, "vector": {"x_dir": 3, "y_dir": 4}}]})[0]
                        ["legal_flow_vector"]["x_dir"], 0.6)


def test_time_limits_and_classes_come_from_the_violation_settings():
    cfg = {"rois": [{"polygon": POLY}, {"polygon": None}]}
    assert wizard("illegal_parking", {**cfg, "time_limit": 30}) == [{"coordinates": POLY, "time_limit": 30.0}]
    assert wizard("illegal_parking", cfg)[0]["time_limit"] == 10.0
    assert wizard("pedestrian_lane", cfg)[0]["time_limit"] == 3.0
    assert wizard("blocking_intersection", cfg)[0]["time_limit"] == 5.0
    assert wizard("restricted_lane", {**cfg, "allowed_classes": ["bus", "car"]})[0]["allowed_classes"] == ["bus", "car"]
    assert wizard("restricted_lane", cfg)[0]["allowed_classes"] == ["bus"]


def test_zones_without_a_polygon_are_dropped_everywhere():
    for key in ("illegal_parking", "restricted_lane", "pedestrian_lane", "swerving", "signal_light", "illegal_u_turn",
                "blocking_intersection", "illegal_loading", "truck_ban", "tricycle_on_highway", "sidewalk_driving",
                "double_parking"):
        assert wizard(key, {"rois": [{"polygon": None}, {}]}) == []


def test_illegal_turn_needs_its_arrow():
    zones = wizard("illegal_turn", {"rois": [{"polygon": POLY, "vector": {"x_dir": -1.0, "y_dir": 0.0}}, {"polygon": POLY}]})
    assert zones == [{"coordinates": POLY, "prohibited_vector": {"x_dir": -1.0, "y_dir": 0.0}}]


def test_red_light_zone_carries_the_stop_line_and_the_light_setting():
    zone = {"polygon": POLY, "ui_vector": LINE, "ui_light_box": [[1, 1], [5, 9]]}
    timer = wizard("red_light", {"light_mode": "timer", "red_start": 2, "red": 30, "green": 25, "yellow": 3, "rois": [zone, {"polygon": POLY}]})
    assert timer == [{"coordinates": POLY, "stop_line": LINE, "light_box": [[1, 1], [5, 9]],
                      "light": {"mode": "timer", "red_start": 2.0, "red": 30.0, "green": 25.0, "yellow": 3.0}}]
    assert wizard("red_light", {"light_mode": "camera", "rois": [zone]})[0]["light"] == {"mode": "camera"}


def test_disregarding_signs_zone_carries_the_sign_and_its_settings():
    cfg = {"time_limit": 8, "banned_classes": ["truck"], "rois": [
        {"polygon": POLY, "sign": "stop", "ui_vector": LINE, "vector": {"x_dir": 0.0, "y_dir": 1.0}},
        {"polygon": POLY, "sign": "no_entry", "ui_vector": LINE, "vector": {"x_dir": 1.0, "y_dir": 0.0}},
        {"polygon": POLY},                                              # no sign type: dropped
    ]}
    stop, no_entry = wizard("disregarding_signs", cfg)
    assert stop["stop_line"] == LINE and stop["sign"] == "stop"
    assert no_entry["stop_line"] is None and no_entry["prohibited_vector"] == {"x_dir": 1.0, "y_dir": 0.0}
    assert stop["time_limit"] == 8.0 and stop["banned_classes"] == ["truck"]


def test_solid_line_zone_carries_its_line():
    cfg = {"rois": [{"polygon": POLY, "ui_vector": LINE}, {"polygon": POLY}]}
    assert wizard("crossing_solid_line", cfg) == [{"coordinates": POLY, "stop_line": LINE}]


def test_overloading_takes_the_rider_limit_as_a_top_level_setting():
    assert REGISTRY["overloading"].settings_from_wizard({"max_riders": 3}) == {"max_riders": 3}
    assert REGISTRY["overloading"].settings_from_wizard({}) == {"max_riders": 2}
    assert REGISTRY["pickup_passengers"].settings_from_wizard({"max_riders": 3}) == {}


# ─── what the wizard writes, the pipeline accepts ────────────────────────────

REPRESENTATIVE = {
    "counterflow": {"rois": [{"polygon": POLY, "vector": {"x_dir": 0.0, "y_dir": 1.0}}]},
    "illegal_turn": {"rois": [{"polygon": POLY, "vector": {"x_dir": -1.0, "y_dir": 0.0}}]},
    "red_light": {"light_mode": "timer", "rois": [{"polygon": POLY, "ui_vector": LINE}]},
    "disregarding_signs": {"rois": [{"polygon": POLY, "sign": "no_entry", "vector": {"x_dir": 1.0, "y_dir": 0.0}}]},
    "crossing_solid_line": {"rois": [{"polygon": POLY, "ui_vector": LINE}]},
}


def test_every_zone_violation_parses_what_its_own_wizard_mapping_writes():
    for v in ZONE_VIOLATIONS:
        cfg = REPRESENTATIVE.get(v.key, {"rois": [{"polygon": POLY}]})
        raw = v.from_wizard(cfg)
        assert raw, f"{v.key}: the wizard mapping produced no zone"
        zone = v.parse_zone(raw[0])
        assert zone and zone["polygon"] == POLY, f"{v.key}: the pipeline rejected the wizard's zone"
