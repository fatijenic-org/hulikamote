"""yolo_inference.py - the detection object and the injected session factory."""
from unittest.mock import MagicMock, patch

from yolo_inference import YoloInference


def test_yolo_inference_dependency_injection(tmp_path):
    """Verify that YoloInference accepts and invokes an injected session_factory."""
    mock_factory = MagicMock()
    mock_session = MagicMock()
    mock_session.get_inputs.return_value = [MagicMock(name="images")]
    mock_session.get_providers.return_value = ["CPUExecutionProvider"]
    mock_factory.return_value = mock_session

    dummy_model = tmp_path / "yolov8n.onnx"
    dummy_model.write_bytes(b"dummy")

    with patch("yolo_inference.MODEL_PATH", dummy_model):
        engine = YoloInference(session_factory=mock_factory)
        mock_factory.assert_called_with(str(dummy_model))
        assert engine._session == mock_session


def _preds(candidates):
    """What the model returns for one frame: one box per (coco_class_id, confidence) in `candidates`."""
    import numpy as np
    preds = np.zeros((84, 200), dtype=np.float32)                   # (4 + 80 classes, boxes): a real model returns thousands of
                                                                    # boxes, and infer() reads "more boxes than rows" as the layout
    for i, (class_id, confidence) in enumerate(candidates):
        preds[0:4, i] = [100 + 150 * i, 320, 80, 80]                # cx, cy, w, h: separate boxes, no overlap
        preds[4 + class_id, i] = confidence
    return [preds[np.newaxis]]


def _engine_that_returns(tmp_path, candidates):
    """A YoloInference whose 'model' answers with one box per (coco_class_id, confidence) in `candidates`."""
    from types import SimpleNamespace

    session = MagicMock()
    session.get_inputs.return_value = [SimpleNamespace(name="images")]
    session.get_providers.return_value = ["CPUExecutionProvider"]
    session.run.return_value = _preds(candidates)
    model = tmp_path / "yolov8n.onnx"
    model.write_bytes(b"dummy")
    with patch("yolo_inference.MODEL_PATH", model):
        return YoloInference(session_factory=MagicMock(return_value=session))


def test_a_motorcycle_needs_a_lower_confidence_than_other_classes(tmp_path):
    """A CCTV motorcycle scores below its rider; with one cutoff for everything the bike was dropped and only the person stayed."""
    import numpy as np
    PERSON, CAR, MOTORCYCLE = 0, 2, 3                               # COCO class ids
    engine = _engine_that_returns(tmp_path, [(MOTORCYCLE, 0.30), (CAR, 0.30), (PERSON, 0.30), (CAR, 0.50)])
    kept = [(d.cls, round(d.confidence, 2)) for d in engine.infer(np.zeros((640, 640, 3), dtype=np.uint8))]
    assert ("motorcycle", 0.30) in kept                             # below 0.45 but above the motorcycle cutoff
    assert ("car", 0.50) in kept                                    # normal cutoff still passes
    assert ("car", 0.30) not in kept and ("person", 0.30) not in kept   # other classes keep the 0.45 cutoff


def test_class_thresholds_follow_the_class_list(tmp_path):
    import yolo_inference as yi
    engine = _engine_that_returns(tmp_path, [(2, 0.9)])
    thresholds = engine._class_thresholds(80)
    assert thresholds[engine._classes.index("motorcycle")] == yi.CLASS_CONFIDENCE["motorcycle"]
    assert thresholds[engine._classes.index("car")] == yi.CONFIDENCE_THRESHOLD


PERSON, CAR, MOTORCYCLE = 0, 2, 3                                   # COCO class ids


class FakeTracker:
    """Follows every box it is shown (id = which 150 px column it sits in) and remembers the boxes it was given."""

    def __init__(self):
        self.boxes_seen = []

    def update_with_detections(self, sv_dets, frame):
        import numpy as np
        import supervision as sv
        if len(sv_dets.xyxy) == 0:
            return sv.Detections.empty()
        self.boxes_seen.extend(tuple(int(v) for v in box) for box in sv_dets.xyxy)
        ids = np.array([1 + int(box[0] // 150) for box in sv_dets.xyxy])
        return sv.Detections(xyxy=sv_dets.xyxy, confidence=sv_dets.confidence, class_id=sv_dets.class_id, tracker_id=ids)


def _frame():
    import numpy as np
    return np.zeros((640, 640, 3), dtype=np.uint8)


def test_riders_and_vehicles_never_share_a_tracker(tmp_path):
    """A rider box next to its motorcycle in one tracker took over the bike's id whenever the bike was missed."""
    import yolo_inference as yi
    engine = _engine_that_returns(tmp_path, [(MOTORCYCLE, 0.5), (PERSON, 0.6), (CAR, 0.6)])
    engine.tracker, engine.people_tracker = FakeTracker(), FakeTracker()
    dets = {d.cls: d for d in engine.infer(_frame())}
    assert len(engine.tracker.boxes_seen) == 2 and len(engine.people_tracker.boxes_seen) == 1   # the person went to the people tracker only
    assert dets["motorcycle"].track_id == 1 and dets["car"].track_id == 3
    assert dets["person"].track_id == yi.PERSON_ID_BASE + 2           # its own id space: it can never equal a vehicle id


def test_a_missed_motorcycle_leaves_its_rider_without_the_bikes_track(tmp_path):
    """Frame 1: bike + rider. Frame 2: the bike is missed. The rider must not inherit the bike's id."""
    import yolo_inference as yi
    engine = _engine_that_returns(tmp_path, [(MOTORCYCLE, 0.5), (PERSON, 0.6)])
    engine.tracker, engine.people_tracker = FakeTracker(), FakeTracker()
    first = {d.cls: d.track_id for d in engine.infer(_frame())}
    engine._session.run.return_value = _preds([(PERSON, 0.6)])         # only the rider this time (still the 1st column: x1 = 60)
    second = engine.infer(_frame())
    assert [d.cls for d in second] == ["person"]
    assert second[0].track_id >= yi.PERSON_ID_BASE and second[0].track_id != first["motorcycle"]


def test_real_trackers_keep_the_two_id_spaces_apart(tmp_path):
    import yolo_inference as yi
    engine = _engine_that_returns(tmp_path, [(MOTORCYCLE, 0.5), (PERSON, 0.6), (CAR, 0.6)])
    for _ in range(3):
        for d in engine.infer(_frame()):
            assert d.track_id == -1 or (d.track_id >= yi.PERSON_ID_BASE) == (d.cls == "person")


def test_one_odd_frame_does_not_change_a_vehicles_class(tmp_path):
    """A motorcycle the model calls 'car' for a single frame is still a motorcycle (no label flicker)."""
    engine = _engine_that_returns(tmp_path, [(MOTORCYCLE, 0.5)])
    engine.tracker, engine.people_tracker = FakeTracker(), FakeTracker()
    classes = []
    for looks in [(MOTORCYCLE, 0.5)] * 4 + [(CAR, 0.5)] + [(MOTORCYCLE, 0.5)] * 2:
        engine._session.run.return_value = _preds([looks])
        classes.append(engine.infer(_frame())[0].cls)
    assert classes == ["motorcycle"] * 7


def test_a_vehicle_that_keeps_looking_like_another_class_does_change(tmp_path):
    """The vote is not stuck: when the new class wins for the whole window, the label follows."""
    import yolo_inference as yi
    engine = _engine_that_returns(tmp_path, [(MOTORCYCLE, 0.5)])
    engine.tracker, engine.people_tracker = FakeTracker(), FakeTracker()
    last = None
    for looks in [(MOTORCYCLE, 0.5)] * 3 + [(CAR, 0.6)] * yi.CLASS_VOTES:
        engine._session.run.return_value = _preds([looks])
        last = engine.infer(_frame())[0].cls
    assert last == "car"


def test_resetting_the_tracker_forgets_classes_and_people(tmp_path):
    engine = _engine_that_returns(tmp_path, [(MOTORCYCLE, 0.5), (PERSON, 0.6)])
    engine.infer(_frame())
    assert engine._class_votes
    engine.reset_tracker()
    assert not engine._class_votes


def test_real_detection_object_accepts_every_field_the_pipeline_sets():
    """The pipeline writes these onto YoloDetection (which uses __slots__); a missing slot crashes analysis."""
    from yolo_inference import YoloDetection
    d = YoloDetection("car", 0.9, [0, 0, 10, 10], "car", track_id=1)
    d.is_violator, d.violation_type = True, "no_plate"
    d.plate_text, d.plate_bbox = "ABC123", [1, 2, 3, 4]
    d.marks = [{"bbox": [1, 2, 3, 4], "label": "NO PLATE FOUND"}]
    assert d.marks[0]["label"] == "NO PLATE FOUND"
