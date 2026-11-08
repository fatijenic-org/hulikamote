"""
Model catalog: models grouped by job, one active per job, training scores read back.
Runs on a temporary models/ and runs/ folder (never the real ones).
"""
import json
import sys
import types

import pytest


from engine import model_catalog as mc  # noqa: E402


@pytest.fixture
def fake_dirs(tmp_path, monkeypatch):
    models, runs = tmp_path / "models", tmp_path / "runs"
    for folder, files in {"Vehicle Detectors": ["yolov8n.onnx", "yolo11_primary.onnx"],
                          "Helmet Detectors": ["helmet_specialist_train3_20261005.onnx"],
                          "Plate Models": ["plate_specialist.onnx"]}.items():
        (models / folder).mkdir(parents=True)
        for f in files:
            (models / folder / f).write_bytes(b"x")
    run = runs / "helmet_specialist" / "train3"
    run.mkdir(parents=True)
    (run / "results.csv").write_text(
        "epoch,metrics/precision(B),metrics/recall(B),metrics/mAP50(B)\n"
        "1,0.80,0.70,0.75\n2,0.95,0.93,0.97\n3,0.90,0.90,0.91\n")
    monkeypatch.setattr(mc, "MODELS_DIR", models)
    monkeypatch.setattr(mc, "MANIFEST", models / "model_manifest.json")
    monkeypatch.setattr(mc, "RUNS_DIR", runs)
    fake_yolo = types.SimpleNamespace(MODEL_PATH=models / "Vehicle Detectors" / "yolov8n.onnx")
    fake_yolo.set_model_path = lambda name: setattr(fake_yolo, "MODEL_PATH", models / "Vehicle Detectors" / name)
    monkeypatch.setitem(sys.modules, "yolo_inference", fake_yolo)
    return models


def by_type(cat):
    return {t["type"]: t for t in cat["types"]}


def test_catalog_groups_models_and_reads_training_scores(fake_dirs):
    cat = by_type(mc.catalog())
    assert {m["name"] for m in cat["vehicles"]["models"]} == {"yolov8n.onnx", "yolo11_primary.onnx"}
    helmet = cat["helmet"]["models"][0]
    assert helmet["source"]["run"] == "train3"
    assert helmet["source"]["best_score"] == 0.97 and helmet["source"]["best_epoch"] == 2
    assert cat["plate"]["models"][0]["source"] is None          # stock / imported model
    assert cat["cabin"]["models"] == [] and cat["cabin"]["active"] is None


def test_defaults_when_nothing_activated(fake_dirs):
    cat = by_type(mc.catalog())
    assert cat["vehicles"]["active"] == "yolov8n.onnx"
    assert cat["plate"]["active"] == "plate_specialist.onnx"   # default file name
    assert cat["helmet"]["active"] is None                      # no default helmet_specialist.onnx


def test_activate_sets_one_active_model_per_type(fake_dirs):
    mc.activate("helmet", "helmet_specialist_train3_20261005.onnx")
    mc.activate("vehicles", "yolo11_primary.onnx")
    cat = by_type(mc.catalog())
    assert cat["helmet"]["active"] == "helmet_specialist_train3_20261005.onnx"
    assert cat["vehicles"]["active"] == "yolo11_primary.onnx"
    manifest = json.loads((fake_dirs / "model_manifest.json").read_text())["active_models"]
    assert manifest["helmet_specialist"] == "Helmet Detectors/helmet_specialist_train3_20261005.onnx"


def test_activate_rejects_wrong_type_or_folder(fake_dirs):
    with pytest.raises(FileNotFoundError):
        mc.activate("helmet", "yolov8n.onnx")        # a vehicle detector is not a helmet model
    with pytest.raises(ValueError):
        mc.activate("tires", "x.onnx")
