"""The Car matcher (ReID) manager of the Dataset Viewer: move / merge / remove / restore / undo on datasets/reid, and the scan flags."""
import json
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data_tools import common, curate                                    # noqa: E402
from dataset_viewer.app import NotFound, TrainingBusy, ViewerApp, ViewerError   # noqa: E402
from dataset_viewer.reid import ReidManager                              # noqa: E402
from dataset_viewer.server import make_server                            # noqa: E402

A, B = "aaaaaaaa-1111", "bbbbbbbb-2222"
CAR1, CAR2, TINY = "aaaaaaaa_car1", "aaaaaaaa_car2", "aaaaaaaa_tiny"


def make(ds: Path, analysis: str, cars: dict):
    for car, names in cars.items():
        for i, name in enumerate(names):
            path = ds / "reid" / "images" / analysis / car / name
            path.parent.mkdir(parents=True, exist_ok=True)
            Image.new("RGB", (40, 80), (30 + 20 * i, 90, 150)).save(path, "JPEG")


@pytest.fixture()
def mgr(tmp_path):
    ds = tmp_path / "datasets"
    make(ds, A, {CAR1: ["100.jpg", "101.jpg", "102.jpg"], CAR2: ["200.jpg", "201.jpg"], TINY: ["300.jpg"]})
    make(ds, B, {"bbbbbbbb_car1": ["100.jpg", "101.jpg"]})
    state = {"training": False, "scan": None, "fail": None}

    def runner(out: Path, training: bool):
        if state["fail"]:
            raise RuntimeError(state["fail"])
        out.write_text(json.dumps(state["scan"]), encoding="utf-8")
        return "[Scan] ok"

    m = ReidManager(ds, tmp_path / "cache", training_check=lambda: state["training"], scan_runner=runner)
    m.state, m.ds = state, ds
    return m


def names(m, key):
    return sorted(p.name for p in (m.images / key).iterdir()) if (m.images / key).is_dir() else None


def decisions(m):
    return [json.loads(x) for x in m.decisions.read_text().splitlines()] if m.decisions.exists() else []


def wait_job(m, job_id):
    for _ in range(200):
        job = m.job(job_id)
        if job["state"] != "running":
            return job
        time.sleep(0.02)
    raise AssertionError("the scan did not finish")


def test_summary_counts_cars_photos_and_the_ones_too_small_to_train_on(mgr):
    s = mgr.summary()
    assert (s["analyses"], s["cars"], s["photos"], s["small"]) == (2, 4, 8, 1)
    assert s["scan"] is None and s["can_undo"] is False and s["removed"] == 0 and s["training"] is False


def test_the_car_list_filters_by_analysis_text_and_size(mgr):
    assert [c["key"] for c in mgr.cars()["cars"]] == [f"{A}/{CAR1}", f"{A}/{CAR2}", f"{A}/{TINY}", f"{B}/bbbbbbbb_car1"]
    assert [c["key"] for c in mgr.cars(analysis=B)["cars"]] == [f"{B}/bbbbbbbb_car1"]
    assert [c["key"] for c in mgr.cars(q="car2")["cars"]] == [f"{A}/{CAR2}"]
    small = mgr.cars(flt="small")["cars"]
    assert [c["key"] for c in small] == [f"{A}/{TINY}"] and small[0]["small"] is True
    assert {a["id"]: (a["cars"], a["photos"]) for a in mgr.cars()["analyses"]} == {A: (3, 6), B: (1, 2)}
    with pytest.raises(ViewerError):
        mgr.cars(flt="nonsense")


def test_moving_a_photo_to_another_car_of_the_analysis_is_logged_and_can_be_undone(mgr):
    r = mgr.move([{"car": f"{A}/{TINY}", "name": "300.jpg"}], f"{A}/{CAR1}")
    assert r["moved"] == 1 and r["to"] == f"{A}/{CAR1}" and r["can_undo"] is True
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg", "300.jpg"]
    assert names(mgr, f"{A}/{TINY}") is None                                   # a folder with nothing in it is not a car
    d = decisions(mgr)[-1]
    assert d["kind"] == "moved" and d["source"] == "manager" and d["task_id"] == A
    assert d["identities"] == {CAR1: [f"images/{A}/{CAR1}/300.jpg"]}           # paths relative to datasets/reid, labels = folder names
    assert mgr.undo()["undid"] == "move"
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg"] and names(mgr, f"{A}/{TINY}") == ["300.jpg"]
    with pytest.raises(ViewerError):
        mgr.undo()


def test_photos_can_start_a_new_car(mgr):
    r = mgr.move([{"car": f"{A}/{CAR1}", "name": "101.jpg"}, {"car": f"{A}/{CAR1}", "name": "102.jpg"}])
    assert r["created"] is True and r["to"] == f"{A}/aaaaaaaa_manual1"
    assert names(mgr, r["to"]) == ["101.jpg", "102.jpg"] and names(mgr, f"{A}/{CAR1}") == ["100.jpg"]
    assert mgr.move([{"car": f"{A}/{CAR2}", "name": "200.jpg"}])["to"] == f"{A}/aaaaaaaa_manual2"
    mgr.undo()
    mgr.undo()
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg"] and names(mgr, f"{A}/aaaaaaaa_manual1") is None


def test_a_move_that_cannot_be_made_changes_nothing(mgr):
    with pytest.raises(ViewerError, match="same analysis"):
        mgr.move([{"car": f"{A}/{CAR1}", "name": "100.jpg"}], f"{B}/bbbbbbbb_car1")
    with pytest.raises(ViewerError, match="inside one analysis"):
        mgr.move([{"car": f"{A}/{CAR1}", "name": "100.jpg"}, {"car": f"{B}/bbbbbbbb_car1", "name": "100.jpg"}], f"{A}/{CAR2}")
    with pytest.raises(NotFound):
        mgr.move([{"car": f"{A}/{CAR1}", "name": "100.jpg"}], f"{A}/nobody")
    with pytest.raises(ViewerError, match="already in that car"):
        mgr.move([{"car": f"{A}/{CAR1}", "name": "100.jpg"}], f"{A}/{CAR1}")
    make(mgr.ds, A, {CAR2: ["100.jpg"]})                                       # a photo with the same name is already in the car
    with pytest.raises(ViewerError, match="already in"):
        mgr.move([{"car": f"{A}/{CAR2}", "name": "200.jpg"}, {"car": f"{A}/{CAR2}", "name": "100.jpg"}], f"{A}/{CAR1}")
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg"]
    assert names(mgr, f"{A}/{CAR2}") == ["100.jpg", "200.jpg", "201.jpg"]      # the first photo that did move was taken back
    assert not mgr.summary()["can_undo"]


def test_merging_cars_empties_their_folders_and_undo_brings_them_back(mgr):
    r = mgr.merge([f"{A}/{CAR2}", f"{A}/{TINY}"], f"{A}/{CAR1}")
    assert r["moved"] == 3 and names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg", "200.jpg", "201.jpg", "300.jpg"]
    assert names(mgr, f"{A}/{CAR2}") is None and names(mgr, f"{A}/{TINY}") is None
    d = decisions(mgr)[-1]
    assert d["kind"] == "merge" and list(d["identities"]) == [CAR1] and len(d["identities"][CAR1]) == 6
    mgr.undo()
    assert names(mgr, f"{A}/{CAR2}") == ["200.jpg", "201.jpg"] and names(mgr, f"{A}/{TINY}") == ["300.jpg"]
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg"]
    with pytest.raises(ViewerError, match="inside one analysis"):
        mgr.merge([f"{B}/bbbbbbbb_car1"], f"{A}/{CAR1}")
    with pytest.raises(ViewerError, match="nothing to merge"):
        mgr.merge([f"{A}/{CAR1}"], f"{A}/{CAR1}")


def test_removed_photos_go_to_quarantine_and_come_back(mgr):
    photos = [{"car": f"{A}/{CAR1}", "name": "100.jpg"}, {"car": f"{A}/{CAR1}", "name": "101.jpg"}]
    assert mgr.remove(photos, "not_a_car")["moved"] == 2
    assert names(mgr, f"{A}/{CAR1}") == ["102.jpg"]
    assert (mgr.datasets / "_quarantine" / "reid" / "not_a_car" / A / CAR1 / "100.jpg").is_file()
    items = mgr.removed()["items"]
    assert len(items) == 2 and items[0] == {"reason": "not_a_car", "analysis": A, "car": CAR1, "name": "100.jpg"}
    assert mgr.summary()["removed"] == 2
    assert mgr.removed_file("not_a_car", A, CAR1, "100.jpg").is_file()
    mgr.restore([items[0]])
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "102.jpg"] and len(mgr.removed()["items"]) == 1
    mgr.undo()                                                                 # undo the restore: it is in quarantine again
    assert len(mgr.removed()["items"]) == 2
    mgr.undo()                                                                 # undo the remove
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg"] and mgr.removed()["items"] == []


def test_a_whole_car_can_be_removed_and_its_folder_returns_on_undo(mgr):
    assert mgr.remove_cars([f"{A}/{CAR2}", f"{A}/{TINY}"])["moved"] == 3
    assert names(mgr, f"{A}/{CAR2}") is None and names(mgr, f"{A}/{TINY}") is None
    mgr.undo()
    assert names(mgr, f"{A}/{CAR2}") == ["200.jpg", "201.jpg"] and names(mgr, f"{A}/{TINY}") == ["300.jpg"]
    with pytest.raises(NotFound):
        mgr.remove_cars([f"{A}/nobody"])


def test_undo_goes_back_in_order_and_survives_a_restart(mgr, tmp_path):
    mgr.move([{"car": f"{A}/{TINY}", "name": "300.jpg"}], f"{A}/{CAR2}")
    mgr.remove([{"car": f"{A}/{CAR1}", "name": "100.jpg"}])
    again = ReidManager(mgr.datasets, tmp_path / "cache", training_check=lambda: False)
    assert again.summary()["can_undo"] is True
    assert again.undo()["undid"] == "remove"
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg"]
    assert again.undo()["undid"] == "move"
    assert names(mgr, f"{A}/{TINY}") == ["300.jpg"]
    last = ReidManager(mgr.datasets, tmp_path / "cache", training_check=lambda: False)
    assert last.summary()["can_undo"] is False                                  # what was undone stays undone


def test_names_from_the_page_cannot_reach_outside_the_car_folders(mgr):
    for bad in ("../x.jpg", "a/b.jpg", "..", "x.txt", "", ".hidden.jpg"):
        with pytest.raises(ViewerError):
            mgr.move([{"car": f"{A}/{CAR1}", "name": bad}], f"{A}/{CAR2}")
    for bad_key in (f"{A}/{CAR1}/extra", "nocar", f"../{CAR1}", f"{A}/.."):
        with pytest.raises(ViewerError):
            mgr.car(bad_key)
    with pytest.raises(ViewerError):
        mgr.remove([{"car": f"{A}/{CAR1}", "name": "100.jpg"}], "../escape")
    with pytest.raises(ViewerError):
        mgr.restore([{"reason": "ok", "analysis": "..", "car": CAR1, "name": "100.jpg"}])
    with pytest.raises(ViewerError):
        mgr.photo_file(f"{A}/{CAR1}", "../../x.jpg")
    with pytest.raises(NotFound):
        mgr.photo_file(f"{A}/{CAR1}", "999.jpg")
    assert mgr.photo_file(f"{A}/{CAR1}", "100.jpg").is_file()


def test_nothing_is_written_while_the_matcher_trains(mgr):
    mgr.state["training"] = True
    for call in (lambda: mgr.move([{"car": f"{A}/{CAR1}", "name": "100.jpg"}]),
                 lambda: mgr.merge([f"{A}/{CAR2}"], f"{A}/{CAR1}"),
                 lambda: mgr.remove([{"car": f"{A}/{CAR1}", "name": "100.jpg"}]),
                 lambda: mgr.restore([{"reason": "x", "analysis": A, "car": CAR1, "name": "1.jpg"}]),
                 lambda: mgr.undo()):
        with pytest.raises(TrainingBusy):
            call()
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg"] and mgr.summary()["training"] is True
    mgr.is_training = lambda: (_ for _ in ()).throw(OSError("cannot list processes"))
    with pytest.raises(TrainingBusy, match="Could not check"):
        mgr.move([{"car": f"{A}/{CAR1}", "name": "100.jpg"}])


SCAN = {"ts": time.time() - 60, "cars": 4, "photos": 8, "used": 3, "photos_used": 6,
        "repeats": [{"dropped": f"{B}/bbbbbbbb_car1", "kept": f"{A}/{CAR1}"}],
        "jumps": [{"a": f"{A}/{CAR2}", "b": f"{A}/{TINY}", "alike": 0.97}], "mixed": [{"car": f"{A}/{CAR1}", "share": 0.4}]}


def test_the_scan_marks_repeats_jumps_and_mixed_cars(mgr):
    mgr.state["scan"] = SCAN
    job = mgr.start_scan()
    assert job["state"] == "running"
    done = wait_job(mgr, job["id"])
    assert done["state"] == "done" and done["text"] == "[Scan] ok"
    s = mgr.summary()["scan"]
    assert (s["used"], s["repeats"], s["jumps"], s["mixed"], s["stale"]) == (3, 1, 1, 1, False)
    by_key = {c["key"]: c for c in mgr.cars()["cars"]}
    assert by_key[f"{A}/{CAR2}"]["jump"] == [{"key": f"{A}/{TINY}", "alike": 0.97}]
    assert by_key[f"{A}/{TINY}"]["jump"][0]["key"] == f"{A}/{CAR2}"
    assert by_key[f"{A}/{CAR1}"]["mixed"] == 0.4 and by_key[f"{A}/{CAR1}"]["repeats"] == [f"{B}/bbbbbbbb_car1"]
    assert by_key[f"{B}/bbbbbbbb_car1"]["repeat_of"] == f"{A}/{CAR1}"
    assert {c["key"] for c in mgr.cars(flt="jumps")["cars"]} == {f"{A}/{CAR2}", f"{A}/{TINY}"}
    assert {c["key"] for c in mgr.cars(flt="flagged")["cars"]} == {f"{A}/{CAR2}", f"{A}/{TINY}", f"{A}/{CAR1}"}
    assert [c["key"] for c in mgr.cars(flt="repeats")["cars"]] == [f"{B}/bbbbbbbb_car1"]
    assert {c["key"] for c in mgr.cars(flt="used")["cars"]} == {f"{A}/{CAR1}", f"{A}/{CAR2}"}    # not the repeat, not the one-photo car
    assert {a["id"]: a["flagged"] for a in mgr.cars()["analyses"]} == {A: 3, B: 0}
    detail = mgr.car(f"{A}/{CAR2}")
    assert detail["photos"] == ["200.jpg", "201.jpg"] and detail["jump"][0]["key"] == f"{A}/{TINY}"
    assert [s["key"] for s in detail["siblings"]] == [f"{A}/{TINY}", f"{A}/{CAR1}"] and detail["siblings"][0]["alike"] == 0.97


def test_a_dismissed_suspect_goes_away_and_the_questions_do_not_return(mgr):
    mgr.state["scan"] = SCAN
    wait_job(mgr, mgr.start_scan()["id"])
    mgr.dismiss(f"{A}/{TINY}", f"{A}/{CAR2}")
    assert mgr.summary()["scan"]["jumps"] == 0 and mgr.cars(flt="jumps")["cars"] == []
    d = decisions(mgr)[-1]
    assert d["kind"] == "not_same" and d["source"] == "manager" and sorted(d["identities"]) == sorted([TINY, CAR2])
    assert mgr.dismiss(f"{A}/{CAR2}", f"{A}/{TINY}")["ok"]                      # again: nothing new
    assert len([x for x in decisions(mgr) if x["kind"] == "not_same"]) == 1
    assert mgr.undo()["undid"] == "dismiss"
    assert mgr.summary()["scan"]["jumps"] == 1


def test_scan_flags_go_stale_after_an_edit_and_ignore_folders_that_are_gone(mgr):
    mgr.state["scan"] = {**SCAN, "ts": time.time() - 1}
    wait_job(mgr, mgr.start_scan()["id"])
    mgr.merge([f"{A}/{TINY}"], f"{A}/{CAR2}")                                     # the suspect pair is now one car
    s = mgr.summary()["scan"]
    assert s["stale"] is True and s["edits"] == 1 and s["jumps"] == 0
    assert mgr.car(f"{A}/{CAR2}")["jump"] == []


def test_a_failed_scan_says_why_and_a_second_scan_waits_for_the_first(mgr):
    mgr.state["fail"] = "no checkpoint"
    done = wait_job(mgr, mgr.start_scan()["id"])
    assert done["state"] == "error" and "no checkpoint" in done["text"] and mgr.summary()["job"] is None
    release = threading.Event()
    original = mgr._scan_runner

    def slow(out, training):
        release.wait(5)
        mgr.state["fail"] = None
        mgr.state["scan"] = SCAN
        return original(out, training)

    mgr._scan_runner = slow
    first = mgr.start_scan()
    assert mgr.start_scan()["id"] == first["id"] and mgr.summary()["job"]["id"] == first["id"]
    release.set()
    assert wait_job(mgr, first["id"])["state"] == "done"
    with pytest.raises(NotFound):
        mgr.job("nope")


def test_the_manager_entry_for_the_datasets_list(mgr):
    e = mgr.entry()
    assert e["name"] == "reid" and e["kind"] == "reid" and e["total"] == 8 and e["cars"] == 4 and e["index"]["state"] == "ready"


# --------------------------------------------------------------------------- HTTP

@pytest.fixture()
def server(mgr, tmp_path, monkeypatch):
    ds = mgr.datasets
    monkeypatch.setattr(common, "DATASETS", ds)
    monkeypatch.setattr(common, "QUARANTINE", ds / "_quarantine")
    monkeypatch.setattr(curate, "DATASETS", ds)
    viewer = ViewerApp(ds, tmp_path / "cache", tmp_path / "m.yaml", training_check=lambda m: False)
    viewer._reid = mgr
    mgr._thumb = viewer.thumb                                                   # the real thumbnail path
    srv = make_server(viewer, 0, token="tok123")
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield mgr, f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()
    srv.server_close()


def call(base, path, body=None, token="tok123"):
    url = base + path + (("&" if "?" in path else "?") + f"t={token}" if token else "")
    req = urllib.request.Request(url, data=None if body is None else json.dumps(body).encode(), method="GET" if body is None else "POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read(), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers


def test_the_routes_need_the_token_and_do_the_work(server):
    mgr, base = server
    assert call(base, "/api/reid/summary", token="")[0] == 403
    code, body, _ = call(base, "/api/datasets")
    rows = json.loads(body)["datasets"]
    assert code == 200 and rows[-1]["name"] == "reid" and rows[-1]["kind"] == "reid"
    assert json.loads(call(base, "/api/reid/summary")[1])["cars"] == 4
    cars = json.loads(call(base, "/api/reid/cars?filter=small")[1])["cars"]
    assert [c["key"] for c in cars] == [f"{A}/{TINY}"]
    assert json.loads(call(base, f"/api/reid/car?key={A}/{CAR1}")[1])["photos"] == ["100.jpg", "101.jpg", "102.jpg"]
    code, body, h = call(base, f"/api/reid/photo?key={A}/{CAR1}&name=100.jpg&thumb=1")
    assert code == 200 and h["Content-Type"] == "image/jpeg" and body[:2] == b"\xff\xd8"
    assert call(base, f"/api/reid/photo?key={A}/{CAR1}&name=..%2Fx.jpg")[0] == 400
    assert call(base, f"/api/reid/photo?key={A}/{CAR1}&name=999.jpg")[0] == 404
    code, body, _ = call(base, "/api/reid/move", {"photos": [{"car": f"{A}/{TINY}", "name": "300.jpg"}], "to": f"{A}/{CAR2}"})
    assert code == 200 and json.loads(body)["moved"] == 1
    assert call(base, "/api/reid/move", {"photos": [], "to": f"{A}/{CAR2}"})[0] == 400
    code, body, _ = call(base, "/api/reid/merge", {"cars": [f"{A}/{CAR2}"], "into": f"{A}/{CAR1}"})
    assert code == 200 and json.loads(body)["moved"] == 3
    assert call(base, "/api/reid/remove", {"photos": [{"car": f"{A}/{CAR1}", "name": "100.jpg"}], "reason": "bad_photo"})[0] == 200
    removed = json.loads(call(base, "/api/reid/removed")[1])["items"]
    assert len(removed) == 1
    code, body, h = call(base, "/api/reid/removed_photo?reason=bad_photo&analysis=%s&car=%s&name=100.jpg&thumb=1" % (A, CAR1))
    assert code == 200 and body[:2] == b"\xff\xd8"
    assert call(base, "/api/reid/restore", {"items": removed})[0] == 200
    assert call(base, "/api/reid/undo", {})[0] == 200
    assert call(base, "/api/reid/dismiss", {"a": f"{A}/{CAR1}", "b": f"{A}/{CAR2}"})[0] == 200
    mgr.state["scan"] = SCAN
    code, body, _ = call(base, "/api/reid/scan", {})
    job = json.loads(body)
    assert code == 200 and wait_job(mgr, job["id"])["state"] == "done"
    assert json.loads(call(base, f"/api/reid/job?id={job['id']}")[1])["state"] == "done"
    assert call(base, "/api/reid/nothing")[0] == 404 and call(base, "/api/reid/nothing", {})[0] == 404


def test_the_routes_refuse_writes_while_training(server):
    mgr, base = server
    mgr.state["training"] = True
    code, body, _ = call(base, "/api/reid/move", {"photos": [{"car": f"{A}/{TINY}", "name": "300.jpg"}], "to": f"{A}/{CAR2}"})
    assert code == 409 and json.loads(body)["training"] is True
    assert names(mgr, f"{A}/{TINY}") == ["300.jpg"]
