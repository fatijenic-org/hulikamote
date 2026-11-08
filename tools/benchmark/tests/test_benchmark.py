"""
Benchmark tests: scoring maths, registry checks, the runner against a fake backend, adopt. No backend, models or videos needed.

    hulikamote_backend/venv/Scripts/python.exe -m pytest tools/benchmark/tests -q -p no:cacheprovider
"""
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tools.benchmark import __main__ as cli                      # noqa: E402
from tools.benchmark import checklist, registry, report, runner, scoring   # noqa: E402
from tools.benchmark.registry import Clip, Event, RegistryError, parse_time   # noqa: E402
from tools.benchmark.violations import BY_KEY, KEYS, NEEDS       # noqa: E402

DEFAULTS = {"tolerance_s": 3.0, "min_events": 3, "pass": {"precision": 0.8, "recall": 0.8}}


def ticket(track, violations, times, plate="unidentified", files=("a.jpg",), bbox=None):
    meta = [{"file": f, "t": t, "bbox": bbox} for f, t in zip(files * len(times), times)]
    return {"track_id": track, "violations": list(violations), "plate_text": plate, "evidence_meta": meta,
            "evidence_paths": list(files)}


def clip(events, enabled=("counterflow", "no_plate"), clean=False, cid="c1"):
    return Clip(cid, Path("x.mp4"), None, events, clean, settings={"active_violations": list(enabled)})


# --------------------------------------------------------------------------- the 25 violations

def test_the_twenty_five_keys_match_the_backend():
    assert len(KEYS) == 25 and len(set(KEYS)) == 25
    backend = ROOT / "hulikamote_backend"
    sys.path.insert(0, str(backend))
    try:
        from engine.violations import REGISTRY
    except Exception as e:                                       # the backend's packages are not installed here
        pytest.skip(f"backend not importable: {e}")
    finally:
        sys.path.remove(str(backend))
    assert set(KEYS) == set(REGISTRY)


def test_every_violation_has_a_checklist_row_and_the_spec_text():
    text = checklist.markdown(10)
    assert all(f"`{n.key}`" in text for n in NEEDS)
    assert "Fixed camera" in text and "Never ask anyone to break traffic rules" in text
    assert all(n.film and n.negative and n.view and n.setup for n in NEEDS)


# --------------------------------------------------------------------------- registry

def test_times_can_be_seconds_or_minutes_and_seconds():
    assert parse_time(3) == 3.0 and parse_time("12.5") == 12.5 and parse_time("1:05") == 65.0 and parse_time("0:01:05.5") == 65.5
    with pytest.raises(RegistryError):
        parse_time("soon")


def write_registry(tmp_path, body):
    (tmp_path / "registry.yaml").write_text(body, encoding="utf-8")
    return registry.load(tmp_path / "registry.yaml")


def test_registry_loads_events_and_rejects_mistakes(tmp_path):
    (tmp_path / "settings").mkdir()
    (tmp_path / "settings" / "a.json").write_text(json.dumps({"active_violations": ["counterflow"]}))
    reg = write_registry(tmp_path, "clips:\n  - id: a\n    file: clips/a.mp4\n    settings: settings/a.json\n"
                                   "    events:\n      - {violation: counterflow, start: '0:03', end: 8}\n")
    c = reg.clips[0]
    assert c.events[0].start == 3.0 and c.enabled == {"counterflow"} and reg.defaults["tolerance_s"] == 3.0
    assert any("video not found" in p for p in registry.problems(reg))
    for bad in ("{violation: made_up, start: 1, end: 2}", "{violation: counterflow, start: 9, end: 2}"):
        with pytest.raises(RegistryError):
            write_registry(tmp_path, f"clips:\n  - id: b\n    file: b.mp4\n    events: [{bad}]\n")
    with pytest.raises(RegistryError):                                 # a clean clip cannot have events
        write_registry(tmp_path, "clips:\n  - id: b\n    file: b.mp4\n    clean: true\n    events: [{violation: counterflow, start: 1, end: 2}]\n")


def test_problems_flags_events_whose_violation_is_not_switched_on(tmp_path):
    (tmp_path / "s.json").write_text(json.dumps({"active_violations": ["counterflow"]}))
    (tmp_path / "a.mp4").write_bytes(b"x")
    reg = write_registry(tmp_path, "clips:\n  - id: a\n    file: a.mp4\n    settings: s.json\n"
                                   "    events: [{violation: no_plate, start: 1, end: 2}]\n")
    assert any("do not switch it on" in p for p in registry.problems(reg))


# --------------------------------------------------------------------------- matching and scoring

def test_a_ticket_catches_an_event_inside_the_tolerance_only():
    e = [Event("counterflow", 10, 14)]
    for times, caught in (([11], True), ([16.5], True), ([18], False), ([2], False)):
        p = scoring.predictions([ticket(1, ["counterflow"], times)])
        pairs, missed, extra = scoring.match(e, p, 3.0)
        assert (len(pairs) == 1) is caught and (len(missed) == 0) is caught and (len(extra) == 0) is caught


def test_matching_is_one_to_one_and_prefers_the_closest_time():
    events = [Event("counterflow", 10, 12), Event("counterflow", 40, 42)]
    tickets = [ticket(1, ["counterflow"], [41]), ticket(2, ["counterflow"], [11]), ticket(3, ["counterflow"], [11.5])]
    pairs, missed, extra = scoring.match(events, scoring.predictions(tickets), 3.0)
    assert pairs == [(0, 1), (1, 0)] and extra == [2] and missed == []


def test_other_violations_never_match_and_unknown_time_is_a_last_resort():
    e = [Event("no_plate", 5, 6)]
    assert scoring.match(e, scoring.predictions([ticket(1, ["counterflow"], [5])]), 3.0)[0] == []
    untimed = {"track_id": 9, "violations": ["no_plate"], "plate_text": "", "evidence_meta": [], "evidence_paths": []}
    assert len(scoring.match(e, scoring.predictions([untimed]), 3.0)[0]) == 1


def test_violations_that_are_not_switched_on_are_not_judged():
    c = clip([Event("counterflow", 1, 2), Event("no_plate", 1, 2)], enabled=("counterflow",))
    r = scoring.score_clip(c, [ticket(1, ["counterflow", "no_plate"], [1.5])], 3.0)
    assert [x["violation"] for x in r.caught] == ["counterflow"] and r.false_alarms == [] and r.skipped == ["no_plate"]


def test_every_ticket_on_a_clean_clip_is_a_false_alarm():
    r = scoring.score_clip(clip([], clean=True), [ticket(1, ["counterflow"], [3]), ticket(2, ["no_plate"], [9])], 3.0, seconds=120)
    assert len(r.false_alarms) == 2 and not r.caught and not r.missed


def test_logging_checks_plate_evidence_and_vehicle(tmp_path):
    (tmp_path / "a.jpg").write_bytes(b"x")
    e = Event("counterflow", 10, 12, plate="ab 12-3", box=[0.4, 0.4, 0.6, 0.6])
    good = scoring.predictions([ticket(1, ["counterflow"], [11], plate="AB123", bbox=[400, 400, 200, 200])])[0]
    assert scoring.logging_check(e, good, (1000, 1000), tmp_path)["ok"] is True
    wrong_plate = scoring.predictions([ticket(1, ["counterflow"], [11], plate="AB124", bbox=[400, 400, 200, 200])])[0]
    assert scoring.logging_check(e, wrong_plate, (1000, 1000), tmp_path)["plate"] is False
    elsewhere = scoring.predictions([ticket(1, ["counterflow"], [11], plate="AB123", bbox=[0, 0, 100, 100])])[0]
    assert scoring.logging_check(e, elsewhere, (1000, 1000), tmp_path)["vehicle"] is False
    no_file = scoring.predictions([ticket(1, ["counterflow"], [11], plate="AB123", files=("missing.jpg",), bbox=[400, 400, 200, 200])])[0]
    assert scoring.logging_check(e, no_file, (1000, 1000), tmp_path)["evidence"] is False
    nothing_expected = scoring.logging_check(Event("counterflow", 10, 12), good, None, None)
    assert nothing_expected["plate"] is None and nothing_expected["vehicle"] is None and nothing_expected["ok"] is True


def test_summary_gives_precision_recall_and_an_honest_verdict():
    c = clip([Event("counterflow", t, t + 2) for t in (10, 30, 50)])
    r = scoring.score_clip(c, [ticket(1, ["counterflow"], [11]), ticket(2, ["counterflow"], [31]), ticket(3, ["counterflow"], [90])],
                           3.0, seconds=120)
    s = scoring.summarize([r], DEFAULTS)["counterflow"]
    assert (s["caught"], s["false_alarms"], s["missed"]) == (2, 1, 1)
    assert s["precision"] == pytest.approx(2 / 3) and s["recall"] == pytest.approx(2 / 3)
    assert s["false_alarms_per_min"] == pytest.approx(0.5) and s["status"] == "FAIL"
    perfect = scoring.summarize([scoring.score_clip(c, [ticket(i, ["counterflow"], [t + 1]) for i, t in enumerate((10, 30, 50))], 3.0)], DEFAULTS)
    assert perfect["counterflow"]["status"] == "PASS"
    few = scoring.summarize([scoring.score_clip(clip([Event("counterflow", 1, 2)]), [ticket(1, ["counterflow"], [1])], 3.0)], DEFAULTS)
    assert few["counterflow"]["status"].startswith("too few events")
    none = scoring.summarize([scoring.score_clip(clip([], clean=True), [], 3.0)], DEFAULTS)
    assert none["counterflow"]["status"] == "no real events in any clip" and none["counterflow"]["precision"] is None


# --------------------------------------------------------------------------- report

def test_report_names_what_is_missing_and_compares_two_runs():
    c = clip([Event("counterflow", 10, 12)])
    r1 = report.build("baseline", [scoring.score_clip(c, [], 3.0, seconds=60)], DEFAULTS, {})
    r2 = report.build("finetuned", [scoring.score_clip(c, [ticket(1, ["counterflow"], [11])], 3.0, seconds=60)], DEFAULTS, {})
    md = report.markdown(r2)
    assert "Caught" in md and "Not benchmarked yet" in md and "pickup_passengers" in md
    assert r1["summary"]["counterflow"]["recall"] == 0 and r2["summary"]["counterflow"]["recall"] == 1
    cmp = report.compare(r1, r2)
    assert "baseline vs finetuned" in cmp and "+100 pts" in cmp


# --------------------------------------------------------------------------- runner and adopt

class FakeResponse:
    def __init__(self, data):
        self._d = data

    def json(self):
        return self._d

    def raise_for_status(self):
        pass


class FakeBackend:
    """Stands in for `requests`: remembers the upload and answers 'processing' once, then 'completed'."""

    def __init__(self, status_sequence):
        self.seq = list(status_sequence)
        self.uploaded = None

    def get(self, url, timeout=0):
        return FakeResponse(self.seq.pop(0) if len(self.seq) > 1 else self.seq[0])

    def post(self, url, files=None, data=None, timeout=0):
        self.uploaded = json.loads(data["config_json"])
        return FakeResponse({"task_id": "t-123"})


def test_runner_uploads_with_benchmark_mode_and_returns_the_tickets(tmp_path):
    video = tmp_path / "a.mp4"
    video.write_bytes(b"x")
    c = Clip("a", video, None, [], settings={"active_violations": ["counterflow"], "tracker": "deepsort"})
    fake = FakeBackend([{"status": "processing", "progress": 10}, {"status": "completed", "tickets": [{"track_id": 1}]}])
    out = runner.run_clip(c, client=fake, overrides={"primary_model": "m.onnx"}, poll_s=0, log=lambda *_: None)
    assert out["tickets"] == [{"track_id": 1}] and out["task_id"] == "t-123"
    assert fake.uploaded["benchmark"] is True and fake.uploaded["primary_model"] == "m.onnx" and fake.uploaded["tracker"] == "deepsort"
    failing = FakeBackend([{"status": "failed", "error": "boom"}])
    with pytest.raises(runner.RunError, match="boom"):
        runner.run_clip(c, client=failing, poll_s=0, log=lambda *_: None)
    with pytest.raises(runner.RunError, match="no settings"):
        runner.run_clip(Clip("b", video, None, []), client=fake)


def test_adopt_copies_the_run_and_adds_a_registry_entry(tmp_path, monkeypatch, capsys):
    task = tmp_path / "forensic" / "task1"
    (task / "output").mkdir(parents=True)
    (task / "input_video.mp4").write_bytes(b"video")
    (task / "output" / "forensic_config.json").write_text(json.dumps({"active_violations": ["counterflow"]}))
    (task / "output" / "report.json").write_text(json.dumps([ticket(7, ["counterflow"], [4.0, 6.0], plate="ABC123")]))
    bench = tmp_path / "bench"
    bench.mkdir()
    monkeypatch.setattr(cli, "FORENSIC", tmp_path / "forensic")
    monkeypatch.setattr(cli, "BENCH", bench)
    ns = type("A", (), {"task_id": "task1", "clip_id": "cf_01", "note": 'says "wrong way"', "video": None})()
    assert cli.cmd_adopt(ns) == 0
    assert (bench / "clips" / "cf_01.mp4").read_bytes() == b"video" and (bench / "settings" / "cf_01.json").exists()
    reg = registry.load(bench / "registry.yaml")
    assert reg.clips[0].id == "cf_01" and reg.clips[0].note == 'says "wrong way"' and reg.clips[0].events == []
    shown = capsys.readouterr().out
    assert "violation: counterflow, start: 3.0, end: 7.0" in shown and 'plate: "ABC123"' in shown
    assert cli.cmd_adopt(ns) == 0                                       # a second time keeps one entry
    assert len(registry.load(bench / "registry.yaml").clips) == 1
    ns.task_id = "nope"
    assert cli.cmd_adopt(ns) == 1


def test_adopt_can_take_the_original_clip_when_the_run_did_not_keep_its_video(tmp_path, monkeypatch, capsys):
    task = tmp_path / "forensic" / "task2"
    (task / "output").mkdir(parents=True)                                # no input_video.mp4: "Keep the uploaded video" was off
    (task / "output" / "forensic_config.json").write_text(json.dumps({"active_violations": ["no_helmet"]}))
    original = tmp_path / "street.mp4"
    original.write_bytes(b"original")
    bench = tmp_path / "bench"
    bench.mkdir()
    monkeypatch.setattr(cli, "FORENSIC", tmp_path / "forensic")
    monkeypatch.setattr(cli, "BENCH", bench)
    ns = type("A", (), {"task_id": "task2", "clip_id": "h_01", "note": "", "video": None})()
    assert cli.cmd_adopt(ns) == 1 and "--video" in capsys.readouterr().out      # tells how to fix it
    ns.video = tmp_path / "missing.mp4"
    assert cli.cmd_adopt(ns) == 1 and "Clip not found" in capsys.readouterr().out
    ns.video = original
    assert cli.cmd_adopt(ns) == 0
    assert (bench / "clips" / "h_01.mp4").read_bytes() == b"original" and (bench / "settings" / "h_01.json").exists()


def test_loar_cer_and_wer_follow_the_thesis_definitions():
    events = [Event("no_helmet", 10, 12, plate="ABC123"), Event("no_helmet", 30, 32, plate="DEF456"),
              Event("no_helmet", 50, 52, plate="GHI789"), Event("no_helmet", 70, 72)]       # the last has no plate written
    tickets = [ticket(1, ["no_helmet"], [11], plate="ABC123"), ticket(2, ["no_helmet"], [31], plate="DEF466"),
               ticket(3, ["no_helmet"], [51], plate="unidentified"), ticket(4, ["no_helmet"], [71], plate="XYZ000")]
    s = scoring.summarize([scoring.score_clip(clip(events, enabled=("no_helmet",)), tickets, 3.0)], DEFAULTS)["no_helmet"]
    assert s["caught"] == 4 and s["plates"]["checked"] == 3                    # the plate-less event cannot be checked
    assert s["plates"]["loar"] == pytest.approx(1 / 3)                         # only ABC123 is fully right
    assert s["plates"]["cer"] == pytest.approx((0 + 1 + 6) / 18)               # edits / characters of the true plates
    assert s["plates"]["wer"] == pytest.approx(2 / 3)                          # whole plate strings that are wrong
    o = scoring.overall({"no_helmet": s})
    assert o["loar"] == pytest.approx(1 / 3) and o["cer"] == pytest.approx(7 / 18) and o["plates_checked"] == 3
    md = report.markdown(report.build("t", [scoring.score_clip(clip(events, enabled=("no_helmet",)), tickets, 3.0, seconds=90)], DEFAULTS, {}))
    assert "**LOAR**" in md and "CER 39%" in md and "WER 67%" in md


def test_a_wrong_vehicle_breaks_loar_even_with_the_right_plate():
    e = Event("counterflow", 10, 12, plate="ABC123", box=[0.0, 0.0, 0.2, 0.2])
    far = scoring.predictions([ticket(1, ["counterflow"], [11], plate="ABC123", bbox=[600, 600, 200, 200])])[0]
    assert scoring.logging_check(e, far, (1000, 1000), None)["loar"] is False
