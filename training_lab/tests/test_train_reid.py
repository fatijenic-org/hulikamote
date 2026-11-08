"""train_reid.py: the check on cars the model never saw, and when a new car matcher may replace the live one (CPU, tiny synthetic data)."""
import csv
import importlib.util
import json
import shutil
from pathlib import Path

import cv2
import numpy as np
import pytest
import torch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "train_reid.py"
spec = importlib.util.spec_from_file_location("train_reid", SCRIPT)
tr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tr)

needs_stock = pytest.mark.skipif(not tr.DEPLOYED.exists(), reason="the stock ckpt.t7 is not in this checkout")


def make_cars(root: Path, n_cars: int, n_photos: int, seed: int = 0, single: int = 0):
    """One folder per car: photos of one colour with a little noise, named like the evidence files (time order)."""
    rng = np.random.default_rng(seed)
    for c in range(n_cars + single):
        colour = rng.integers(30, 225, 3)
        for p in range(1 if c >= n_cars else n_photos):
            img = np.clip(colour + rng.integers(-20, 20, (140, 70, 3)), 0, 255).astype(np.uint8)
            path = root / "images" / "t1" / f"car{c:02d}" / f"{1000 + p}.jpg"
            path.parent.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(path), img)


def test_only_cars_with_two_photos_can_teach_and_photos_come_in_time_order(tmp_path):
    make_cars(tmp_path, 3, 4, single=2)
    ids = tr.collect_identities(tmp_path)
    assert sorted(ids) == ["t1/car00", "t1/car01", "t1/car02"]
    assert [f.name for f in ids["t1/car00"]] == ["1000.jpg", "1001.jpg", "1002.jpg", "1003.jpg"]


def test_spread_keeps_order_and_spaces_the_pick_evenly():
    files = list(range(100))
    picked = tr.spread(files, 5)
    assert picked == sorted(picked) and picked[0] == 0 and picked[-1] == 99 and len(picked) == 5
    assert tr.spread([1, 2, 3], 5) == [1, 2, 3]


def test_the_split_is_by_whole_cars_and_the_same_every_time():
    keys = [f"car{i:02d}" for i in range(20)]
    train, test = tr.split_cars(keys, seed=3)
    assert len(test) == 5 and set(train) | set(test) == set(keys) and not set(train) & set(test)
    assert (train, test) == tr.split_cars(list(reversed(keys)), seed=3)             # not changed by the order they came in
    assert tr.split_cars(keys, seed=4)[1] != test                                   # another seed, another unseen set
    train8, test8 = tr.split_cars(keys[:8])
    assert len(test8) == 2 and len(train8) == 6
    train5, test5 = tr.split_cars(keys[:5])
    assert len(test5) == 2 and len(train5) == 3                                      # never fewer than three to learn from


def test_the_questions_are_earlier_photos_and_the_answers_later_ones(tmp_path):
    make_cars(tmp_path, 3, 10)
    make_cars(tmp_path / "x", 1, 2)                                                  # a car with just two photos
    ids = tr.collect_identities(tmp_path)
    ids.update({"t1/two": tr.collect_identities(tmp_path / "x")["t1/car00"]})
    keys = ["t1/car00", "t1/car01", "t1/two"]
    gallery, queries = tr.probe_items(ids, keys)
    for label in range(3):
        q = [int(p.stem) for p, y in queries if y == label]
        g = [int(p.stem) for p, y in gallery if y == label]
        assert q and g and max(q) < min(g)                                           # the questions came first
    assert len([1 for _, y in queries if y == 2]) == 1 and len([1 for _, y in gallery if y == 2]) == 1


def test_a_new_model_replaces_the_live_one_only_when_clearly_better_on_enough_unseen_cars():
    assert tr.decide(0.70, 0.78, 40) == (True, "Better on cars it never saw.")
    ok, why = tr.decide(0.70, 0.71, 40)
    assert not ok and "not clearly better" in why.lower()
    ok, why = tr.decide(0.70, 0.60, 40)
    assert not ok
    ok, why = tr.decide(0.70, 0.80, 40, before_map=0.60, after_map=0.55)            # a better first guess, a worse ranking
    assert not ok and "orders the other cars worse" in why
    assert tr.decide(0.70, 0.80, 40, before_map=0.60, after_map=0.65)[0] is True
    ok, why = tr.decide(None, None, 6)
    assert not ok and "too few" in why
    ok, why = tr.decide(0.2, 0.9, 7)                                                  # a great score on 7 cars proves nothing
    assert not ok and "too few" in why


@needs_stock
def test_the_same_car_filed_by_two_analyses_is_used_once_but_cars_of_one_analysis_are_never_merged(tmp_path):
    make_cars(tmp_path, 4, 6)                                                          # t1/car00 .. car03
    images = tmp_path / "images"
    for car in ("car00", "car01"):                                                     # another analysis of the same clip files them again
        shutil.copytree(images / "t1" / car, images / "t2" / car)
    shutil.copytree(images / "t1" / "car02", images / "t1" / "car02b")                 # one analysis: a person said these are two cars
    ids = tr.collect_identities(tmp_path)
    assert len(ids) == 7
    original = torch.load(tr.DEPLOYED, map_location="cpu", weights_only=False)["net_dict"]
    kept, dropped = tr.drop_repeats(ids, tr.make_net(tr.load_net_class(), original, 2, "cpu"), "cpu")
    assert sorted(dropped) == [("t1/car00", "t2/car00"), ("t1/car01", "t2/car01")]
    assert sorted(kept) == ["t1/car02", "t1/car02b", "t1/car03", "t2/car00", "t2/car01"]
    assert kept["t2/car00"] == ids["t2/car00"]


@needs_stock
def test_scan_lists_repeats_and_jumps_for_the_manager_without_training(tmp_path):
    data, report = tmp_path / "data", tmp_path / "scan.json"
    make_cars(data, 4, 6)                                                              # t1/car00 .. car03
    images = data / "images"
    shutil.copytree(images / "t1" / "car00", images / "t2" / "car00")                  # another analysis filed car00 again: a repeat
    shutil.copytree(images / "t1" / "car02", images / "t1" / "car02b")                 # one analysis, two folders that look like one car
    assert tr.main(["--scan", str(report), "--data-dir", str(data), "--cpu"]) == 0
    scan = json.loads(report.read_text())
    assert (scan["cars"], scan["used"], scan["photos"], scan["photos_used"]) == (6, 5, 36, 30)
    assert scan["repeats"] == [{"dropped": "t1/car00", "kept": "t2/car00"}]
    assert [(j["a"], j["b"]) for j in scan["jumps"]] == [("t1/car02", "t1/car02b")] and scan["jumps"][0]["alike"] > 0.99
    assert scan["mixed"] == [] and not (tmp_path / "out").exists()                      # it only reports: nothing was trained or written
    empty = tmp_path / "empty.json"
    assert tr.main(["--scan", str(empty), "--data-dir", str(tmp_path / "nothing"), "--cpu"]) == 0
    assert json.loads(empty.read_text())["cars"] == 0


def run(tmp_path, n_cars, **extra):
    data, out = tmp_path / "data", tmp_path / "out"
    make_cars(data, n_cars, 6)
    argv = ["--epochs", "1", "--batch", "8", "--data-dir", str(data), "--out-dir", str(out), "--cpu"]
    for k, v in extra.items():
        argv += [f"--{k.replace('_', '-')}"] + ([] if v is True else [str(v)])
    assert tr.main(argv) == 0
    return out


@needs_stock
def test_a_run_writes_a_matcher_the_tracker_loads_and_a_check_on_unseen_cars(tmp_path):
    out = run(tmp_path, 10)
    m = json.loads((out / "metrics.json").read_text())
    assert m["cars"] == 10 and m["held_out_cars"] == 2 and m["check"] == "cars it never saw" and m["repeats_dropped"] == 0
    assert 0.0 <= m["before"] <= 1.0 and 0.0 <= m["after"] <= 1.0 and m["deployed"] is False and m["best_epoch"] == 1
    assert 0.0 <= m["before_map"] <= 1.0 and 0.0 <= m["after_map"] <= 1.0
    rows = list(csv.DictReader((out / "results.csv").open()))
    assert [r["epoch"] for r in rows] == ["1"] and set(rows[0]) == {"epoch", "loss", "train_acc", "val_top1"}
    # DeepSORT builds Net(reid=True) and loads the file with load_state_dict(strict): that must work, classifier shape included
    net = tr.load_net_class()(reid=True)
    state = torch.load(out / "ckpt.t7", map_location="cpu", weights_only=False)["net_dict"]
    net.load_state_dict(state)
    stock = torch.load(tr.DEPLOYED, map_location="cpu", weights_only=False)["net_dict"]
    assert all(torch.equal(state[k], stock[k]) for k in stock if k.startswith("classifier."))     # the head is the original one
    assert any(not torch.equal(state[k], stock[k]) for k in stock if not k.startswith("classifier.") and state[k].dtype.is_floating_point)


@needs_stock
def test_too_few_cars_are_trained_but_never_deployed(tmp_path):
    live = tmp_path / "live"
    live.mkdir()
    shutil.copy2(tr.DEPLOYED, live / "ckpt.t7")
    before = (live / "ckpt.t7").read_bytes()
    out = run(tmp_path, 6, deploy=True, ckpt=live / "ckpt.t7", deploy_dir=live)
    m = json.loads((out / "metrics.json").read_text())
    assert m["before"] is None and m["after"] is None and m["deployed"] is False and "too few" in m["note"].lower()
    assert (live / "ckpt.t7").read_bytes() == before and (out / "ckpt.t7").exists()


@needs_stock
@pytest.mark.parametrize("gain,deployed", [(0.5, True), (0.0, False)])
def test_deploy_backs_up_the_old_model_and_swaps_only_when_the_check_passes(tmp_path, monkeypatch, gain, deployed):
    calls = {"n": 0}

    def fake_scores(net, gallery, queries, device):     # the first call is the old model's score, later ones the new model's
        calls["n"] += 1
        v = 0.3 if calls["n"] == 1 else 0.3 + gain
        return {"rank1": v, "map": v}

    monkeypatch.setattr(tr, "scores", fake_scores)
    live = tmp_path / "live"
    live.mkdir()
    shutil.copy2(tr.DEPLOYED, live / "ckpt.t7")
    old = (live / "ckpt.t7").read_bytes()
    out = run(tmp_path, 10, deploy=True, ckpt=live / "ckpt.t7", deploy_dir=live)
    m = json.loads((out / "metrics.json").read_text())
    assert m["deployed"] is deployed
    if deployed:
        assert (live / "ckpt.t7").read_bytes() == (out / "ckpt.t7").read_bytes() != old
        assert (live / "ckpt_original.t7").read_bytes() == old and len(list(live.glob("ckpt_backup_*.t7"))) == 1
    else:
        assert (live / "ckpt.t7").read_bytes() == old and not list(live.glob("ckpt_*.t7"))
