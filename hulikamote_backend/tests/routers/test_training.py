"""
The Training Studio polls /status and /state every few seconds while a run is followed, so both
must stay cheap and must never run on the event loop (that froze live video every 2 seconds).
"""
import inspect
import time

import pytest
from fastapi import HTTPException

from routers import training

TASK = "11111111-2222-3333-4444-555555555555"


@pytest.fixture
def log(tmp_path, monkeypatch):
    monkeypatch.setattr(training, "LOGS_DIR", tmp_path)
    monkeypatch.setitem(training.TRAINING_TASKS, TASK, {"status": "running", "model": "plate_specialist"})
    return tmp_path / f"{TASK}.log"


def test_a_huge_log_is_answered_with_its_tail_only(log):
    lines = [f"      {i % 100}/100      2.1G      1.2  progress line {i}" for i in range(60_000)]
    log.write_text("\n".join(lines), encoding="utf-8")            # about 3 MB
    t0 = time.perf_counter()
    res = training.get_training_status(TASK)
    assert time.perf_counter() - t0 < 0.5
    assert res["log_truncated"] is True
    assert len(res["logs"]) < 120_000
    assert res["logs"].rstrip().endswith("progress line 59999")
    assert (res["current_epoch"], res["total_epochs"]) == (99, 100)
    assert res["status"] == "running"


def test_a_small_log_comes_back_whole_with_carriage_return_progress_cleaned(log):
    log.write_text("start\n   3/30   1.0G  step 1\r   3/30   1.0G  step 2\nend", encoding="utf-8")
    res = training.get_training_status(TASK)
    assert res["log_truncated"] is False
    assert res["logs"].split("\n") == ["start", "   3/30   1.0G  step 2", "end"]
    assert (res["current_epoch"], res["total_epochs"]) == (3, 30)


def test_unknown_task_and_missing_log(log):
    with pytest.raises(HTTPException) as e:
        training.get_training_status("00000000-0000-0000-0000-000000000000")
    assert e.value.status_code == 404
    res = training.get_training_status(TASK)       # task exists, no log written yet
    assert res["logs"] == "" and res["log_truncated"] is False


def test_polled_endpoints_run_in_a_worker_thread_not_on_the_event_loop():
    for fn in (training.get_training_status, training.training_state, training.training_log):
        assert not inspect.iscoroutinefunction(fn), fn.__name__


def test_state_is_answered_from_a_short_cache(monkeypatch):
    calls = []
    monkeypatch.setattr(training.run_state, "state", lambda m: calls.append(m) or {"model": m, "training": False})
    training._STATE_CACHE.clear()
    training.training_state("plate_specialist")
    training.training_state("plate_specialist")
    assert calls == ["plate_specialist"]
    training.training_state("helmet_specialist")      # another model is its own entry
    assert calls == ["plate_specialist", "helmet_specialist"]


def test_pause_does_not_answer_from_the_cache(monkeypatch):
    monkeypatch.setattr(training.run_state, "pause", lambda m: 1)
    states = iter([{"training": True}, {"training": False, "resumable": True}])
    monkeypatch.setattr(training.run_state, "state", lambda m: next(states))
    training._STATE_CACHE.clear()
    assert training.training_state("plate_specialist") == {"training": True}      # cached now
    import asyncio
    res = asyncio.run(training.pause_training("plate_specialist"))
    assert res["training"] is False                                                # fresh, not the cache
    assert "plate_specialist" not in training._STATE_CACHE


# ─── the dashboard button that opens the terminal Training Lab ───────────────

class _Popped:
    pid = 4242


@pytest.fixture
def opened(monkeypatch):
    """Records what the open-lab button would start, without opening a window."""
    calls = []
    monkeypatch.setattr(training.subprocess, "Popen", lambda cmd, **kw: calls.append((cmd, kw)) or _Popped())
    return calls


def test_open_lab_starts_the_plain_menu_in_its_own_console(opened):
    import asyncio
    assert asyncio.run(training.open_training_lab()) == {"status": "opened", "pid": 4242}
    cmd, kw = opened[0]
    assert cmd[1].endswith("lab.py") and len(cmd) == 2
    if training.os.name == "nt":
        assert kw["creationflags"] & training.subprocess.CREATE_NEW_CONSOLE


def test_open_lab_can_open_straight_on_a_model(opened):
    import asyncio
    asyncio.run(training.open_training_lab(model="primary_anchor"))
    assert opened[0][0][2:] == ["--model", "primary_anchor"]


def test_open_lab_refuses_a_model_it_does_not_know(opened):
    import asyncio
    with pytest.raises(HTTPException) as err:
        asyncio.run(training.open_training_lab(model="rm -rf"))
    assert err.value.status_code == 400 and opened == []


def test_open_lab_can_still_open_the_full_screen_app(opened):
    import asyncio
    asyncio.run(training.open_training_lab(model="helmet_specialist", ui="tui"))
    cmd = opened[0][0]
    assert cmd[1].endswith("lab_tui.py") and len(cmd) == 2           # the full-screen app takes no model argument
