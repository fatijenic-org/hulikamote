"""
engine/pipeline.py - zone settings parsing, the simulated light drawn on frames, how the pipeline hands each
vehicle to the specialist jobs and the violation modules, and the model-based checks (helmet / seatbelt /
mirror / plate) run with a fake specialist model so only our own logic is tested.
"""
import json
from types import SimpleNamespace

import numpy as np

from engine import marks
from engine import specialists as sp
from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from engine.specialist_jobs import JOBS, MAX_PLATE_CROPS
from engine.violations import REGISTRY
from tests.helpers import FPS, H, W, Det


def test_new_zones_are_parsed_and_scaled(tmp_path):
    cfg = {
        "video_native_width": 1920,
        "video_native_height": 1080,
        "regions_of_interest": {
            "pedestrian_lane_zones": [{"coordinates": [[0, 0], [100, 0], [100, 100]], "time_limit": 4.0}],
            "illegal_turn_zones": [{"coordinates": [[0, 0], [200, 0], [200, 200]],
                                    "prohibited_vector": {"x_dir": -1.0, "y_dir": 0.0}}],
            "swerving_zones": [{"coordinates": [[0, 0], [300, 0], [300, 300]]}],
        },
    }
    path = tmp_path / "cfg.json"
    path.write_text(json.dumps(cfg))

    pipe = object.__new__(DecoupledPipeline)   # skip model loading
    pipe.rois = pipe._parse_rois(str(path))
    pipe.native_w, pipe.native_h = 1920, 1080

    assert pipe.rois["pedestrian_lane_zones"][0]["time_limit"] == 4.0
    assert pipe.rois["illegal_turn_zones"][0]["vector"] == (-1.0, 0.0)
    assert len(pipe.rois["swerving_zones"]) == 1

    scaled = pipe._get_scaled_rois(960, 540)  # half size
    assert scaled["pedestrian_lane_zones"][0]["polygon"] == [[0, 0], [50, 0], [50, 50]]
    assert scaled["pedestrian_lane_zones"][0]["time_limit"] == 4.0
    assert scaled["illegal_turn_zones"][0]["vector"] == (-1.0, 0.0)
    assert scaled["swerving_zones"][0]["polygon"] == [[0, 0], [150, 0], [150, 150]]


def test_red_light_and_sign_zones_parsed_and_scaled(tmp_path):
    cfg = {
        "video_native_width": 1920, "video_native_height": 1080,
        "regions_of_interest": {
            "red_light_zones": [{"coordinates": [[0, 0], [100, 0], [100, 100]],
                                 "stop_line": [[0, 50], [100, 50]], "light_box": [[10, 10], [20, 30]],
                                 "light": {"mode": "timer", "red_start": 1, "red": 2, "green": 3, "yellow": 1}}],
            "sign_zones": [{"coordinates": [[0, 0], [100, 0], [100, 100]], "sign": "stop",
                            "stop_line": [[0, 80], [100, 80]]}],
        },
    }
    path = tmp_path / "cfg.json"
    path.write_text(json.dumps(cfg))
    pipe = object.__new__(DecoupledPipeline)
    pipe.rois = pipe._parse_rois(str(path))
    pipe.native_w, pipe.native_h = 1920, 1080
    scaled = pipe._get_scaled_rois(960, 540)
    assert scaled["red_light_zones"][0]["stop_line"] == [[0, 25], [50, 25]]
    assert scaled["red_light_zones"][0]["light_box"] == [[5, 5], [10, 15]]
    assert scaled["red_light_zones"][0]["light"]["mode"] == "timer"
    assert scaled["sign_zones"][0]["stop_line"] == [[0, 40], [50, 40]]
    assert pipe.rois["sign_zones"][0]["sign"] == "stop"


def test_simulated_light_drawn_on_frames():
    """Timer mode: the virtual light is drawn top-right with the lit lamp, and the stop line in its colour."""
    from types import SimpleNamespace
    pipe = object.__new__(DecoupledPipeline)
    pipe.native_w = pipe.native_h = 0
    pipe.registry = SimpleNamespace(active_violations=["red_light"])
    pipe._light_readers, pipe._light_states = {}, {}
    pipe.rois = {"red_light_zones": [{
        "polygon": [[0, 300], [640, 300], [640, 479], [0, 479]],
        "stop_line": [[100, 400], [500, 400]],
        "light": {"mode": "timer", "red_start": 0, "red": 10, "green": 10, "yellow": 2},
    }]}
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    REGISTRY["red_light"].prepare(pipe, frame, [], pipe._get_scaled_rois(640, 480)["red_light_zones"], 3.0)
    out = pipe._draw_rois(frame.copy())

    corner = out[:120, 560:].astype(int)               # the light is a real-looking object now: its lit lamp is red, not pure (0, 0, 255)
    red_lamp = (corner[..., 2] > 90) & (corner[..., 2] > 2 * corner[..., 1]) & (corner[..., 2] > 2 * corner[..., 0])
    assert red_lamp.sum() > 20                       # lit red lamp in the top-right corner
    assert tuple(out[400, 300]) == (0, 0, 255)       # stop line drawn red

    REGISTRY["red_light"].prepare(pipe, frame, [], pipe._get_scaled_rois(640, 480)["red_light_zones"], 12.0)
    out = pipe._draw_rois(frame.copy())
    assert tuple(out[400, 300]) == (0, 255, 0)       # green phase


FRAME = np.zeros((1700, 1300, 3), dtype=np.uint8)
WITH, WITHOUT = sp.IDX_RIDER_WITH_HELMET, sp.IDX_RIDER_WITHOUT_HELMET
CLEAR, TINTED, BELT, PHONE, MIRROR = (sp.IDX_CLEAR_WINDOW, sp.IDX_TINTED_WINDOW, sp.IDX_SEATBELT,
                                      sp.IDX_DRIVER_PHONE, sp.IDX_SIDE_MIRROR)
PLATE = sp.IDX_LICENSE_PLATE


def fake_pipe(monkeypatch, active, outputs, model="cabin_specialist", plate_method="smart"):
    """
    Pipeline whose `model` returns the next list of detections from `outputs` on each look (a list of class ids,
    or full detection dicts); every other specialist sees nothing. Returns the pipeline; `pipe.calls` records
    (model name, crop shape) of every look.
    """
    pipe = object.__new__(DecoupledPipeline)
    pipe.registry = SimpleNamespace(active_violations=active, plate_method=plate_method,
                                    get_model=lambda name: SimpleNamespace(name=name))
    pipe.ledger_manager = ActiveLedgerManager()
    pipe.max_riders = 2
    pipe.calls = []
    looks = iter(outputs)

    def detect(session, crop, conf=sp.SEARCH_CONF):
        pipe.calls.append((session.name, crop.shape[:2]))
        if session.name != model:
            return []
        return [d if isinstance(d, dict) else {"class_id": d, "confidence": 0.9, "box": [0, 0, 1, 1]}
                for d in next(looks)]

    monkeypatch.setattr(sp, "detect", detect)
    return pipe


def look_n(pipe, n, cls="car", vy=-9, x=1000, dx=0):
    """Drive one vehicle for 5 settling frames, then take a specialist look on each of the next n frames."""
    for i in range(5 + n):   # 5 frames to settle the vehicle class first
        det = Det(4, [x + dx * i, int(1500 + vy * i), W, H], cls)
        pipe.ledger_manager.update([det], i / FPS)
        if i >= 5:
            pipe._run_specialists(FRAME, 0, [det], pipe.registry.active_violations)
    return pipe.ledger_manager.ledgers[4].violations


def test_no_helmet_needs_a_majority_of_looks(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_helmet"], [[WITHOUT]] * 3, model="helmet_specialist")
    assert "no_helmet" in look_n(pipe, 3, "motorcycle")
    pipe = fake_pipe(monkeypatch, ["no_helmet"], [[WITHOUT]] + [[WITH]] * 4, model="helmet_specialist")   # one wrong guess
    assert "no_helmet" not in look_n(pipe, 5, "motorcycle")
    pipe = fake_pipe(monkeypatch, ["no_helmet"], [[]] * 5, model="helmet_specialist")                      # no rider found: no vote
    assert "no_helmet" not in look_n(pipe, 5, "motorcycle")


def test_no_helmet_only_looks_at_motorcycles(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_helmet"], [[WITHOUT]] * 6, model="helmet_specialist")
    assert "no_helmet" not in look_n(pipe, 6, "car")
    assert not [c for c in pipe.calls if c[0] == "helmet_specialist"]


def test_no_seatbelt_vote_and_tint_gate(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_seatbelt"], [[CLEAR]] * 4)
    assert "no_seatbelt" in look_n(pipe, 4)
    pipe = fake_pipe(monkeypatch, ["no_seatbelt"], [[CLEAR]] * 3 + [[CLEAR, BELT]] * 2)
    assert "no_seatbelt" not in look_n(pipe, 5)
    pipe = fake_pipe(monkeypatch, ["no_seatbelt"], [[TINTED]] * 6)              # can't see inside: no judgement
    assert "no_seatbelt" not in look_n(pipe, 6)
    pipe = fake_pipe(monkeypatch, ["no_seatbelt"], [[CLEAR]] * 6)               # motorcycles have no seatbelt rule
    assert "no_seatbelt" not in look_n(pipe, 6, "motorcycle")


def test_distracted_driving_needs_a_phone_in_most_looks(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["distracted_driving"], [[CLEAR, PHONE]] * 4)
    assert "distracted_driving" in look_n(pipe, 4)
    pipe = fake_pipe(monkeypatch, ["distracted_driving"], [[CLEAR, PHONE]] + [[CLEAR]] * 4)
    assert "distracted_driving" not in look_n(pipe, 5)
    pipe = fake_pipe(monkeypatch, ["distracted_driving"], [[TINTED, PHONE]] * 5)  # tinted window: nothing to judge
    assert "distracted_driving" not in look_n(pipe, 5)


def test_one_cabin_look_serves_every_cabin_violation(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_seatbelt", "distracted_driving"], [[CLEAR, PHONE]] * 4)
    violations = look_n(pipe, 4)
    assert {"no_seatbelt", "distracted_driving"} <= violations
    assert len([c for c in pipe.calls if c[0] == "cabin_specialist"]) == 4      # 4 looks, not 8


def test_missing_mirror_only_judged_from_front_or_rear(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["missing_side_mirror"], [[MIRROR]] * 5)
    assert "missing_side_mirror" in look_n(pipe, 5, "motorcycle")
    pipe = fake_pipe(monkeypatch, ["missing_side_mirror"], [[MIRROR, MIRROR]] * 5)
    assert "missing_side_mirror" not in look_n(pipe, 5, "motorcycle")
    pipe = fake_pipe(monkeypatch, ["missing_side_mirror"], [[MIRROR]] * 8)      # crossing sideways: one mirror is always hidden
    assert "missing_side_mirror" not in look_n(pipe, 8, "motorcycle", vy=0, x=500, dx=9)


def test_helmet_check_boxes_the_bare_rider(monkeypatch):
    # fake specialist: a bare rider and a helmeted rider, boxes in the pixels of the crop it was shown
    bare = {"class_id": WITHOUT, "confidence": 0.9, "box": [32, 0, 32, 64]}
    helmeted = {"class_id": WITH, "confidence": 0.9, "box": [60, 0, 30, 64]}
    pipe = fake_pipe(monkeypatch, ["no_helmet"], [[bare, helmeted]] * 3, model="helmet_specialist")
    for i in range(8):
        det = Det(4, [1000, 1500 - 9 * i, W, H], "motorcycle")
        pipe.ledger_manager.update([det], i / FPS)
        if i >= 5:
            pipe._run_specialists(FRAME, 0, [det], pipe.registry.active_violations)
    ledger = pipe.ledger_manager.ledgers[4]
    assert "no_helmet" in ledger.violations
    labels = {label: box for box, label, _ in marks.current_marks(ledger, det.bbox)}
    assert set(labels) == {"NO HELMET", "helmet"}
    assert labels["NO HELMET"] == [1032, 1437, 32, 64]          # placed on the frame where the model saw it
    frame = np.zeros((1600, 1600, 3), dtype=np.uint8)
    marks.draw_marks(frame, ledger, det.bbox)
    assert (frame[1450, 1032] == marks.RED).all()               # red box edge drawn on the frame


def test_helmet_look_covers_the_motorcycle_and_its_riders(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_helmet"], [[]], model="helmet_specialist")
    moto = Det(4, [500, 800, 100, 80], "motorcycle")
    rider = Det(9, [510, 730, 40, 120], "person")               # feet on the bike, head sticks out 70 px above its box
    pipe.ledger_manager.update([moto, rider], 0.0)
    pipe._run_specialists(FRAME, 0, [moto, rider], ["no_helmet"])
    assert ("helmet_specialist", (150, 100)) in pipe.calls      # from the rider's head (y 730) to the bike's wheels (y 880)


# ─── Plate job ───────────────────────────────────────────────────────────────

def plate_look(pipe, bbox=(100, 100, 200, 150), cls="car"):
    det = Det(4, list(bbox), cls)
    pipe.ledger_manager.update([det], 0.0)
    job = next(j for j in JOBS if j.name == "plate")
    return det, job.look(pipe, FRAME, det, [det])


def test_plate_is_searched_in_the_whole_vehicle(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_plate"], [[]], model="plate_specialist")
    det, look = plate_look(pipe)
    assert ("plate_specialist", (150, 200)) in pipe.calls       # the full vehicle box, not a bottom strip
    assert look.found is False and look.search_box == [100, 100, 200, 150]


def test_plate_found_is_cached_and_cropped_for_the_ocr(monkeypatch):
    plate = {"class_id": PLATE, "confidence": 0.8, "box": [60, 100, 80, 30]}
    pipe = fake_pipe(monkeypatch, ["no_plate"], [[plate]], model="plate_specialist")
    det, look = plate_look(pipe)
    ledger = pipe.ledger_manager.ledgers[4]
    assert look.found is True
    assert ledger.plate_bbox == [160, 200, 80, 30]              # in frame pixels
    assert len(ledger.plate_crops) == 1
    tight, context, _t = ledger.plate_crops[0]
    assert tight.shape[0] >= 30 and tight.shape[1] >= 80        # the plate plus a 10% margin
    assert context.shape[:2] == (150, 200)                      # the whole vehicle with the plate boxed


def test_plate_crops_are_capped(monkeypatch):
    plate = {"class_id": PLATE, "confidence": 0.8, "box": [60, 100, 80, 30]}
    pipe = fake_pipe(monkeypatch, ["no_plate"], [[plate]] * (MAX_PLATE_CROPS + 5), model="plate_specialist")
    det, _ = plate_look(pipe)
    job = next(j for j in JOBS if j.name == "plate")
    for _ in range(MAX_PLATE_CROPS + 3):
        job.look(pipe, FRAME, det, [det])
    assert len(pipe.ledger_manager.ledgers[4].plate_crops) == MAX_PLATE_CROPS


def test_direct_ocr_hands_the_bumper_strip_to_the_reader(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_plate"], [], model="plate_specialist", plate_method="direct_ocr")
    det, look = plate_look(pipe)
    assert pipe.calls == []                                     # no detector in this mode
    assert look.found is True and look.search_box == [100, 190, 200, 60]    # lower 40% of the box
    assert pipe.ledger_manager.ledgers[4].plate_crops[0][0].shape[:2] == (60, 200)


def test_plate_job_skips_vehicles_that_are_too_small(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_plate"], [[]], model="plate_specialist")
    assert plate_look(pipe, bbox=(100, 100, 15, 150))[1] is None
    assert pipe.calls == []


def test_no_plate_is_pending_then_decided_when_the_car_leaves(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_plate"], [[]] * 12, model="plate_specialist")
    violations = look_n(pipe, 8)
    ledger = pipe.ledger_manager.ledgers[4]
    assert "no_plate" not in violations and "no_plate" in ledger.pending      # a suspicion, not yet a ticket
    pipe.ledger_manager.decide_end_of_track(ledger)
    assert "no_plate" in ledger.violations


def test_a_plate_seen_later_clears_the_no_plate_suspicion(monkeypatch):
    plate = {"class_id": PLATE, "confidence": 0.8, "box": [60, 100, 80, 30]}
    pipe = fake_pipe(monkeypatch, ["no_plate"], [[]] * 7 + [[plate]], model="plate_specialist")
    look_n(pipe, 8)
    ledger = pipe.ledger_manager.ledgers[4]
    pipe.ledger_manager.decide_end_of_track(ledger)
    assert "no_plate" not in ledger.violations


# ─── How the pipeline hands work to the violation modules ────────────────────

def test_specialists_take_turns_across_vehicles(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["no_seatbelt"], [[CLEAR]] * 10)
    cars = [Det(1, [100, 800, W, H]), Det(2, [400, 800, W, H])]
    pipe.ledger_manager.update(cars, 0.0)
    cabin_looks = lambda: len([c for c in pipe.calls if c[0] == "cabin_specialist"])
    pipe._run_specialists(FRAME, 0, cars, ["no_seatbelt"])      # (0 + 0) % 5 == 0: only the first car
    assert cabin_looks() == 1
    pipe._run_specialists(FRAME, 4, cars, ["no_seatbelt"])      # (4 + 1) % 5 == 0: only the second car
    assert cabin_looks() == 2


def test_judge_runs_zone_rules_and_frame_checks(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["counterflow", "overloading"], [])
    zones = {"counterflow_zones": [{"polygon": [[0, 0], [2000, 0], [2000, 2000], [0, 2000]], "vector": (0.0, -1.0)}]}
    for i in range(30):
        moto = Det(4, [1000, 500 + 9 * i, W, H], "motorcycle")                       # drives DOWN, against the arrow
        people = [Det(10 + k, [1000 + 10 * k, 500 + 9 * i - 40, 30, 100], "person") for k in range(3)]   # 3 riders
        detections = [moto] + people
        pipe.ledger_manager.update(detections, i / FPS)
        pipe._judge(FRAME, detections, zones, pipe.registry.active_violations, i / FPS)
    flagged = pipe.ledger_manager.ledgers[4].violations
    assert {"counterflow", "overloading"} <= flagged
    assert not pipe.ledger_manager.ledgers[10].violations        # people are never judged by the zone rules


def test_violations_that_are_not_active_do_not_run(monkeypatch):
    pipe = fake_pipe(monkeypatch, ["overloading"], [])
    zones = {"counterflow_zones": [{"polygon": [[0, 0], [2000, 0], [2000, 2000], [0, 2000]], "vector": (0.0, -1.0)}]}
    for i in range(30):
        car = Det(4, [1000, 500 + 9 * i, W, H])
        pipe.ledger_manager.update([car], i / FPS)
        pipe._judge(FRAME, [car], zones, ["overloading"], i / FPS)
    assert "counterflow" not in pipe.ledger_manager.ledgers[4].violations
