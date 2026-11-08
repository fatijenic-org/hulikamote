"""
engine/privacy.py - heads and other vehicles' plates are blurred before a photo is saved, the violator's plate is not,
and the pipeline only ever saves the blurred copy. Photos are random noise, so "blurred" is easy to measure.
"""
from types import SimpleNamespace

import cv2
import numpy as np
import pytest

from engine import privacy
from engine.ledger import ActiveLedgerManager
from engine.pipeline import DecoupledPipeline
from tests.helpers import Det


def noise(h=640, w=640, seed=1):
    return np.random.default_rng(seed).integers(0, 256, (h, w, 3), dtype=np.uint8)


def detail(image):
    """How much fine detail is left: random noise has a lot, a blurred patch almost none."""
    return float(cv2.Laplacian(cv2.cvtColor(image, cv2.COLOR_BGR2GRAY), cv2.CV_64F).var())


def region(image, box):
    x, y, w, h = box
    return image[y:y + h, x:x + w]


def untouched(a, b, box):
    return np.array_equal(region(a, box), region(b, box))


def blurred(after, before, box):
    return detail(region(after, box)) < detail(region(before, box)) / 50


# ─── the blur itself ─────────────────────────────────────────────────────────

def test_a_box_is_blurred_hard_and_nothing_outside_it_changes():
    frame, original = noise(), noise()
    privacy.blur_boxes(frame, [(100, 100, 80, 80)])
    assert blurred(frame, original, (100, 100, 80, 80))
    assert untouched(frame, original, (0, 0, 640, 100)) and untouched(frame, original, (200, 0, 440, 640))


@pytest.mark.parametrize("box", [(-50, -50, 100, 100), (600, 600, 200, 200), (10, 10, 0, 40), (10, 10, 40, 0), (700, 700, 50, 50), (5, 5, 3, 3)])
def test_boxes_hanging_off_the_photo_or_tiny_ones_do_not_break_it(box):
    privacy.blur_boxes(noise(), [box])


# ─── who gets a box ──────────────────────────────────────────────────────────

def test_every_person_gets_a_head_box_and_cars_get_none():
    people = [Det(1, [100, 200, 60, 180], "person"), Det(2, [300, 300, 200, 150], "car")]
    boxes = privacy.head_boxes(people)
    assert len(boxes) == 1
    x, y, w, h = boxes[0]
    assert (x, y) < (100, 200)                                  # a little wider and higher than the top 30% of the person
    assert 200 - y < 20 and abs((y + h) - (200 + 180 * privacy.HEAD_SHARE)) < 30        # it covers the head, not the whole body


def test_a_bike_whose_rider_was_found_adds_nothing_but_one_without_gets_a_head_zone_above_it():
    bike = Det(1, [250, 300, 120, 160], "motorcycle")
    rider = Det(5, [270, 220, 60, 200], "person")
    assert len(privacy.head_boxes([bike, rider])) == 1                               # only the rider's own head box

    (x, y, w, h), = privacy.head_boxes([bike])                                      # nobody detected on it
    assert y < 300 and x >= 250 and x + w <= 370 and y + h > 300                    # the zone where a rider's head sticks out


def test_other_vehicles_plates_are_boxed_but_the_violators_is_not():
    violator, other, bystander = Det(1, [0, 0, 200, 100], "car"), Det(2, [400, 0, 200, 100], "car"), Det(3, [0, 300, 50, 120], "person")
    ledgers = {2: SimpleNamespace(plate_bbox=[470, 80, 60, 20])}
    (box,) = privacy.other_plate_boxes([violator, other, bystander], ledgers, keep_track_id=1)
    x, y, w, h = box
    assert x <= 470 and y <= 80 and x + w >= 530 and y + h >= 100                   # the plate the model found, with a margin


def test_a_vehicle_whose_plate_was_not_found_yet_gets_its_whole_lower_part_blurred():
    other = Det(2, [400, 100, 200, 100], "motorcycle")
    (x, y, w, h), = privacy.other_plate_boxes([other], {2: SimpleNamespace(plate_bbox=None)}, keep_track_id=1)
    assert x == 400 and x + w == 600 and y >= 100 + 50 and y + h <= 200


# ─── a whole photo ───────────────────────────────────────────────────────────

def scene():
    """A violator with a readable plate, a rider whose head sticks out above, and another car behind."""
    violator = Det(1, [200, 300, 200, 160], "car")
    rider = Det(5, [250, 120, 60, 200], "person")
    other = Det(2, [420, 300, 180, 150], "car")
    ledgers = {1: SimpleNamespace(plate_bbox=[260, 420, 80, 30]), 2: SimpleNamespace(plate_bbox=[480, 410, 60, 22])}
    return [violator, rider, other], ledgers


def test_heads_and_other_plates_are_blurred_and_the_violators_plate_is_exactly_as_it_was():
    detections, ledgers = scene()
    frame = noise()
    before = frame.copy()
    out = privacy.anonymize(frame, detections, ledgers, keep_track_id=1)

    assert np.array_equal(frame, before)                                            # the original frame is not touched
    assert blurred(out, before, (255, 125, 50, 40))                                 # the head
    assert blurred(out, before, (485, 412, 50, 18))                                 # the other plate
    assert untouched(out, before, (260, 420, 80, 30))                               # the violator's plate: readable
    assert untouched(out, before, (0, 480, 640, 160))                               # far from everyone: untouched


def test_the_violators_plate_stays_readable_even_when_another_vehicles_box_covers_it():
    violator = Det(1, [200, 300, 200, 160], "car")
    in_front = Det(2, [150, 250, 300, 250], "truck")                                # its lower part lies on the violator's plate
    ledgers = {1: SimpleNamespace(plate_bbox=[260, 420, 80, 30])}
    frame = noise()
    out = privacy.anonymize(frame, [violator, in_front], ledgers, keep_track_id=1)
    assert untouched(out, frame, (260, 420, 80, 30))


def test_an_empty_scene_is_returned_unchanged():
    frame = noise()
    assert np.array_equal(privacy.anonymize(frame, [], {}), frame)


# ─── the picture kept next to a plate crop ───────────────────────────────────

def test_the_vehicle_picture_beside_a_plate_crop_loses_its_heads_but_keeps_the_plate():
    crop, original = noise(200, 200), noise(200, 200)
    rider = Det(5, [1050, 1010, 60, 100], "person")                                  # in frame coordinates
    privacy.anonymize_crop(crop, (1000, 1000), [rider], keep=(20, 150, 80, 30))
    assert blurred(crop, original, (55, 15, 40, 20))
    assert untouched(crop, original, (20, 150, 80, 30))


# ─── what the pipeline saves ─────────────────────────────────────────────────

def capture_setup(monkeypatch):
    """A pipeline that 'saves' photos into a list instead of onto the disk, with a bike, its rider and a plate."""
    import yolo_inference
    saved = []
    monkeypatch.setattr(yolo_inference.YoloInference, "save_snapshot",
                        staticmethod(lambda image, folder: saved.append(image.copy()) or f"snapshots/evidence/{len(saved)}.jpg"))
    monkeypatch.setattr(yolo_inference, "get_inference", lambda: SimpleNamespace(draw_detections=lambda frame, dets: frame))
    pipe = object.__new__(DecoupledPipeline)
    pipe.ledger_manager = ActiveLedgerManager()
    pipe.evidence_gap = 1
    pipe._draw_rois = lambda frame: frame
    bike, rider = Det(1, [250, 300, 120, 160], "motorcycle"), Det(5, [270, 220, 60, 200], "person")
    pipe.ledger_manager.update([bike, rider], 0.0)
    pipe.ledger_manager.ledgers[1].plate_bbox = [280, 430, 60, 22]
    return pipe, saved, bike, rider


def test_the_saved_photo_and_both_crops_show_no_head_but_a_readable_plate(monkeypatch):
    pipe, saved, bike, rider = capture_setup(monkeypatch)
    frame = noise()
    pipe._capture_evidence_frame(frame, bike, 1, [bike, rider])

    assert len(saved) == 3                                                           # the photo, the vehicle crop, the wider crop
    head = (280, 225, 40, 30)
    photo, car_crop, clean = saved
    assert blurred(photo, frame, head)
    assert untouched(photo, frame, (280, 430, 60, 22))                               # plate still readable
    assert untouched(car_crop, frame[300:460, 250:370], (30, 130, 60, 22))           # the crop is cut from the blurred frame, plate intact
    cx, cy = 250 - 20, 300 - int(160 * 0.6)                                          # where the wider crop starts
    assert detail(region(clean, (head[0] - cx, head[1] - cy, head[2], head[3]))) < detail(region(frame, head)) / 50


def test_when_the_blur_fails_nothing_is_saved(monkeypatch):
    pipe, saved, bike, rider = capture_setup(monkeypatch)
    monkeypatch.setattr(privacy, "anonymize", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom")))
    pipe._capture_evidence_frame(noise(), bike, 1, [bike, rider])
    assert saved == [] and pipe.ledger_manager.ledgers[1].evidence_paths == []


def test_with_the_blur_switched_off_the_photos_show_the_head(monkeypatch):
    pipe, saved, bike, rider = capture_setup(monkeypatch)
    pipe.blur_privacy = False                                                        # the temporary wizard switch
    frame = noise()
    pipe._capture_evidence_frame(frame, bike, 1, [bike, rider])

    photo = saved[0]
    assert untouched(photo, frame, (280, 225, 40, 30))                               # head not blurred
    assert DecoupledPipeline.blur_privacy is True                                    # and the default stays ON
