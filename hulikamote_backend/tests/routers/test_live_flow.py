"""Live Monitor: the learned traffic flow as arrows, the Counterflow demo reversal, and keeping the flow when the rules change."""
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from engine.flow_field import FlowField
from engine.ledger import ActiveLedgerManager
from engine.violations import REGISTRY
from main import app
from routers import stream
from tests.engine.test_flow_field import FH, FW, LEFT, RIGHT, teach
from tests.helpers import FPS, H, W, Det

client = TestClient(app)
WHOLE = [[0, 0], [FW, 0], [FW, FH], [0, FH]]


def fake_pipeline(active=("counterflow",), learns=True, cfg=None, field=None, rois=None):
    return SimpleNamespace(
        registry=SimpleNamespace(active_violations=list(active)), learns_flow=learns, violation_cfg={} if cfg is None else cfg,
        rois=rois or {}, ledger_manager=ActiveLedgerManager(), flow=field if field is not None else FlowField(),
    )


@pytest.fixture
def live(monkeypatch):
    """A running live feed with a taught flow (traffic goes RIGHT), no camera and no models."""
    pipe = fake_pipeline(field=teach(FlowField(), RIGHT))
    monkeypatch.setattr(stream, "_pipeline", pipe)
    monkeypatch.setattr(stream, "_last_size", (FW, FH))
    return pipe


# ─── the arrows ──────────────────────────────────────────────────────────────

def test_arrows_follow_the_learned_flow_and_can_be_reversed():
    field = teach(FlowField(), RIGHT)
    arrows = field.arrows(FW, FH)
    assert arrows and all(a["x2"] > a["x1"] and abs(a["y2"] - a["y1"]) < 1e-6 for a in arrows)
    assert all(a["x2"] < a["x1"] for a in field.arrows(FW, FH, invert=True))
    assert FlowField().arrows(FW, FH) == []                                    # nothing learned, nothing to show


# ─── reversing Counterflow for a demo ───────────────────────────────────────────

def judge(pipe, mgr, points, first_frame=0, tid=1):
    """Drive one car along `points`, judging it on every frame with the zone the pipeline would build from its settings."""
    rule, flagged = REGISTRY["counterflow"], False
    for i, (x, y) in enumerate(points, first_frame):
        mgr.update([Det(tid, [int(x - W / 2), int(y - H), W, H])], i / FPS)
        zone = rule.whole_frame_zone(pipe.violation_cfg.get("counterflow", {}), WHOLE, (FW, FH), pipe.flow)
        flagged = rule.evaluate(mgr, tid, [zone]) or flagged
    return flagged


def test_reversing_flags_ordinary_traffic_and_a_switch_off_leaves_no_ticket_behind():
    rule = REGISTRY["counterflow"]
    pipe = fake_pipeline(field=teach(FlowField(), RIGHT))
    mgr = pipe.ledger_manager
    path = [(150 + 9 * i, 360) for i in range(100)]                            # drives RIGHT, with the learned flow, for 10 s
    assert not judge(pipe, mgr, path[:40], 0)
    rule.set_test_reversed(pipe, True)
    assert pipe.violation_cfg["counterflow"]["invert_flow"] is True
    assert judge(pipe, mgr, path[40:80], 40) and "counterflow" in mgr.ledgers[1].violations      # now the same car is "wrong way"
    rule.set_test_reversed(pipe, False)
    assert "counterflow" not in mgr.ledgers[1].violations                      # the test flag is gone at once
    assert not judge(pipe, mgr, path[80:], 80)                                 # and ordinary traffic is ordinary again


def test_reversing_flips_the_arrow_of_a_drawn_zone_once():
    rule = REGISTRY["counterflow"]
    zone = {"polygon": [[0, 0], [100, 0], [100, 100]], "vector": (1.0, 0.0), "test_reversed": False}
    pipe = fake_pipeline(rois={"counterflow_zones": [zone]})
    rule.set_test_reversed(pipe, True)
    rule.set_test_reversed(pipe, True)                                         # asking again must not flip it back
    assert zone["vector"] == (-1.0, 0.0) and zone["test_reversed"] is True
    rule.set_test_reversed(pipe, False)
    assert zone["vector"] == (1.0, 0.0) and zone["test_reversed"] is False


# ─── what the live feed tells the dashboard ─────────────────────────────────────────────

def test_flow_status_is_none_when_no_rule_uses_the_flow(monkeypatch):
    monkeypatch.setattr(stream, "_pipeline", None)
    assert stream.flow_status() is None
    monkeypatch.setattr(stream, "_pipeline", fake_pipeline(active=("swerving",), learns=False))
    assert stream.flow_status() is None


def test_the_flow_message_has_the_arrows_and_follows_the_reversal(live):
    state = stream.flow_status()
    assert state == {"learning": True, "counterflow": True, "reversed": False, "cells": state["cells"]} and state["cells"] > 0
    normal = stream._flow_message(live, FW, FH)
    assert normal["arrows"] and normal["arrows"][0]["x2"] > normal["arrows"][0]["x1"]
    assert stream.set_flow_reversed(True) == {"ok": True, "reversed": True}
    flipped = stream._flow_message(live, FW, FH)
    assert flipped["reversed"] is True and flipped["arrows"][0]["x2"] < flipped["arrows"][0]["x1"]


def test_counterflow_with_drawn_zones_has_the_switch_but_no_learned_arrows(monkeypatch):
    drawn = fake_pipeline(learns=False, rois={"counterflow_zones": [{"polygon": WHOLE, "vector": (1.0, 0.0)}]})
    monkeypatch.setattr(stream, "_pipeline", drawn)
    message = stream._flow_message(drawn, FW, FH)
    assert message["counterflow"] and not message["learning"] and message["arrows"] == []


def test_reversing_needs_counterflow_to_be_on(monkeypatch):
    monkeypatch.setattr(stream, "_pipeline", None)
    assert stream.set_flow_reversed(True)["ok"] is False
    monkeypatch.setattr(stream, "_pipeline", fake_pipeline(active=("swerving",), learns=False))
    assert "Counterflow is not switched on" in stream.set_flow_reversed(True)["reason"]


def test_relearning_forgets_the_flow(live):
    before = live.flow
    assert stream.relearn_flow() == {"ok": True} and live.flow is not before and live.flow.arrows(FW, FH) == []


# ─── the same over HTTP ───────────────────────────────────────────────────────────────

def test_the_switch_and_relearn_work_over_http(live):
    assert client.post("/settings/live/flow/reverse", params={"on": "true"}).json() == {"ok": True, "reversed": True}
    assert live.violation_cfg["counterflow"]["invert_flow"] is True
    assert client.get("/settings/video/status").json()["flow"]["reversed"] is True
    assert client.post("/settings/live/flow/reverse", params={"on": "false"}).json() == {"ok": True, "reversed": False}
    assert client.get("/settings/video/status").json()["flow"]["reversed"] is False
    assert client.post("/settings/live/flow/relearn").json() == {"ok": True}


def test_http_says_why_when_counterflow_is_off(monkeypatch):
    monkeypatch.setattr(stream, "_pipeline", fake_pipeline(active=("swerving",), learns=False))
    answer = client.post("/settings/live/flow/reverse", params={"on": "true"}).json()
    assert answer["ok"] is False and "Set up violations" in answer["reason"]


# ─── new rules for the same camera keep the learned flow ──────────────────────────────────────

def test_new_rules_for_the_same_camera_keep_the_learned_flow_and_another_camera_does_not(monkeypatch):
    learned = teach(FlowField(), RIGHT)
    old = fake_pipeline(field=learned)
    fresh = []

    def build():
        new = fake_pipeline()
        fresh.append(new)
        return new

    monkeypatch.setattr(stream, "_build_pipeline", build)
    monkeypatch.setattr(stream, "_pipeline", old)
    monkeypatch.setattr(stream, "_pipeline_source", stream.VIDEO_SOURCE)
    assert stream.reload_pipeline().flow is learned                            # the rules changed, the camera did not

    monkeypatch.setattr(stream, "_pipeline", old)
    monkeypatch.setattr(stream, "_pipeline_source", "rtsp://another-camera/x")
    assert stream.reload_pipeline().flow is not learned                        # another camera: learn from nothing
