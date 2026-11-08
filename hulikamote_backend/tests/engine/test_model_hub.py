"""
Model hub: every version of every job with its numbers, and "use this".
Runs on a temporary models/, runs/ and checkpoint folder (never the real ones); the export step is faked.
"""
import json
import sys
import types

import pytest

from engine import model_catalog as mc  # noqa: E402
from engine import model_hub as hub  # noqa: E402


def results(*scores):
    rows = "".join(f"{i},0.8,0.7,{s}\n" for i, s in enumerate(scores, 1))
    return "epoch,metrics/precision(B),metrics/recall(B),metrics/mAP50(B)\n" + rows


@pytest.fixture
def fake(tmp_path, monkeypatch):
    models, runs, ckpt = tmp_path / "models", tmp_path / "runs", tmp_path / "ckpt"
    for folder, files in {"Vehicle Detectors": ["yolo11_primary.onnx"],
                          "Helmet Detectors": ["helmet_specialist_train-2_20261005.onnx"]}.items():
        (models / folder).mkdir(parents=True)
        for f in files:
            (models / folder / f).write_bytes(b"x")
    # vehicles: train (23 epochs), train-3 (never exported, has weights), train-2 is empty and must not be listed
    for run, scores in {"train": [0.5, 0.68], "train-3": [0.6, 0.712]}.items():
        d = runs / "primary_anchor" / run
        (d / "weights").mkdir(parents=True)
        (d / "results.csv").write_text(results(*scores))
        (d / "args.yaml").write_text("epochs: 30\nimgsz: 640\nbatch: 16\n")
    (runs / "primary_anchor" / "train-3" / "weights" / "best.pt").write_bytes(b"w")
    (runs / "primary_anchor" / "train-2" / "weights").mkdir(parents=True)
    # helmet: one run that was exported
    h = runs / "helmet_specialist" / "train-2"
    h.mkdir(parents=True)
    (h / "results.csv").write_text(results(0.9))
    (ckpt).mkdir()
    (ckpt / "ckpt.t7").write_bytes(b"stock")
    monkeypatch.setattr(mc, "MODELS_DIR", models)
    monkeypatch.setattr(mc, "MANIFEST", models / "model_manifest.json")
    monkeypatch.setattr(mc, "RUNS_DIR", runs)
    monkeypatch.setattr(hub, "LAB", tmp_path)
    monkeypatch.setattr(hub, "CKPT_DIR", ckpt)
    hub._DIGESTS.clear()
    hub._CHECKS.clear()
    fake_yolo = types.SimpleNamespace(MODEL_PATH=models / "Vehicle Detectors" / "yolo11_primary.onnx")
    fake_yolo.set_model_path = lambda name: setattr(fake_yolo, "MODEL_PATH", models / "Vehicle Detectors" / name)
    monkeypatch.setitem(sys.modules, "yolo_inference", fake_yolo)
    return types.SimpleNamespace(models=models, runs=runs, ckpt=ckpt, tmp=tmp_path)


def job(name):
    return {j["job"]: j for j in hub.hub()["jobs"]}[name]


def test_every_job_is_listed_with_its_kind(fake):
    jobs = {j["job"]: j for j in hub.hub()["jobs"]}
    assert list(jobs) == ["vehicles", "plate", "helmet", "cabin", "reader", "matcher", "enhancer"]
    assert jobs["reader"]["can_switch"] is False and jobs["reader"]["versions"] == []
    assert jobs["vehicles"]["can_switch"] and jobs["matcher"]["can_switch"]


def test_runs_and_files_become_versions_with_scores(fake):
    versions = {v["id"]: v for v in job("vehicles")["versions"]}
    assert set(versions) == {"train", "train-3", "yolo11_primary.onnx"}          # the empty train-2 is not a version
    v3 = versions["train-3"]
    assert v3["name"] == "Version 3" and v3["stats"]["score"] == 0.712 and v3["epochs_planned"] == 30
    assert v3["file"] is None and v3["usable"] and not v3["live"]
    assert versions["train"]["name"] == "Version 1" and versions["train"]["best_epoch"] == 2
    stock = versions["yolo11_primary.onnx"]
    assert stock["origin"] == "stock" and stock["stats"] == {} and stock["live"]
    assert job("vehicles")["live_id"] == "yolo11_primary.onnx"


def test_an_exported_run_is_one_version_with_its_file(fake):
    versions = {v["id"]: v for v in job("helmet")["versions"]}
    assert list(versions) == ["train-2"]                                         # the file belongs to the run, no duplicate
    assert versions["train-2"]["file"] == "helmet_specialist_train-2_20261005.onnx"


def test_use_a_run_that_was_never_exported_exports_it_then_activates(fake, monkeypatch):
    calls = []

    def fake_run(cmd, **kw):
        calls.append(cmd)
        (fake.models / "Vehicle Detectors" / "primary_anchor_train-3_20261101.onnx").write_bytes(b"onnx")
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(hub.subprocess, "run", fake_run)
    msg = hub.use("vehicles", "train-3")
    assert "primary_anchor_train-3_20261101.onnx" in msg
    assert calls[0][-4:] == ["--model", "primary_anchor", "--run", "train-3"]
    assert job("vehicles")["live_id"] == "train-3"


def test_use_a_file_needs_no_export(fake, monkeypatch):
    monkeypatch.setattr(hub.subprocess, "run", lambda *a, **k: pytest.fail("must not export"))
    hub.use("helmet", "train-2")
    manifest = json.loads((fake.models / "model_manifest.json").read_text())["active_models"]
    assert manifest["helmet_specialist"].endswith("helmet_specialist_train-2_20261005.onnx")


def test_use_reports_a_failed_export_and_leaves_the_live_model(fake, monkeypatch):
    monkeypatch.setattr(hub.subprocess, "run", lambda *a, **k: types.SimpleNamespace(returncode=1, stdout="", stderr="boom\nno GPU"))
    with pytest.raises(RuntimeError, match="no GPU"):
        hub.use("vehicles", "train-3")
    assert job("vehicles")["live_id"] == "yolo11_primary.onnx"


def test_use_rejects_unknown_things(fake):
    with pytest.raises(ValueError):
        hub.use("tires", "x")
    with pytest.raises(ValueError):
        hub.use("reader", "x")                                                   # cannot switch yet
    with pytest.raises(FileNotFoundError):
        hub.use("vehicles", "train-9")


def test_per_type_scores_are_shown_when_checked(fake):
    d = fake.runs / "primary_anchor" / "train-3"
    (d / "per_class.json").write_text(json.dumps({"split": "test", "map50": 0.7, "classes": [{"name": "tricycle", "score": 0.9, "boxes": 124}]}))
    assert {v["id"]: v for v in job("vehicles")["versions"]}["train-3"]["classes"]["classes"][0]["name"] == "tricycle"


def test_check_needs_weights_and_a_detector(fake):
    with pytest.raises(FileNotFoundError):
        hub.start_check("vehicles", "train")                                     # no weights saved
    with pytest.raises(ValueError):
        hub.start_check("matcher", "x")


def test_check_marks_the_version_while_it_runs(fake, monkeypatch):
    started = []
    monkeypatch.setattr(hub.threading, "Thread", lambda target, daemon: types.SimpleNamespace(start=lambda: started.append(target)))
    assert hub.start_check("vehicles", "train-3") == "running"
    assert {v["id"]: v for v in job("vehicles")["versions"]}["train-3"]["checking"] == "running"
    assert hub.start_check("vehicles", "train-3") == "running" and len(started) == 1   # no second job


def test_matcher_stock_is_live_and_a_trained_version_can_replace_it(fake):
    versions = job("matcher")["versions"]
    assert [v["name"] for v in versions] == ["Stock"] and versions[0]["live"]
    run = fake.tmp / "runs" / "reid" / "train_100"
    run.mkdir(parents=True)
    (run / "ckpt.t7").write_bytes(b"better")
    (run / "metrics.json").write_text(json.dumps({"before": 0.8, "after": 0.85, "before_map": 0.7, "after_map": 0.75,
                                                  "held_out_cars": 12, "passed": True, "note": "Better on cars it never saw."}))
    new = next(v for v in job("matcher")["versions"] if v["kind"] == "run")
    assert new["name"] == "Version 1" and new["stats"]["score"] == 0.85 and new["passed"] and not new["live"]
    msg = hub.use("matcher", "train_100")
    assert "Version 1" in msg and (fake.ckpt / "ckpt.t7").read_bytes() == b"better"
    assert (fake.ckpt / "ckpt_original.t7").read_bytes() == b"stock"           # the first file is always kept
    live = [v for v in job("matcher")["versions"] if v["live"]]
    assert [v["id"] for v in live] == ["train_100"]
    hub.use("matcher", "ckpt_original")                                         # and we can go back
    assert (fake.ckpt / "ckpt.t7").read_bytes() == b"stock"
    assert hub.use("matcher", "ckpt_original").startswith("That version is already live")
