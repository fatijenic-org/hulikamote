"""
The Labeller's blur is its own layer, apart from the labels: a person draws areas to blur (or accepts the program's guess of
heads and number plates), and whatever is inside an area is blurred in the saved picture. Temporary folders and fake detectors only.

    hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests/test_pii_blur.py -q -p no:cacheprovider
"""
import sys
from pathlib import Path

import cv2
import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from harvest_tool import folder_labeller as fl           # noqa: E402
from harvest_tool import pii_blur                        # noqa: E402
from harvest_tool.detect import Det                      # noqa: E402
from harvest_tool.store import Item                      # noqa: E402
from harvest_tool.web import HarvestApp                  # noqa: E402
from test_folder_labeller import env, label_all, write_img  # noqa: E402,F401  (env is a fixture)


class FakeDet:
    """A detector that answers with whatever [fn] makes of the picture it is given."""

    def __init__(self, fn, names=None):
        self.fn, self.names = fn, names or {}

    def detect(self, img, conf=0.25, **_):
        return self.fn(img)


class FakeDetectors:
    def __init__(self, **by_model):
        self.by_model = by_model

    def get(self, model):
        return self.by_model.get(model)


def street(width=200, height=100):
    return np.full((height, width, 3), 120, np.uint8)


def vehicle_finder(*dets):
    return FakeDet(lambda img: list(dets), names={0: "person", 1: "car", 2: "motorcycle"})


PERSON = Det(0, 0.9, 20, 10, 60, 60)
CAR = Det(1, 0.9, 100, 20, 190, 90)


def contains(box, x, y):
    bx, by, bw, bh = box
    return bx <= x <= bx + bw and by <= y <= by + bh


# ─── finding the personal details ────────────────────────────────────────────

def test_the_head_of_a_person_is_the_top_of_their_box():
    boxes = pii_blur.find_pii(street(), heads=True, plates=False, vehicle_detector=vehicle_finder(PERSON, CAR))
    assert len(boxes) == 1 and contains(boxes[0], 40, 15) and not contains(boxes[0], 40, 50)   # the head, not the body


def test_the_plate_comes_from_the_plate_model_inside_the_vehicle():
    plates = FakeDet(lambda img: [Det(0, 0.9, 30, 40, 60, 55)] if img.shape[1] == 90 else [])   # found in the car's crop
    boxes = pii_blur.find_pii(street(), heads=False, plates=True, vehicle_detector=vehicle_finder(PERSON, CAR), plate_detector=plates)
    assert len(boxes) == 1 and contains(boxes[0], 140, 67)                                       # 100 + 30..60, 20 + 40..55


def test_without_a_plate_model_the_lower_part_of_the_vehicle_is_covered():
    boxes = pii_blur.find_pii(street(), heads=False, plates=True, vehicle_detector=vehicle_finder(CAR))
    assert len(boxes) == 1 and contains(boxes[0], 145, 80) and not contains(boxes[0], 145, 30)


def test_a_plate_in_a_picture_that_is_already_a_crop_is_found_in_the_whole_picture():
    plates = FakeDet(lambda img: [Det(0, 0.9, 60, 60, 120, 85)])
    boxes = pii_blur.find_pii(street(), heads=False, plates=True, vehicle_detector=None, plate_detector=plates)
    assert len(boxes) == 1 and contains(boxes[0], 90, 72)


def test_a_motorcycle_with_no_rider_found_gets_a_head_zone_above_it():
    bike = Det(2, 0.9, 50, 50, 100, 90)
    boxes = pii_blur.find_pii(street(), heads=True, plates=False, vehicle_detector=vehicle_finder(bike))
    assert len(boxes) == 1 and boxes[0][1] < 50 + 5 and contains(boxes[0], 75, 40)


def test_a_motorcycle_whose_rider_was_found_gets_no_extra_zone():
    bike = Det(2, 0.9, 50, 50, 100, 90)
    rider = Det(0, 0.9, 60, 25, 90, 75)
    boxes = pii_blur.find_pii(street(), heads=True, plates=False, vehicle_detector=vehicle_finder(bike, rider))
    assert len(boxes) == 1                                                                       # the rider's head only


def test_nothing_is_searched_when_nothing_is_asked_for():
    assert pii_blur.find_pii(street(), heads=False, plates=False, vehicle_detector=vehicle_finder(PERSON, CAR)) == []


def test_a_model_never_loses_its_own_target():
    assert pii_blur.allowed("plate_specialist", True, True) == (True, False)       # plates are what it learns
    assert pii_blur.allowed("helmet_specialist", True, True) == (False, True)      # heads are what it learns
    assert pii_blur.allowed("cabin_specialist", True, True) == (True, True)
    assert pii_blur.allowed("primary_anchor", True, False) == (True, False)


# ─── blurring ────────────────────────────────────────────────────────────────

def test_blurring_hides_detail_inside_the_box_and_leaves_the_rest_alone():
    rng = np.random.default_rng(1)
    img = rng.integers(0, 255, (100, 200, 3), dtype=np.uint8)
    before = img.copy()
    pii_blur.blur_regions(img, [(40, 20, 60, 40)])
    assert img[20:60, 40:100].std() < before[20:60, 40:100].std() / 3
    assert np.array_equal(img[:20], before[:20]) and np.array_equal(img[:, :40], before[:, :40])


# ─── in the Labeller ─────────────────────────────────────────────────────────

def helper_models(paths):
    return FakeDetectors(primary_anchor=vehicle_finder(PERSON, CAR),
                         plate_specialist=FakeDet(lambda img: [Det(0, 0.9, 30, 40, 60, 55)] if img.shape[1] == 90 else []))


def folder_item(store, task, ending):
    return next(i for i in store.items("plate_specialist", ("label", "check"), task=task) if i.src_path.endswith(ending))


def test_pre_drawing_guesses_head_blur_in_its_own_layer_and_never_plates_on_the_plate_model(env):
    paths, store, evidence = env
    write_img(evidence / "1794600000000.jpg", 200, 100, seed=5)
    r = fl.scan(paths, store, "plate_specialist", evidence)
    got = fl.suggest_batch(paths, store, "plate_specialist", r["task"], n=50, detectors=helper_models(paths), heads=True, plates=True)
    assert got >= 1
    item = folder_item(store, r["task"], "1794600000000.jpg")
    assert len(item.blur) == 1 and item.blur[0][0] == 0              # one head; the plate model's own target is not blurred
    assert all(int(b[0]) == 0 for b in item.boxes)                   # the labels hold only plates: blur is not a class


def test_the_helmet_model_gets_plate_blur_but_never_head_blur(env):
    paths, store, evidence = env
    write_img(evidence / "1794600000001.jpg", 200, 100, seed=6)
    r = fl.scan(paths, store, "helmet_specialist", evidence)
    fl.suggest_batch(paths, store, "helmet_specialist", r["task"], n=50, detectors=helper_models(paths), heads=True, plates=True)
    item = next(i for i in store.items("helmet_specialist", ("label", "check"), task=r["task"]) if i.src_path.endswith("1794600000001.jpg"))
    assert len(item.blur) == 1 and item.blur[0][1] > 0.5            # the vehicle's plate zone (lower right), no head box


def test_blur_guesses_do_not_decide_the_picture(env):
    paths, store, evidence = env
    write_img(evidence / "1794600000002.jpg", 200, 100, seed=7)
    r = fl.scan(paths, store, "plate_specialist", evidence)
    fl.suggest_batch(paths, store, "plate_specialist", r["task"], n=50, detectors=FakeDetectors(
        primary_anchor=vehicle_finder(PERSON, CAR)), heads=True, plates=False)     # no plate model here: only the blur guess
    item = folder_item(store, r["task"], "1794600000002.jpg")
    assert item.state == "label" and item.boxes == [] and len(item.blur) == 1       # still waiting for a person


def test_the_labelling_page_has_no_blur_class_but_every_picture_carries_its_blur_areas(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    item = store.items("plate_specialist", ("label",), task=r["task"])[0]
    store.set_blur_guess(item.id, [[0, 0.5, 0.5, 0.2, 0.2]])
    queue = HarvestApp(paths, store).queue("plate_specialist", task=r["task"])
    assert queue["classes"] == ["license_plate"]
    assert next(i for i in queue["items"] if i["id"] == item.id)["blur"] == [[0, 0.5, 0.5, 0.2, 0.2]]


def test_blur_areas_are_saved_apart_from_labels_for_a_folder_picture_but_ignored_for_a_normal_one(env):
    paths, store, evidence = env
    app = HarvestApp(paths, store)
    r = fl.scan(paths, store, "plate_specialist", evidence)
    item = store.items("plate_specialist", ("label",), task=r["task"])[0]
    app.save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]], [[0, 0.2, 0.2, 0.2, 0.2], [0, 9, 9, 9, 9]])      # the second area is not valid
    saved = store.get(item.id)
    assert len(saved.boxes) == 1 and saved.boxes[0][0] == 0
    assert len(saved.blur) == 1 and saved.blur[0][1] == pytest.approx(0.2)
    app.save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]])                                                    # no blur sent: what is stored stays
    assert len(store.get(item.id).blur) == 1
    store.add(Item(id="f" * 16, model="plate_specialist", state="label", source="forensic", group_id="g"))
    app.save("f" * 16, [[0, 0.5, 0.5, 0.3, 0.2]], [[0, 0.2, 0.2, 0.2, 0.2]])
    assert store.get("f" * 16).blur == []                                                           # blur exists only in the Labeller


def test_saving_blurs_the_area_removes_the_original_and_keeps_blur_out_of_the_labels(env, tmp_path):
    paths, store, evidence = env
    only = write_img(evidence / "1794700000000.jpg", 64, 48, seed=11)
    original = cv2.imread(str(only))
    r = fl.scan(paths, store, "plate_specialist", evidence)
    for item in store.items("plate_specialist", ("label",), task=r["task"]):
        if item.src_path.endswith("1794700000000.jpg"):
            store.save_boxes(item.id, [[0, 0.7, 0.7, 0.2, 0.2]], [[0, 0.3, 0.3, 0.4, 0.4]])      # a plate label + a blur area
        else:
            store.save_boxes(item.id, [], [[0, 0.5, 0.5, 0.3, 0.3]])                              # only a blur area: an empty-label example
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")

    assert out["blurred_pictures"] == 8 and out["blurred_regions"] == 8 and out["per_class"] == {"license_plate": 1}
    assert out["empty_labels"] == 7                                                              # blur alone is not a label
    saved = next(p for s in ("train", "val") for p in (tmp_path / "out" / "plate_specialist" / "images" / s).iterdir() if p.name == only.name)
    label = (saved.parent.parent.parent / "labels" / saved.parent.name / (saved.stem + ".txt")).read_text().split("\n")
    assert len(label) == 1 and label[0].startswith("0 ")                                         # the plate only; no blur line
    after = cv2.imread(str(saved))
    assert after[7:22, 8:30].std() < original[7:22, 8:30].std() / 2                              # the blur area is blurred
    assert after[38:46, 2:20].std() > original[38:46, 2:20].std() / 2                            # the rest is not
    assert not only.exists()                                                                     # the original, with the faces, is gone


def test_without_a_blur_box_the_picture_is_moved_byte_for_byte(env, tmp_path):
    paths, store, evidence = env
    only = write_img(evidence / "1794700000001.jpg", 64, 48, seed=12)
    bytes_before = only.read_bytes()
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")
    assert out["blurred_pictures"] == 0
    saved = next(p for s in ("train", "val") for p in (tmp_path / "out" / "plate_specialist" / "images" / s).iterdir() if p.name == only.name)
    assert saved.read_bytes() == bytes_before
