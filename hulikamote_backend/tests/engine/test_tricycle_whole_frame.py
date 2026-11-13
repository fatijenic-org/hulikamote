"""
Tricycle on a national highway without a drawn zone: ticking the rule says "the whole view is a road where tricycles are banned";
a drawn zone still limits it to where it is. Scripted vehicles only (no model, no video).
"""
from types import SimpleNamespace

from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from engine.violations import REGISTRY, ZONE_RULES
from tests.helpers import drive

RULE = REGISTRY["tricycle_on_highway"]
KEY = RULE.key
CORNER = [[0, 0], [100, 0], [100, 100], [0, 100]]             # a drawn zone that the scripted vehicle never reaches


def pipeline(active, cfg=None, drawn=None, flow_mode="zones"):
    pipe = object.__new__(DecoupledPipeline)                      # skip model loading
    pipe.rois = {key: [] for key in ZONE_RULES.values()}
    if drawn is not None:
        pipe.rois[RULE.zone_key] = drawn
    pipe.native_w, pipe.native_h = 1920, 1080
    pipe.registry = SimpleNamespace(active_violations=active)
    pipe.violation_cfg = {KEY: cfg} if cfg is not None else {}
    pipe.flow_mode = flow_mode
    pipe.flow = None                                              # the learned traffic flow: not needed here
    return pipe


def run(zones, cls):
    mgr = ActiveLedgerManager()
    return drive(mgr, [(1000, 1000 - 9 * i) for i in range(20)], lambda tid: RULE.evaluate(mgr, tid, zones), cls=cls)


def test_the_rule_is_zone_optional():
    assert RULE.whole_frame


def test_with_nothing_drawn_the_whole_picture_is_the_banned_road():
    for mode in ("zones", "auto"):
        scaled = pipeline([KEY], flow_mode=mode)._get_scaled_rois(960, 540)
        (zone,) = scaled[RULE.zone_key]
        assert zone["polygon"] == [[0, 0], [960, 0], [960, 540], [0, 540]]
        assert zone["banned_classes"] == ["tricycle"]


def test_a_tricycle_is_flagged_and_other_vehicles_are_not_on_the_whole_picture_road():
    (zone,) = pipeline([KEY])._get_scaled_rois(1920, 1080)[RULE.zone_key]
    assert run([zone], "tricycle")
    for cls in ("car", "motorcycle", "bus", "truck"):
        assert not run([zone], cls), cls


def test_the_enforcers_vehicle_types_still_decide_who_is_banned():
    (zone,) = pipeline([KEY], {"banned_classes": ["motorcycle"]})._get_scaled_rois(1920, 1080)[RULE.zone_key]
    assert zone["banned_classes"] == ["motorcycle"]
    assert run([zone], "motorcycle") and not run([zone], "tricycle")


def test_a_drawn_zone_still_limits_the_rule_and_no_whole_picture_zone_is_added():
    drawn = [{"polygon": CORNER, "banned_classes": ["tricycle"]}]
    (zone,) = pipeline([KEY], drawn=drawn)._get_scaled_rois(1920, 1080)[RULE.zone_key]
    assert zone["polygon"] == CORNER
    assert not run([zone], "tricycle")                             # it drives past the drawn part: not flagged


def test_with_the_rule_off_no_zone_is_made():
    assert pipeline(["counterflow"])._get_scaled_rois(1920, 1080)[RULE.zone_key] == []
    assert pipeline([])._get_scaled_rois(1920, 1080)[RULE.zone_key] == []
