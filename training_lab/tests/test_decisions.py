"""
The journal of box decisions and "add a class": nothing is lost when label files are rewritten, old class numbers never change.

    hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests/test_decisions.py -q -p no:cacheprovider
"""
import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data_tools import common, decisions   # noqa: E402

YAML = """# Primary Anchor Dataset
path: datasets/primary_anchor
train: images/train

nc: 3
names:
  0: car
  1: truck     # big ones
  2: person    # REQUIRED
test: images/test
"""


@pytest.fixture()
def ds(tmp_path):
    base = tmp_path / "datasets" / "toy"
    (base / "labels" / "train").mkdir(parents=True)
    (base / "labels" / "val").mkdir(parents=True)
    (base / "data.yaml").write_text(YAML, encoding="utf-8")
    (base / "labels" / "train" / "srcA__one.txt").write_text("1 0.500000 0.500000 0.200000 0.200000\n0 0.2 0.2 0.1 0.1\n")
    (base / "labels" / "val" / "srcA__two.txt").write_text("1 0.4 0.4 0.3 0.3\n")
    return tmp_path / "datasets"


def test_adding_a_class_keeps_old_numbers_comments_and_other_keys(ds):
    path = ds / "toy" / "data.yaml"
    cid, added = decisions.add_class_to_yaml(path, "pickup")
    assert (cid, added) == (3, True)
    text = path.read_text(encoding="utf-8")
    assert "nc: 4" in text and "  3: pickup" in text
    assert "  1: truck     # big ones" in text and "# REQUIRED" in text and "test: images/test" in text
    assert text.index("3: pickup") < text.index("test: images/test")       # inside the names block
    assert decisions.class_ids(path) == {"car": 0, "truck": 1, "person": 2, "pickup": 3}


def test_adding_a_class_twice_adds_it_once(ds):
    path = ds / "toy" / "data.yaml"
    decisions.add_class_to_yaml(path, "pickup")
    assert decisions.add_class_to_yaml(path, "pickup") == (3, False)
    assert path.read_text(encoding="utf-8").count("pickup:") == 0 and path.read_text().count(": pickup") == 1


@pytest.mark.parametrize("bad", ["", "Pickup", "pick up", "../x", "9lives", "a" * 40, None])
def test_a_bad_class_name_is_refused(ds, bad):
    with pytest.raises(decisions.DecisionError):
        decisions.add_class_to_yaml(ds / "toy" / "data.yaml", bad)


def test_a_flow_style_class_list_is_refused_not_mangled(ds):
    path = ds / "toy" / "data.yaml"
    path.write_text("nc: 2\nnames: [car, truck]\n", encoding="utf-8")
    with pytest.raises(decisions.DecisionError):
        decisions.add_class_to_yaml(path, "pickup")
    assert path.read_text(encoding="utf-8") == "nc: 2\nnames: [car, truck]\n"


def test_the_journal_remembers_the_latest_decision_and_counts(ds):
    j = decisions.Journal(ds, "toy")
    j.append([j.make("a1", "train", "srcA__one.jpg", [0.5, 0.5, 0.2, 0.2], "truck", "move", "pickup"),
              j.make("a1", "val", "srcA__two.jpg", [0.4, 0.4, 0.3, 0.3], "truck", "keep")])
    assert decisions.Journal(ds, "toy").counts("truck") == {"reviewed": 2, "moved": 1, "kept": 1}
    j.append([j.make("a2", "train", "srcA__one.jpg", [0.5, 0.5, 0.2, 0.2], "truck", "keep")])   # changed my mind
    assert decisions.Journal(ds, "toy").counts("truck") == {"reviewed": 2, "moved": 0, "kept": 2}


def test_undo_takes_back_only_that_actions_lines(ds):
    j = decisions.Journal(ds, "toy")
    j.append([j.make("a1", "train", "srcA__one.jpg", [0.5, 0.5, 0.2, 0.2], "truck", "move", "pickup"),
              j.make("a2", "val", "srcA__two.jpg", [0.4, 0.4, 0.3, 0.3], "truck", "keep")])
    assert j.drop_action("a1") == 1
    assert list(decisions.Journal(ds, "toy").entries()) == [decisions.box_sig("srcA__two.jpg", [0.4, 0.4, 0.3, 0.3])]
    assert j.drop_action("nope") == 0


def test_a_broken_journal_line_is_ignored(ds):
    path = decisions.journal_file(ds, "toy")
    path.parent.mkdir(parents=True)
    path.write_text('garbage\n{"name": "x.jpg", "box": [0.1, 0.1, 0.2, 0.2], "decision": "keep", "from": "truck"}\n', encoding="utf-8")
    assert len(decisions.Journal(ds, "toy").entries()) == 1


def test_reapply_puts_the_pickups_back_after_a_label_rewrite(ds):
    j = decisions.Journal(ds, "toy")
    j.append([j.make("a1", "train", "srcA__one.jpg", [0.5, 0.5, 0.2, 0.2], "truck", "move", "pickup"),
              j.make("a1", "val", "srcA__two.jpg", [0.4, 0.4, 0.3, 0.3], "truck", "keep")])
    out = decisions.reapply(ds, "toy")                       # the re-merge restored "truck": add the class and move the box
    assert out["applied"] == 1 and out["class_id"] == 3
    first = common.read_yolo(ds / "toy" / "labels" / "train" / "srcA__one.txt")
    assert [b[0] for b in first] == [3, 0]                   # the pickup, and the car next to it untouched
    assert common.read_yolo(ds / "toy" / "labels" / "val" / "srcA__two.txt")[0][0] == 1      # "keep" never changes a label
    again = decisions.reapply(ds, "toy")
    assert again["applied"] == 0 and again["already"] == 1   # safe to repeat


def test_reapply_finds_a_box_that_moved_a_hair_and_skips_what_changed_class_or_vanished(ds):
    j = decisions.Journal(ds, "toy")
    j.append([j.make("a", "train", "srcA__one.jpg", [0.5005, 0.5, 0.2, 0.2], "truck", "move", "pickup"),     # moved a hair
              j.make("a", "val", "srcA__two.jpg", [0.4, 0.4, 0.3, 0.3], "bus", "move", "pickup"),             # now another class than it came from
              j.make("a", "val", "gone__x.jpg", [0.4, 0.4, 0.3, 0.3], "truck", "move", "pickup"),             # picture is gone
              j.make("a", "train", "srcA__one.jpg", [0.9, 0.9, 0.05, 0.05], "truck", "move", "pickup")])      # no such box any more
    out = decisions.reapply(ds, "toy")
    assert (out["applied"], out["different_class"], out["image_missing"], out["box_missing"]) == (1, 1, 1, 1)


def test_reapply_refuses_while_training_and_changes_nothing(ds):
    j = decisions.Journal(ds, "toy")
    j.append([j.make("a1", "train", "srcA__one.jpg", [0.5, 0.5, 0.2, 0.2], "truck", "move", "pickup")])
    with pytest.raises(decisions.DecisionError):
        decisions.reapply(ds, "toy", is_training=lambda m: True)
    assert "pickup" not in (ds / "toy" / "data.yaml").read_text()


def test_curate_with_apply_puts_the_decisions_back(tmp_path, monkeypatch):
    """`data.py curate --apply` calls the same re-apply, so cleaning never erases hand work."""
    from PIL import Image
    from data_tools import curate
    ds = tmp_path / "datasets"
    base = ds / "toy"
    for sub in ("images/train", "labels/train", "images/val", "labels/val", "images/test", "labels/test"):
        (base / sub).mkdir(parents=True)
    (base / "data.yaml").write_text(YAML, encoding="utf-8")
    for n in range(3):
        noise = np.random.default_rng(n).integers(0, 255, (64, 64, 3), dtype=np.uint8)      # different pictures: none is a "twin"
        Image.fromarray(noise).save(base / "images" / "train" / f"srcA__p{n}.jpg", "JPEG")
        (base / "labels" / "train" / f"srcA__p{n}.txt").write_text("1 0.5 0.5 0.4 0.4\n")
    monkeypatch.setattr(common, "DATASETS", ds)
    monkeypatch.setattr(common, "QUARANTINE", ds / "_quarantine")
    monkeypatch.setattr(curate, "DATASETS", ds)
    j = decisions.Journal(ds, "toy")
    j.append([j.make("a", "train", "srcA__p0.jpg", [0.5, 0.5, 0.4, 0.4], "truck", "move", "pickup")])
    lines = []
    curate.curate_model("toy", apply=True, log=lines.append)
    assert common.read_yolo(base / "labels" / "train" / "srcA__p0.txt")[0][0] == 3
    assert common.read_yolo(base / "labels" / "train" / "srcA__p1.txt")[0][0] == 1
    assert any("put back as 'pickup'" in x for x in lines)
    dry = []
    curate.curate_model("toy", apply=False, log=dry.append)                          # a dry run changes nothing and says nothing of it
    assert not any("put back" in x for x in dry)
