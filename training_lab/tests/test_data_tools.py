"""
Dataset tool tests. Everything runs in a temporary folder: no real dataset, download or model is read or written,
so these are safe to run while a training is going.

    hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests -q -p no:cacheprovider
"""
import json
import sys
from collections import Counter
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data_tools import common, curate, ocr, stage                    # noqa: E402
from data_tools.common import (clean_boxes, crop_windows, group_key, read_yolo, split_for, source_of,   # noqa: E402
                               write_yolo, xywh_to_yolo)


def noise_jpg(path: Path, w: int = 96, h: int = 64, seed: int = 0, quality: int = 90) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    Image.fromarray(rng.integers(0, 255, (h, w, 3), dtype=np.uint8)).save(path, "JPEG", quality=quality)


@pytest.fixture
def lab(tmp_path, monkeypatch):
    """A fake datasets/ folder with one two-class dataset 'toy' in the standard layout."""
    ds = tmp_path / "datasets"
    monkeypatch.setattr(common, "DATASETS", ds)
    monkeypatch.setattr(common, "QUARANTINE", ds / "_quarantine")
    monkeypatch.setattr(curate, "DATASETS", ds)
    monkeypatch.setattr(ocr, "DATASETS", ds)
    (ds / "toy").mkdir(parents=True)
    (ds / "toy" / "data.yaml").write_text("# toy\npath: datasets/toy\ntrain: images/train\nval: images/val\n"
                                          "test: images/test\nnc: 2\nnames:\n  0: a\n  1: b\n", encoding="utf-8")
    return ds


def put(ds: Path, split: str, name: str, boxes, seed: int, **kw) -> Path:
    img = ds / "toy" / "images" / split / name
    noise_jpg(img, seed=seed, **kw)
    (ds / "toy" / "labels" / split).mkdir(parents=True, exist_ok=True)
    write_yolo(ds / "toy" / "labels" / split / (Path(name).stem + ".txt"), boxes)
    return img


# --------------------------------------------------------------------------- names, splits, labels

def test_group_key_ignores_roboflow_augmentation_suffix():
    assert group_key("car_12_jpg.rf.abc123.jpg") == group_key("car_12_jpg.rf.zzz999.jpg") == "car_12_jpg"
    assert source_of("oi_plates__0a1b.jpg") == "oi_plates" and source_of("0a1b.jpg") == "legacy"


def test_split_is_stable_and_close_to_80_10_10():
    groups = [f"photo{i}" for i in range(4000)]
    first = [split_for(g) for g in groups]
    assert first == [split_for(g) for g in groups]                      # same photo, same side, every run
    share = Counter(first)
    assert 0.77 < share["train"] / 4000 < 0.83 and 0.08 < share["val"] / 4000 < 0.12 and 0.08 < share["test"] / 4000 < 0.12


def test_read_yolo_turns_polygons_into_boxes_and_skips_junk(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("1 0.5 0.5 0.2 0.4\n2 0.1 0.1 0.3 0.1 0.3 0.5 0.1 0.5\nnot a label\n3 0.5 0.5\n")
    boxes = read_yolo(f)
    assert boxes[0] == (1, 0.5, 0.5, 0.2, 0.4)
    cls, cx, cy, w, h = boxes[1]
    assert (cls, round(cx, 3), round(cy, 3), round(w, 3), round(h, 3)) == (2, 0.2, 0.3, 0.2, 0.4)
    assert len(boxes) == 2


def test_clean_boxes_clips_and_drops_bad_ones():
    boxes = [(0, 0.5, 0.5, 0.4, 0.4),          # fine
             (0, 0.5, 0.5, 0.4, 0.4),          # exact duplicate
             (5, 0.5, 0.5, 0.2, 0.2),          # class id out of range
             (1, 0.5, 0.5, 0.001, 0.2),        # thinner than 3 px
             (1, 0.98, 0.5, 0.1, 0.2)]         # sticks out of the picture: clipped, kept
    kept, dropped = clean_boxes(boxes, 200, 100, nc=2)
    assert len(kept) == 2 and dropped["duplicate"] == 1 and dropped["bad_class"] == 1 and dropped["tiny"] == 1
    assert dropped["clipped"] == 1
    assert max(b[1] + b[3] / 2 for b in kept) <= 1.0


def test_coco_box_conversion():
    assert xywh_to_yolo(10, 20, 30, 40, 100, 200) == (0.25, 0.2, 0.3, 0.2)


def test_crop_windows_cut_around_the_anchor_and_move_the_boxes_inside():
    # 1000 x 500 picture; motorcycle (class 0) = pixels 400..600 x 100..300; its mirror (class 2) = 410..450 x 120..150
    boxes = [(0, 0.5, 0.4, 0.2, 0.4),
             (2, 0.43, 0.27, 0.04, 0.06),
             (3, 0.46, 0.20, 0.04, 0.06),          # a class we do not want: ignored
             (2, 0.90, 0.50, 0.04, 0.06)]          # a mirror on another bike: outside the window
    (win, inside), = crop_windows(boxes, anchor=0, wanted={2: 4}, img_w=1000, img_h=500, margin=0.1)
    assert win == (380, 80, 620, 320)                                   # 10% of 200 x 200 added on each side
    (cls, cx, cy, w, h), = inside
    assert cls == 4                                                     # re-labelled with OUR class id
    assert (cx, cy, w, h) == pytest.approx((50 / 240, 55 / 240, 40 / 240, 30 / 240))   # window is 240 x 240 px


def test_crop_windows_skip_cut_boxes_empty_windows_and_slivers():
    cut = [(0, 0.5, 0.5, 0.2, 0.4), (2, 0.40, 0.5, 0.04, 0.06)]         # the mirror is half outside the 0-margin window
    assert crop_windows(cut, 0, {2: 0}, 1000, 500, margin=0.0) == []
    assert crop_windows([(0, 0.5, 0.5, 0.2, 0.4)], 0, {2: 0}, 1000, 500) == []        # nothing wanted inside
    thin = [(0, 0.5, 0.5, 0.01, 0.4), (2, 0.5, 0.5, 0.004, 0.06)]
    assert crop_windows(thin, 0, {2: 0}, 1000, 500) == []                # 10 px wide: too thin to train on


# --------------------------------------------------------------------------- importers

def test_import_yolo_tree_finds_labels_in_a_separate_folder_and_splits_by_hash(tmp_path):
    root = tmp_path / "raw"
    for i in range(30):
        noise_jpg(root / "pics" / f"p{i}.jpg", seed=i)
        (root / "labels_only").mkdir(exist_ok=True)
        (root / "labels_only" / f"p{i}.txt").write_text("0 0.5 0.5 0.3 0.3\n")
    noise_jpg(root / "pics" / "nolabel.jpg", seed=99)
    st = stage.Stage("toysrc", ["thing"], tmp_path / "stage")
    seen = stage.import_yolo_tree(root, st)
    assert seen["no_label"] == 1 and seen["train"] + seen["val"] + seen["test"] == 30
    assert seen["train"] > seen["val"] and sum(1 for _ in (tmp_path / "stage" / "train" / "images").iterdir()) == seen["train"]
    st.finish({"id": "toysrc"})
    assert (tmp_path / "stage" / "data.yaml").exists() and (tmp_path / "stage" / "SOURCE.json").exists()


def test_import_yolo_tree_trusts_split_folders(tmp_path):
    root = tmp_path / "raw"
    for split, n in (("train", 3), ("valid", 2), ("test", 1)):
        for i in range(n):
            noise_jpg(root / split / "images" / f"{split}{i}.jpg", seed=i)
            (root / split / "labels").mkdir(parents=True, exist_ok=True)
            (root / split / "labels" / f"{split}{i}.txt").write_text("0 0.5 0.5 0.3 0.3\n")
    st = stage.Stage("s", ["x"], tmp_path / "stage")
    assert dict(stage.import_yolo_tree(root, st)) == {"train": 3, "val": 2, "test": 1}


def test_import_coco_maps_categories_to_yolo(tmp_path):
    folder = tmp_path / "coco"
    noise_jpg(folder / "a.jpg", w=200, h=100)
    (folder / "_annotations.coco.json").write_text(json.dumps({
        "categories": [{"id": 0, "name": "junk"}, {"id": 1, "name": "plate"}],
        "images": [{"id": 7, "file_name": "a.jpg", "width": 200, "height": 100}],
        "annotations": [{"image_id": 7, "category_id": 1, "bbox": [20, 10, 100, 50]},
                        {"image_id": 7, "category_id": 0, "bbox": [0, 0, 10, 10]}]}))
    st = stage.Stage("c", ["plate"], tmp_path / "stage")
    stage.import_coco(folder / "_annotations.coco.json", folder, st, "val")
    label = (tmp_path / "stage" / "valid" / "labels" / "a.txt").read_text().split()
    assert label[0] == "0" and [round(float(v), 3) for v in label[1:]] == [0.35, 0.35, 0.5, 0.5]


# --------------------------------------------------------------------------- curator

def test_curate_quarantines_bad_pictures_and_keeps_val_copy_of_a_leak(lab):
    good = [(0, 0.5, 0.5, 0.4, 0.4)]
    put(lab, "train", "src__ok.jpg", good, seed=1)
    put(lab, "train", "src__leak.jpg", good, seed=2)
    put(lab, "val", "src__leak_val.jpg", good, seed=2, quality=70)         # same photo, re-encoded, in val
    (lab / "toy" / "images" / "train" / "src__broken.jpg").write_bytes(b"not a picture")
    (lab / "toy" / "labels" / "train" / "src__broken.txt").write_text("0 0.5 0.5 0.4 0.4")
    put(lab, "train", "src__empty.jpg", [], seed=3)
    put(lab, "train", "src__badclass.jpg", [(7, 0.5, 0.5, 0.4, 0.4), (1, 0.5, 0.5, 0.3, 0.3)], seed=4)
    noise_jpg(lab / "toy" / "images" / "test" / "src__nolabel.jpg", seed=5)

    rep = curate.curate_model("toy", apply=True, log=lambda *_: None)

    assert rep["dropped"] == {"corrupt_image": 1, "no_boxes": 1, "no_label": 1, "leak": 1}
    left = {p.name for s in ("train", "val", "test") for p in (lab / "toy" / "images" / s).iterdir()}
    assert left == {"src__ok.jpg", "src__leak_val.jpg", "src__badclass.jpg"}
    assert (lab / "_quarantine" / "toy" / "leak" / "src__leak.jpg").exists()        # moved, not deleted
    assert read_yolo(lab / "toy" / "labels" / "train" / "src__badclass.txt") == [(1, 0.5, 0.5, 0.3, 0.3)]
    assert rep["images_per_split"] == {"train": 2, "val": 1, "test": 0}
    assert (lab / "toy" / "report.json").exists()


def test_curate_never_touches_harvest_files_and_does_not_resave_legacy(lab):
    put(lab, "train", "harvest__car1.jpg", [(0, 0.5, 0.5, 0.4, 0.4)], seed=1)
    (lab / "toy" / "images" / "train" / "harvest__broken.jpg").write_bytes(b"junk")
    (lab / "toy" / "labels" / "train" / "harvest__broken.txt").write_text("0 0.5 0.5 0.4 0.4")
    big = put(lab, "train", "legacy_big.jpg", [(0, 0.5, 0.5, 0.4, 0.4)], seed=2, w=2000, h=1500)
    size_before = big.stat().st_size
    pub = put(lab, "train", "src__big.jpg", [(0, 0.5, 0.5, 0.4, 0.4)], seed=3, w=2000, h=1500)

    rep = curate.curate_model("toy", apply=True, max_side=1280, log=lambda *_: None)

    assert (lab / "toy" / "images" / "train" / "harvest__broken.jpg").read_bytes() == b"junk"   # reported only
    assert rep["issues_kept"] == {"corrupt_image": 1}
    assert big.stat().st_size == size_before                                  # original data: not re-saved
    with Image.open(pub) as im:
        assert max(im.size) == 1280                                            # public picture: capped
    assert rep["resaved_pictures"] == 1


def test_curate_dry_run_changes_nothing(lab):
    put(lab, "train", "src__a.jpg", [(0, 0.5, 0.5, 0.4, 0.4)], seed=1)
    (lab / "toy" / "images" / "train" / "src__bad.jpg").write_bytes(b"x")
    (lab / "toy" / "labels" / "train" / "src__bad.txt").write_text("0 0.5 0.5 0.4 0.4")
    rep = curate.curate_model("toy", apply=False, log=lambda *_: None)
    assert rep["dropped"] == {"corrupt_image": 1}
    assert (lab / "toy" / "images" / "train" / "src__bad.jpg").exists() and not (lab / "_quarantine").exists()


def test_curate_moves_old_roboflow_layout_to_the_standard_one(lab):
    old = lab / "oldstyle"
    for split, sub in (("train", "train"), ("val", "valid"), ("test", "test")):
        noise_jpg(old / sub / "images" / f"{split}.jpg", seed=len(split))
        (old / sub / "labels").mkdir(parents=True, exist_ok=True)
        (old / sub / "labels" / f"{split}.txt").write_text("0 0.5 0.5 0.4 0.4")
    (old / "data.yaml").write_text("train: train/images\nval: valid/images\ntest: test/images\nnames:\n  0: thing\n")
    moves = curate.ensure_layout("oldstyle", apply=True, log=lambda *_: None)
    assert len(moves) == 6
    assert (old / "images" / "val" / "val.jpg").exists() and (old / "labels" / "test" / "test.txt").exists()
    assert not (old / "valid").exists() and not (old / "train").exists()
    cfg = common.load_yaml(old / "data.yaml")
    assert (cfg["train"], cfg["val"], cfg["test"], cfg["nc"]) == ("images/train", "images/val", "images/test", 1)


# --------------------------------------------------------------------------- OCR import

def test_normalise_plate_text():
    assert ocr.normalise_text("01 DVZ 18") == "01DVZ18" and ocr.normalise_text("ab-12.3") == "AB123" and ocr.normalise_text("  ") == ""


def test_ocr_merge_cuts_plate_and_writes_text_label(lab, tmp_path):
    folder = tmp_path / "stage"
    noise_jpg(folder / "train" / "images" / "34 ABC 123.jpg", w=300, h=200, seed=1)
    (folder / "train" / "labels").mkdir(parents=True)
    (folder / "train" / "labels" / "34 ABC 123.txt").write_text("0 0.5 0.5 0.5 0.2")
    noise_jpg(folder / "val" / "images" / "x.jpg", seed=2)                          # val has no stage folder name: ignored
    got = ocr.merge_filename_text({"id": "tr"}, folder)
    assert got["train"] == 1
    crops = list((lab / "plate_ocr" / "images" / "train").glob("tr__34ABC123_*.jpg"))
    assert len(crops) == 1
    label = (lab / "plate_ocr" / "labels" / "train" / (crops[0].stem + ".txt")).read_text()
    assert label == "0 34ABC123"
    with Image.open(crops[0]) as im:
        assert im.size[0] > im.size[1]


def test_tf_corner_labels_are_ymin_xmin_ymax_xmax(tmp_path):
    f = tmp_path / "a.txt"
    f.write_text("0.5, 0.2, 0.7, 0.6")
    (cls, cx, cy, w, h), = stage.read_labels(f, "tf_corners")
    assert (cls, round(cx, 3), round(cy, 3), round(w, 3), round(h, 3)) == (0, 0.4, 0.6, 0.4, 0.2)
    f.write_text("0.7, 0.2, 0.5, 0.6")                                     # upside-down box: ignored
    assert stage.read_labels(f, "tf_corners") == []


def test_import_can_be_limited_to_some_folders(tmp_path):
    root = tmp_path / "raw"
    for folder in ("wanted", "copies"):
        noise_jpg(root / folder / "p.jpg", seed=1 if folder == "wanted" else 2)
    (root / "labels").mkdir()
    (root / "labels" / "p.txt").write_text("0 0.5 0.5 0.3 0.3")
    st = stage.Stage("s", ["x"], tmp_path / "stage")
    seen = stage.import_yolo_tree(root, st, image_dirs=["wanted"])
    assert seen["train"] + seen["val"] + seen["test"] == 1


# --------------------------------------------------------------------------- ReID sample, enhancer crops, cards

def test_reid_pick_spreads_over_cameras_and_is_stable():
    from data_tools import reid
    names = [f"images/train/0001_c0{c}_{f:06d}.jpg" for c in (10, 11, 12) for f in range(5)] + ["images/query/0002_c10_000001.jpg"]
    got = reid.pick(names, per_identity=4)
    assert len(got["0001"]) == 4 and len({n.split("_")[1] for n in got["0001"]}) == 3       # all three cameras seen
    assert got["0002"] == ["images/query/0002_c10_000001.jpg"]
    assert got == reid.pick(list(reversed(names)), per_identity=4)                            # same pick whatever the order


def test_sr_build_keeps_only_big_sharp_plate_shaped_crops(lab, monkeypatch):
    import cv2
    from data_tools import sr
    monkeypatch.setattr(sr, "DATASETS", lab)
    monkeypatch.setattr(sr, "OUT", lab / "sr_plates" / "clean")
    ds = lab / "plates"
    (ds / "data.yaml").parent.mkdir(parents=True)
    (ds / "data.yaml").write_text("names:\n  0: license_plate\n")
    rng = np.random.default_rng(0)

    def photo(name, sharp: bool, plate_w: float, seed: int):
        img = np.random.default_rng(seed).integers(0, 255, (600, 800, 3), dtype=np.uint8)
        if not sharp:
            img = cv2.GaussianBlur(img, (0, 0), 6)
        d = ds / "images" / "train"
        d.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(d / f"{name}.jpg"), img)
        (ds / "labels" / "train").mkdir(parents=True, exist_ok=True)
        (ds / "labels" / "train" / f"{name}.txt").write_text(f"0 0.5 0.5 {plate_w} 0.1")

    photo("good", True, 0.4, 1)         # 320 x 60 px, sharp
    photo("small", True, 0.1, 2)        # 80 x 60 px: too small
    photo("blurry", False, 0.4, 3)      # big but blurred
    photo("square", True, 0.1, 4)       # (0.1 wide x 0.1 high of a 4:3 picture): not plate shaped
    report = sr.build("plates", log=lambda *_: None)
    assert report["counts"] == {"train": 1, "val": 0, "test": 0}
    assert [p.name for p in (lab / "sr_plates" / "clean" / "train").iterdir()] == ["good_0.jpg"]
    assert report["rejected"]["too_small"] >= 1 and report["rejected"]["blurry"] == 1


def test_card_warns_about_missing_classes_small_eval_sets_and_leaks(lab, monkeypatch):
    from data_tools import report
    monkeypatch.setattr(report, "DATASETS", lab)
    monkeypatch.setattr(report, "DOWNLOADS", lab / "_downloads")
    monkeypatch.setattr(report, "MANIFEST", lab / "m.yaml")
    (lab / "m.yaml").write_text("toy:\n  - id: src\n    license: CC BY 4.0\n    country: Elsewhere\n    trust: A\n    ph: false\n")
    (lab / "toy" / "report.json").write_text(json.dumps({
        "model": "toy", "classes": ["a", "b"], "checked": 100, "kept": 90, "dropped": {"leak": 10}, "fixed_labels": 3,
        "resaved_pictures": 0, "images_per_split": {"train": 80, "val": 5, "test": 5},
        "boxes_per_class": {"train": {"a": 90}, "val": {"a": 5}, "test": {"a": 5}}, "per_source": {"src": {"train": 80, "val": 5, "test": 5}},
        "long_side_px": {"min": 100, "median": 640, "max": 1280}, "box_area_share": {"p10": 0.01, "median": 0.1, "p90": 0.4},
        "eval_pictures_with_train_twin": {"val": 3, "test": 0}, "issues_kept": {}}))
    text = report.card("toy")
    assert "No training boxes for class `b`" in text
    assert "Only 5 pictures in `val`" in text and "Only 5 pictures in `test`" in text
    assert "Before the first cleaning, 3 val and 0 test pictures" in text
    assert "Philippine pictures: **0 of 90 (0%)**" in text
    assert "Less than a quarter of the pictures are Philippine" in text


def test_card_separates_mixed_philippine_sources_and_flags_rare_eval_classes(lab, monkeypatch):
    from data_tools import report
    monkeypatch.setattr(report, "DATASETS", lab)
    monkeypatch.setattr(report, "DOWNLOADS", lab / "_downloads")
    monkeypatch.setattr(report, "MANIFEST", lab / "m.yaml")
    (lab / "m.yaml").write_text("toy:\n  - id: pure\n    ph: true\n    license: x\n  - id: blend\n    ph: mixed\n    license: y\n")
    (lab / "toy" / "report.json").write_text(json.dumps({
        "model": "toy", "classes": ["a", "b"], "checked": 400, "kept": 400, "dropped": {}, "fixed_labels": 0, "resaved_pictures": 0,
        "images_per_split": {"train": 300, "val": 60, "test": 40},
        "boxes_per_class": {"train": {"a": 500, "b": 90}, "val": {"a": 100, "b": 10}, "test": {"a": 70, "b": 60}},
        "per_source": {"pure": {"train": 100, "val": 20, "test": 10}, "blend": {"train": 200, "val": 40, "test": 30}},
        "long_side_px": {"min": 1, "median": 2, "max": 3}, "box_area_share": {"p10": 0.1, "median": 0.2, "p90": 0.3}}))
    text = report.card("toy")
    assert "Philippine pictures: **130 of 400 (32%)**, plus 270 (68%)" in text
    assert "Class `b` has only 10 boxes in `val`" in text and "Class `b` has only 60 boxes in `test`" not in text


def test_clean_boxes_ignores_rounding_noise_and_is_idempotent():
    noisy = [(0, 0.5, 0.5, 1.00001, 0.4)]                                  # 0.0005 % too wide: just rounding
    kept, dropped = clean_boxes(noisy, 640, 480, nc=1)
    assert dropped["clipped"] == 0 and len(kept) == 1
    wide = [(0, 0.5, 0.5, 1.2, 0.4)]                                         # really outside
    kept, dropped = clean_boxes(wide, 640, 480, nc=1)
    assert dropped["clipped"] == 1
    again, dropped2 = clean_boxes(kept, 640, 480, nc=1)
    assert dropped2["clipped"] == 0 and len(again) == len(kept)
    assert all(abs(x - y) < 1e-9 for a, b in zip(again, kept) for x, y in zip(a, b))


def test_later_cleaning_passes_keep_the_first_leak_count(lab):
    good = [(0, 0.5, 0.5, 0.4, 0.4)]
    put(lab, "train", "src__a.jpg", good, seed=1)
    put(lab, "train", "src__twin.jpg", good, seed=2)
    put(lab, "val", "src__twin_val.jpg", good, seed=2, quality=70)
    first = curate.curate_model("toy", apply=True, log=lambda *_: None)
    assert first["eval_pictures_with_train_twin"] == {"val": 1} and first["eval_twins_before_first_cleaning"] == {"val": 1}
    second = curate.curate_model("toy", apply=True, log=lambda *_: None)
    assert second["eval_pictures_with_train_twin"] == {}                          # nothing left to find this time...
    assert second["eval_twins_before_first_cleaning"] == {"val": 1}               # ...but the first finding is kept
