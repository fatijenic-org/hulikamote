"""
The Labeller: every picture of a folder, one model, a clean dataset at the end. Everything runs in a temporary folder.

    hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests/test_folder_labeller.py -q -p no:cacheprovider
"""
import sys
import time
from pathlib import Path

import cv2
import numpy as np
import pytest
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from harvest_tool import accept as accept_mod            # noqa: E402
from harvest_tool import folder_labeller as fl           # noqa: E402
from harvest_tool.config import Paths                    # noqa: E402
from harvest_tool.store import FOLDER_SOURCE, Item, Store  # noqa: E402
from harvest_tool.web import HarvestApp                  # noqa: E402


def write_img(path: Path, w: int = 64, h: int = 48, seed: int = 0) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    cv2.imwrite(str(path), rng.integers(0, 255, (h, w, 3), dtype=np.uint8))
    return path


@pytest.fixture
def env(tmp_path):
    lab, backend = tmp_path / "lab", tmp_path / "backend"
    paths = Paths(lab=lab, backend=backend)
    for model, names in (("plate_specialist", ["license_plate"]), ("helmet_specialist", ["rider_with_helmet", "rider_without_helmet"])):
        folder = lab / "datasets" / model
        folder.mkdir(parents=True)
        (folder / "data.yaml").write_text(yaml.safe_dump({"train": "images/train", "val": "images/val",
                                                         "names": {i: n for i, n in enumerate(names)}}), encoding="utf-8")
    evidence = paths.evidence
    for i in range(6):                                             # millisecond names: three in one minute, three in the next
        write_img(evidence / f"{1794523400000 + i * 1000 + (60000 if i >= 3 else 0)}.jpg", seed=i)
    write_img(evidence / "forensic" / "task1" / "temp" / "extra.png", seed=50)
    (evidence / "forensic" / "task1" / "output").mkdir(parents=True)
    (evidence / "forensic" / "task1" / "output" / "boxes.json").write_text("{}")      # not a picture
    (evidence / "notes.txt").write_text("not a picture")
    store = Store(paths)
    return paths, store, evidence


def label_all(store, model, task, boxes=None):
    for item in store.items(model, ("label", "check"), task=task):
        store.save_boxes(item.id, boxes if boxes is not None else [[0, 0.5, 0.5, 0.4, 0.3]])


# ─── scanning ────────────────────────────────────────────────────────────────

def test_scan_queues_every_picture_in_every_subfolder_and_nothing_else(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    assert r["found"] == 7 and r["new"] == 7                        # six photos + the png in a subfolder; txt and json skipped
    assert store.counts("plate_specialist", r["task"])["label"] == 7


def test_scanning_again_adds_nothing_twice_and_a_new_picture_is_picked_up(env):
    paths, store, evidence = env
    first = fl.scan(paths, store, "plate_specialist", evidence)
    again = fl.scan(paths, store, "plate_specialist", evidence)
    assert again["found"] == 7 and again["new"] == 0
    write_img(evidence / "1794523999999.jpg", seed=99)
    assert fl.scan(paths, store, "plate_specialist", evidence)["new"] == 1
    assert store.counts("plate_specialist", first["task"])["label"] == 8


def test_the_same_picture_can_be_queued_for_two_models(env):
    paths, store, evidence = env
    a = fl.scan(paths, store, "plate_specialist", evidence)
    b = fl.scan(paths, store, "helmet_specialist", evidence)
    assert a["task"] == b["task"] and b["new"] == 7


def test_scanning_something_that_is_not_a_folder_is_refused(env):
    paths, store, evidence = env
    with pytest.raises(ValueError):
        fl.scan(paths, store, "plate_specialist", evidence / "nope")
    with pytest.raises(KeyError):
        fl.scan(paths, store, "not_a_model", evidence)


def test_folder_pictures_never_show_up_in_the_normal_harvest(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    assert store.counts("plate_specialist")["needs_eyes"] == 0 and store.counts("plate_specialist")["ready"] == 0
    assert store.queue("plate_specialist") == [] and store.ready("plate_specialist") == []
    assert store.unsuggested_labels("plate_specialist") == []
    assert accept_mod.accept(paths, store, "plate_specialist")["ready"] == 0       # "Add to dataset" ignores them


# ─── showing a page of pictures ──────────────────────────────────────────────

def test_the_queue_of_a_folder_makes_each_picture_showable_with_its_size(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    queue = HarvestApp(paths, store).queue("plate_specialist", task=r["task"])
    assert queue["total"] == 7 and len(queue["items"]) == 7
    first = queue["items"][0]
    assert (first["width"], first["height"]) == (64, 48)
    assert store.image_path("plate_specialist", first["id"]).exists()


def test_a_picture_that_vanished_is_set_aside_not_shown(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    gone = store.items("plate_specialist", ("label",), task=r["task"])[0]
    Path(gone.src_path).unlink()
    queue = HarvestApp(paths, store).queue("plate_specialist", task=r["task"])
    assert len(queue["items"]) == 6 and all(i["id"] != gone.id for i in queue["items"])
    assert store.get(gone.id).state == "skipped"


def test_pictures_in_the_same_minute_share_a_group(env):
    paths, store, evidence = env
    fl.scan(paths, store, "plate_specialist", evidence)
    groups = {Path(i.src_path).name: i.group_id for i in store.items("plate_specialist", ("label",), task=fl.folder_task(evidence))}
    assert len({groups[f"{1794523400000 + k * 1000}.jpg"] for k in range(3)}) == 1
    assert groups["1794523400000.jpg"] != groups[f"{1794523400000 + 3000 + 60000}.jpg"]


# ─── the clean dataset ───────────────────────────────────────────────────────

def test_export_writes_a_ready_to_train_dataset_and_moves_the_pictures(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    dest = tmp_path / "external drive"
    out = fl.export(paths, store, "plate_specialist", r["task"], dest)

    assert out["ready"] == 7 and out["exported"] == 7 and out["train"] + out["val"] == 7
    root = dest / "plate_specialist"
    images = [p for split in ("train", "val") for p in (root / "images" / split).iterdir()]
    labels = [p for split in ("train", "val") for p in (root / "labels" / split).iterdir()]
    assert len(images) == 7 and len(labels) == 7
    assert {p.stem for p in images} == {p.stem for p in labels}                 # every picture has its label
    text = labels[0].read_text().split()
    assert text[0] == "0" and all(0 < float(v) <= 1 for v in text[1:])
    cfg = yaml.safe_load((root / "data.yaml").read_text())
    assert cfg["train"] == "images/train" and cfg["val"] == "images/val" and cfg["names"] == {0: "license_plate"} and cfg["nc"] == 1
    assert (root / "report.json").exists()
    assert out["per_class"] == {"license_plate": 7}
    # moved: gone from the folder and from the inbox, and the store knows where they are
    assert not list(evidence.glob("*.jpg")) and not (evidence / "forensic" / "task1" / "temp" / "extra.png").exists()
    assert not any(store.image_path("plate_specialist", i.id).exists() for i in store.items("plate_specialist", ("accepted",), task=r["task"]))
    assert store.counts("plate_specialist", r["task"])["accepted"] == 7


def test_pictures_of_the_same_minute_stay_on_one_side_of_the_split(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out", val_share=0.5)
    side = {}
    for split in ("train", "val"):
        for p in (tmp_path / "out" / "plate_specialist" / "images" / split).iterdir():
            side[p.name] = split
    first_minute = {side[f"{1794523400000 + k * 1000}.jpg"] for k in range(3)}
    second_minute = {side[f"{1794523400000 + 3000 + 60000 + k * 1000}.jpg"] for k in range(3)}
    assert len(first_minute) == 1 and len(second_minute) == 1


def test_a_nothing_here_picture_is_exported_as_an_empty_label_and_skipped_or_undecided_ones_stay_put(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    items = store.items("plate_specialist", ("label",), task=r["task"])
    store.save_boxes(items[0].id, [])                                  # decided: nothing here
    store.save_boxes(items[1].id, [[0, 0.5, 0.5, 0.2, 0.2]])
    store.skip(items[2].id)                                            # not sure
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")
    assert out["exported"] == 2 and out["empty_labels"] == 1
    assert Path(items[2].src_path).exists() and Path(items[3].src_path).exists()      # skipped / undecided stay in the folder
    assert not Path(items[0].src_path).exists() and not Path(items[1].src_path).exists()


def test_the_same_picture_twice_is_exported_once_and_the_copy_stays(env, tmp_path):
    paths, store, evidence = env
    one = write_img(evidence / "1794524000000.jpg", seed=7)
    two = evidence / "1794524000001.jpg"
    two.write_bytes(one.read_bytes())
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")
    assert out["duplicates"] == 1 and out["exported"] == 8
    assert (one.exists() ^ two.exists())                              # exactly one of the twins is left behind


def test_an_unreadable_picture_is_reported_and_not_exported(env, tmp_path):
    paths, store, evidence = env
    (evidence / "1794524100000.jpg").write_bytes(b"this is not a jpeg")
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")
    assert out["unreadable"] == 1 and out["exported"] == 7
    assert (evidence / "1794524100000.jpg").exists()


def test_export_without_move_keeps_the_originals(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out", move=False)
    assert out["exported"] == 7 and len(list(evidence.glob("*.jpg"))) == 6


def test_exporting_again_adds_only_what_is_new_and_never_duplicates(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")
    write_img(evidence / "1794525000000.jpg", seed=123)
    fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")
    assert out["ready"] == 1 and out["exported"] == 1
    total = sum(len(list((tmp_path / "out" / "plate_specialist" / "images" / s).iterdir())) for s in ("train", "val"))
    assert total == 8


def test_a_destination_inside_the_folder_being_labelled_is_refused(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    with pytest.raises(ValueError):
        fl.export(paths, store, "plate_specialist", r["task"], evidence / "dataset")
    assert len(list(evidence.glob("*.jpg"))) == 6                       # nothing moved


def test_the_training_datasets_cannot_be_the_destination_while_that_model_trains(env, monkeypatch):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", r["task"])
    monkeypatch.setattr(fl, "is_training", lambda model: True)
    with pytest.raises(RuntimeError):
        fl.export(paths, store, "plate_specialist", r["task"], paths.datasets)


def test_nothing_ready_means_nothing_is_written(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")
    assert out["exported"] == 0 and not (tmp_path / "out").exists()


# ─── the helper's jobs ───────────────────────────────────────────────────────

def wait_job(app, timeout=20):
    until = time.time() + timeout
    while app._labeller["running"] and time.time() < until:
        time.sleep(0.05)
    assert not app._labeller["running"], "the job did not finish"


def test_scan_and_export_run_as_jobs_the_page_can_follow(env, tmp_path):
    paths, store, evidence = env
    app = HarvestApp(paths, store)
    job = app.labeller_scan("plate_specialist", str(evidence))
    assert job["running"] and job["kind"] == "scan" and job["task"] == fl.folder_task(evidence)
    wait_job(app)
    status = app.labeller_status("plate_specialist", job["task"])
    assert status["job"]["summary"]["found"] == 7 and status["counts"]["label"] == 7

    label_all(store, "plate_specialist", job["task"])
    app.labeller_export("plate_specialist", job["task"], str(tmp_path / "out"))
    wait_job(app)
    done = app.labeller_status("plate_specialist", job["task"])
    assert done["job"]["summary"]["exported"] == 7 and done["job"]["error"] is None
    assert done["counts"]["accepted"] == 7


def test_a_job_that_fails_reports_the_reason_instead_of_crashing(env, tmp_path):
    paths, store, evidence = env
    app = HarvestApp(paths, store)
    task = fl.folder_task(evidence)
    app.labeller_export("plate_specialist", task, str(evidence / "dataset"))      # nothing to export: not an error
    wait_job(app)
    assert app._labeller["error"] is None
    fl.scan(paths, store, "plate_specialist", evidence)
    label_all(store, "plate_specialist", task)
    app.labeller_export("plate_specialist", task, str(evidence / "dataset"))      # inside the folder: refused
    wait_job(app)
    assert "inside the folder" in app._labeller["error"]


def test_only_a_full_path_is_accepted_as_destination(env):
    paths, store, evidence = env
    app = HarvestApp(paths, store)
    with pytest.raises(ValueError):
        app.labeller_export("plate_specialist", fl.folder_task(evidence), "relative/folder")
    with pytest.raises(ValueError):
        app.labeller_scan("plate_specialist", str(evidence / "missing"))
