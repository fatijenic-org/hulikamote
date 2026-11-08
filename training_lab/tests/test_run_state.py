"""Pause / continue state (training_lab/scripts/run_state.py) on a temporary runs/ folder."""
import os
import sys

import torch

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts")))
import run_state  # noqa: E402


def make_run(root, model, name, epochs_done, planned, finished):
    run = root / "runs" / model / name
    (run / "weights").mkdir(parents=True)
    rows = "\n".join(f"{i + 1},0.{i}" for i in range(epochs_done))
    (run / "results.csv").write_text("epoch,metrics/mAP50(B)\n" + rows + "\n")
    (run / "args.yaml").write_text(f"epochs: {planned}\nmodel: yolov8n.pt\n")
    torch.save({"epoch": -1 if finished else epochs_done - 1}, run / "weights" / "last.pt")
    return run


def test_paused_run_can_continue(tmp_path, monkeypatch):
    monkeypatch.setattr(run_state, "ROOT", tmp_path)
    monkeypatch.setattr(run_state, "training_processes", lambda model: [])
    make_run(tmp_path, "cabin_specialist", "train", 68, 100, finished=False)
    s = run_state.state("cabin_specialist")
    assert s["resumable"] and not s["training"]
    assert (s["epochs_done"], s["epochs_total"]) == (68, 100)
    cmd = run_state.resume_command("python", "cabin_specialist")
    assert "resume=True" in cmd[-1] and "last.pt" in cmd[-1]


def test_finished_run_cannot_continue(tmp_path, monkeypatch):
    monkeypatch.setattr(run_state, "ROOT", tmp_path)
    monkeypatch.setattr(run_state, "training_processes", lambda model: [])
    make_run(tmp_path, "helmet_specialist", "train", 62, 100, finished=True)   # early-stopped = finished
    s = run_state.state("helmet_specialist")
    assert not s["resumable"] and "already finished" in s["message"]


def test_training_now_is_not_resumable(tmp_path, monkeypatch):
    monkeypatch.setattr(run_state, "ROOT", tmp_path)
    monkeypatch.setattr(run_state, "training_processes", lambda model: ["fake process"])
    make_run(tmp_path, "plate_specialist", "train", 3, 100, finished=False)
    s = run_state.state("plate_specialist")
    assert s["training"] and not s["resumable"]


def test_no_runs(tmp_path, monkeypatch):
    monkeypatch.setattr(run_state, "ROOT", tmp_path)
    monkeypatch.setattr(run_state, "training_processes", lambda model: [])
    s = run_state.state("primary_anchor")
    assert s["run"] is None and not s["resumable"] and not s["training"]
