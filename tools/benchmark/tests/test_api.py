"""
Benchmark API tests: the endpoints the dashboard's Benchmark tab uses, on temporary folders and a fake scorer.
No backend, models or videos needed.

    hulikamote_backend/venv/Scripts/python.exe -m pytest tools/benchmark/tests -q -p no:cacheprovider
"""
import json
import sys
import threading
import time
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tools.benchmark import api, registry, runner, service        # noqa: E402
from tools.benchmark.violations import KEYS                       # noqa: E402


def make_run(forensic: Path, name: str, keep_video: bool) -> None:
    task = forensic / name
    (task / "output").mkdir(parents=True)
    if keep_video:
        (task / "input_video.mp4").write_bytes(b"video")
    (task / "output" / "forensic_config.json").write_text(json.dumps({"active_violations": ["counterflow", "no_plate"]}))
    (task / "output" / "report.json").write_text(json.dumps([
        {"track_id": 7, "violations": ["counterflow"], "plate_text": "ABC123", "evidence_meta": [{"t": 4.0}, {"t": 6.0}]},
        {"track_id": 9, "violations": ["no_plate"], "plate_text": "unidentified", "evidence_meta": []}]))


@pytest.fixture
def env(tmp_path, monkeypatch):
    bench, forensic = tmp_path / "bench", tmp_path / "forensic"
    monkeypatch.setattr(service, "BENCH", bench)
    monkeypatch.setattr(service, "FORENSIC_DIR", forensic)
    monkeypatch.setattr(service, "EVIDENCE_DIR", tmp_path / "evidence")
    api._RUNS.clear()
    make_run(forensic, "kept", keep_video=True)
    make_run(forensic, "nokeep", keep_video=False)
    app = FastAPI()
    app.include_router(api.router)
    return TestClient(app), bench, tmp_path


def put(client, clip_id, **body):
    return client.put(f"/api/benchmark/clips/{clip_id}", json=body)


EVENT = {"violation": "counterflow", "start": 3, "end": "0:07"}


def test_an_empty_registry_lists_all_twenty_five_violations_with_nothing_yet(env):
    client, _, _ = env
    body = client.get("/api/benchmark/overview").json()
    assert [r["key"] for r in body["violations"]] == list(KEYS)
    assert {r["state"] for r in body["violations"]} == {"no clips yet"}
    assert body["clips"] == [] and body["reports"] == [] and body["run"] is None


def test_suggestions_show_what_a_run_flagged_and_refuse_odd_ids(env):
    client, _, _ = env
    s = client.get("/api/benchmark/suggestions/kept").json()
    assert s["enabled"] == ["counterflow", "no_plate"] and s["video_kept"] is True
    assert s["suggestions"][0] == {"violation": "counterflow", "track": 7, "start": 3.0, "end": 7.0, "plate": "ABC123"}
    assert s["suggestions"][1]["start"] is None                       # a ticket with no time
    assert client.get("/api/benchmark/suggestions/nokeep").json()["video_kept"] is False
    assert client.get("/api/benchmark/suggestions/missing").status_code == 404
    assert client.get("/api/benchmark/suggestions/..%2Fkept").status_code in (400, 404)


def test_a_clip_is_added_from_a_run_edited_and_counted(env):
    client, bench, _ = env
    r = put(client, "cf_01", task_id="kept", note=" Rizal Ave ", events=[EVENT])
    assert r.status_code == 200 and r.json()["problems"] == []
    assert (bench / "clips" / "cf_01.mp4").read_bytes() == b"video" and (bench / "settings" / "cf_01.json").exists()
    clip = r.json()["clip"]
    assert clip["note"] == "Rizal Ave" and clip["events"][0]["start"] == 3.0 and clip["events"][0]["end"] == 7.0
    assert clip["enabled"] == ["counterflow", "no_plate"] and clip["file_ok"] and clip["settings_ok"]
    # the file is a normal registry: the command line reads it too
    assert registry.load(bench / "registry.yaml").clips[0].events[0].violation == "counterflow"
    rows = {r["key"]: r for r in client.get("/api/benchmark/overview").json()["violations"]}
    assert rows["counterflow"]["events"] == 1 and rows["counterflow"]["state"].startswith("needs ")
    # a later edit needs no run: only the events change
    r = put(client, "cf_01", note="x", events=[EVENT, {"violation": "no_plate", "start": "12", "plate": "ABC 1234"}])
    assert [e["violation"] for e in r.json()["clip"]["events"]] == ["counterflow", "no_plate"]
    assert r.json()["clip"]["events"][1]["plate"] == "ABC 1234"


def test_mistakes_come_back_as_plain_messages(env):
    client, _, tmp = env
    assert "needs the forensic run" in put(client, "new_clip", events=[]).json()["detail"]
    assert "Unknown violation" in put(client, "a", task_id="kept", events=[{"violation": "flying"}]).json()["detail"]
    assert "before it starts" in put(client, "a", task_id="kept", events=[{"violation": "counterflow", "start": 9, "end": 2}]).json()["detail"]
    assert "cannot read the time" in put(client, "a", task_id="kept", events=[{"violation": "counterflow", "start": "soon"}]).json()["detail"]
    assert "nothing illegal" in put(client, "a", task_id="kept", clean=True, events=[EVENT]).json()["detail"]
    assert put(client, "bad name!", task_id="kept").status_code in (400, 404, 422)
    assert put(client, "a", task_id="missing").status_code == 404
    # a run that did not keep its video: say so, then accept the original clip
    assert "did not keep its copy" in put(client, "b", task_id="nokeep", events=[EVENT]).json()["detail"]
    original = tmp / "street.mp4"
    original.write_bytes(b"original")
    assert put(client, "b", task_id="nokeep", video_path=str(original), events=[EVENT]).status_code == 200
    assert put(client, "c", task_id="nokeep", video_path=str(tmp / "gone.mp4")).json()["detail"].startswith("Clip not found")


def test_an_event_the_settings_do_not_switch_on_is_saved_but_flagged(env):
    client, _, _ = env
    r = put(client, "h_01", task_id="kept", events=[{"violation": "no_helmet", "start": 1, "end": 2}])
    assert r.status_code == 200
    assert "do not switch it on" in r.json()["problems"][0]
    assert client.get("/api/benchmark/overview").json()["problems"]


def test_a_clip_can_be_deleted_with_its_copies(env):
    client, bench, _ = env
    put(client, "cf_01", task_id="kept", events=[EVENT])
    assert client.delete("/api/benchmark/clips/cf_01").json() == {"deleted": "cf_01"}
    assert not (bench / "clips" / "cf_01.mp4").exists() and not (bench / "settings" / "cf_01.json").exists()
    assert client.get("/api/benchmark/overview").json()["clips"] == []
    assert client.delete("/api/benchmark/clips/cf_01").status_code == 404


def test_delete_never_touches_files_outside_the_benchmark_folder(env):
    client, bench, tmp = env
    outside = tmp / "precious.mp4"
    outside.write_bytes(b"keep me")
    registry.save_raw({"clips": [{"id": "x", "file": str(outside), "settings": "settings/x.json", "clean": True, "events": []}]},
                      bench / "registry.yaml")
    assert client.delete("/api/benchmark/clips/x").status_code == 200
    assert outside.read_bytes() == b"keep me"


def ticket(track, violation, t):
    return {"track_id": track, "violations": [violation], "plate_text": "unidentified", "evidence_paths": ["a.jpg"],
            "evidence_meta": [{"file": "a.jpg", "t": t, "bbox": None}]}


def wait_for(client, run_id, status, seconds=8.0):
    end = time.time() + seconds
    while time.time() < end:
        body = client.get(f"/api/benchmark/run/{run_id}").json()
        if body["status"] == status:
            return body
        time.sleep(0.05)
    raise AssertionError(f"run never reached {status}: {body}")


def fake_scoring(monkeypatch, gate=None):
    monkeypatch.setattr(runner, "check_backend", lambda *a, **k: None)
    monkeypatch.setattr(runner, "probe", lambda video: {"seconds": 10.0, "fps": 25, "width": 1280, "height": 720})

    def run_clip(clip, base_url, overrides=None, **kw):
        if gate is not None:
            gate.wait(5)
        return {"task_id": "t1", "tickets": [ticket(1, "counterflow", 4.0)], "wall_s": 1.5}
    monkeypatch.setattr(runner, "run_clip", run_clip)


def test_a_run_scores_the_clips_in_the_background_and_saves_a_report(env, monkeypatch):
    client, bench, _ = env
    put(client, "cf_01", task_id="kept", events=[EVENT])
    fake_scoring(monkeypatch)
    started = client.post("/api/benchmark/run", json={"label": "baseline"})
    assert started.status_code == 202
    done = wait_for(client, started.json()["run_id"], "done")
    assert done["clips_done"] == 1 and done["results"][0]["caught"] == 1 and done["results"][0]["false_alarms"] == 0
    rep = client.get(f"/api/benchmark/reports/{done['report']}").json()
    assert rep["label"] == "baseline" and rep["summary"]["counterflow"]["caught"] == 1
    listed = client.get("/api/benchmark/overview").json()["reports"]
    assert listed[0]["name"] == done["report"] and listed[0]["caught"] == 1
    assert client.get("/api/benchmark/reports/nope").status_code == 404


def test_only_one_run_at_a_time_and_a_run_can_be_stopped_between_clips(env, monkeypatch):
    client, bench, _ = env
    put(client, "cf_01", task_id="kept", events=[EVENT])
    put(client, "cf_02", task_id="kept", events=[EVENT])
    gate = threading.Event()
    fake_scoring(monkeypatch, gate)
    run_id = client.post("/api/benchmark/run", json={"label": "slow"}).json()["run_id"]
    assert client.post("/api/benchmark/run", json={"label": "again"}).status_code == 409
    assert client.get("/api/benchmark/overview").json()["run"]["id"] == run_id
    client.post(f"/api/benchmark/run/{run_id}/cancel")
    gate.set()
    stopped = wait_for(client, run_id, "cancelled")
    assert stopped["clips_done"] == 1 and stopped["report"] is None


def test_a_run_needs_clips_that_can_be_judged_and_reports_a_dead_backend(env, monkeypatch):
    client, _, _ = env
    assert "No clips" in client.post("/api/benchmark/run", json={}).json()["detail"]
    put(client, "h_01", task_id="kept", events=[{"violation": "no_helmet", "start": 1, "end": 2}])
    assert "Fix these first" in client.post("/api/benchmark/run", json={}).json()["detail"]
    put(client, "h_01", events=[EVENT])
    monkeypatch.setattr(runner, "probe", lambda video: {"seconds": 1.0, "fps": 25, "width": 1, "height": 1})

    def dead(*a, **k):
        raise runner.RunError("The backend is not answering")
    monkeypatch.setattr(runner, "check_backend", dead)
    run_id = client.post("/api/benchmark/run", json={}).json()["run_id"]
    failed = wait_for(client, run_id, "failed")
    assert "not answering" in failed["error"]
    assert client.get("/api/benchmark/run/unknown").status_code == 404


def test_the_registry_round_trips_and_keeps_the_defaults(tmp_path):
    f = tmp_path / "registry.yaml"
    registry.save_raw({"defaults": {"min_events": 3}, "clips": [{"id": "a", "file": "a.mp4", "events": []}]}, f)
    text = f.read_text(encoding="utf-8")
    assert text.startswith("# Ground-truth registry") and "min_events: 3" in text
    assert registry.load_raw(f)["clips"][0]["id"] == "a"
    assert registry.load_raw(tmp_path / "missing.yaml") == {}
