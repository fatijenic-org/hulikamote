"""What the boxes say and where they go: plate + type (never an id), vehicles only, labels kept inside the picture."""
import numpy as np

from engine import marks
from yolo_inference import YoloDetection, box_specs, draw_specs


def det(cls="motorcycle", bbox=(100, 100, 80, 60), plate=None, violation=None, track_id=7):
    d = YoloDetection(cls, 0.9, list(bbox), violation or cls, track_id=track_id, is_violator=bool(violation))
    d.plate_text = plate
    return d


def test_label_is_plate_and_type_or_just_vehicle():
    assert box_specs([det(plate="ABC 1234")])[0]["lines"] == ["ABC 1234 - MOTORCYCLE"]
    assert box_specs([det()])[0]["lines"] == ["VEHICLE"]


def test_violation_keeps_plate_and_type():
    lines = box_specs([det("car", plate="XYZ 987", violation="no_seatbelt+overloading?")])[0]["lines"]
    assert lines == ["NO SEATBELT", "OVERLOADING?", "XYZ 987 - CAR"]
    assert box_specs([det("car", violation="red_light")])[0]["lines"] == ["RED LIGHT", "VEHICLE"]


def test_no_vehicle_id_anywhere_in_the_labels():
    for spec in box_specs([det(track_id=42), det(plate="ABC 1234", track_id=43)]):
        assert not any("ID" in line.split() or "42" in line or "43" in line for line in spec["lines"])


def test_only_vehicles_get_a_box():
    people = [det("person", track_id=1_000_001), det("traffic light"), det("bicycle")]
    assert box_specs(people) == []
    assert len(box_specs(people + [det("truck")])) == 1


def test_label_block_stays_inside_when_the_vehicle_is_half_outside():
    # box above the top edge and past the right edge: the block is clamped into a 640x360 picture
    x, y = marks.place_block([600, -50, 200, 120], (640, 360), 120, 40)
    assert 0 <= x <= 640 - 120 and 0 <= y <= 360 - 40
    x, y = marks.place_block([-80, 300, 100, 100], (640, 360), 120, 40)       # left and bottom edges
    assert x == 0 and y + 40 <= 360
    assert marks.place_block([100, 200, 50, 50], (640, 360), 120, 40) == (100, 160)   # room above: just above the box


def test_drawing_near_the_edges_does_not_fail_and_draws():
    frame = np.zeros((360, 640, 3), np.uint8)
    specs = box_specs([det("car", bbox=(560, -20, 150, 100), plate="ABC 1234", violation="wrong_lane")])
    draw_specs(frame, specs)
    assert frame.any()


def test_lines_are_thinner_than_before():
    import cv2
    assert [marks.line_width(t) for t in (1, 2, 3)] == [1, 2, 2]
    box = [500, 500, 300, 200]
    now = np.zeros((1080, 1920, 3), np.uint8)
    draw_specs(now, [{"box": box, "color": (0, 255, 0), "lines": ["VEHICLE"], "plate": None}])
    before = np.zeros_like(now)
    cv2.rectangle(before, (500, 500), (800, 700), (0, 255, 0), 3)             # the old width at 1920 px
    assert int((now[600, 490:510, 1] == 255).sum()) < int((before[600, 490:510, 1] == 255).sum())
