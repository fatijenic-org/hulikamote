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
    with pytest.raises(ViewerError, match="already in that vehicle"):
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


def tint(ds: Path, analysis: str, car: str, names: list, rgb: tuple):
    """Photos of one solid colour: the 'most alike' suggestions compare colour layouts."""
    for n in names:
        path = ds / "reid" / "images" / analysis / car / n
        path.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (40, 80), rgb).save(path, "JPEG")


def write_report(root: Path, analysis: str, tickets: dict):
    out = root / analysis / "output"
    out.mkdir(parents=True, exist_ok=True)
    (out / "report.json").write_text(json.dumps([{"ticket_uid": uid, "evidence_meta": [{"vclass": c} for c in classes]}
                                                 for uid, classes in tickets.items()]))


def test_every_vehicle_has_a_class_that_starts_as_the_tickets_and_you_can_set(mgr, tmp_path):
    write_report(tmp_path / "forensic", A, {"car1": ["motorcycle", "motorcycle", "unknown"], "car2": ["truck"]})
    mgr._forensic_root = tmp_path / "forensic"
    by_key = {c["key"]: c for c in mgr.cars()["cars"]}
    assert (by_key[f"{A}/{CAR1}"]["class"], by_key[f"{A}/{CAR1}"]["class_source"]) == ("motorcycle", "ticket")
    assert by_key[f"{A}/{CAR2}"]["class"] == "truck" and by_key[f"{A}/{TINY}"]["class"] is None
    assert [c["key"] for c in mgr.cars(cls="motorcycle")["cars"]] == [f"{A}/{CAR1}"]
    assert {c["key"] for c in mgr.cars(cls="unset")["cars"]} == {f"{A}/{TINY}", f"{B}/bbbbbbbb_car1"}
    assert mgr.summary()["classes"] == {"motorcycle": 1, "truck": 1, "unset": 2} and "tricycle" in mgr.summary()["class_list"]
    r = mgr.set_class([f"{A}/{CAR1}", f"{A}/{TINY}"], "tricycle")
    assert r["changed"] == 2
    assert mgr.car(f"{A}/{CAR1}")["class"] == "tricycle" and mgr.car(f"{A}/{CAR1}")["class_source"] == "you"
    assert mgr.car(f"{A}/{TINY}")["class"] == "tricycle"
    assert json.loads(mgr.classes_path.read_text()) == {f"{A}/{CAR1}": "tricycle", f"{A}/{TINY}": "tricycle"}
    again = ReidManager(mgr.datasets, tmp_path / "cache", training_check=lambda: False, forensic_root=tmp_path / "forensic")
    assert again.car(f"{A}/{CAR1}")["class"] == "tricycle"                                 # kept across a restart
    mgr.undo()
    assert mgr.car(f"{A}/{CAR1}")["class"] == "motorcycle" and mgr.car(f"{A}/{CAR1}")["class_source"] == "ticket"
    assert mgr.car(f"{A}/{TINY}")["class"] is None
    mgr.set_class([f"{A}/{CAR2}"], "bus")
    mgr.set_class([f"{A}/{CAR2}"], "auto")                                                 # back to what the ticket said
    assert mgr.car(f"{A}/{CAR2}")["class"] == "truck"
    with pytest.raises(ViewerError, match="unknown class"):
        mgr.set_class([f"{A}/{CAR2}"], "spaceship")
    with pytest.raises(ViewerError):
        mgr.cars(cls="spaceship")
    with pytest.raises(NotFound):
        mgr.set_class([f"{A}/nobody"], "car")
    with pytest.raises(ViewerError):
        mgr.set_class([], "car")


def test_a_split_off_vehicle_keeps_the_class_and_a_class_survives_being_emptied_and_restored(mgr):
    mgr.set_class([f"{A}/{CAR1}"], "jeepney")
    new = mgr.move([{"car": f"{A}/{CAR1}", "name": "101.jpg"}])["to"]
    assert mgr.car(new)["class"] == "jeepney" and mgr.car(new)["class_source"] == "you"
    mgr.undo()
    assert not mgr._classes.get(new)
    mgr.set_class([f"{A}/{TINY}"], "truck")
    mgr.remove([{"car": f"{A}/{TINY}", "name": "300.jpg"}])                                # the vehicle is gone, so is its class
    assert f"{A}/{TINY}" not in mgr._classes
    mgr.undo()
    assert mgr.car(f"{A}/{TINY}")["class"] == "truck"                                      # it comes back with the vehicle
    mgr.merge([f"{A}/{TINY}"], f"{A}/{CAR2}")
    assert f"{A}/{TINY}" not in mgr._classes
    mgr.undo()
    assert mgr.car(f"{A}/{TINY}")["class"] == "truck"


def test_photos_set_aside_are_not_trained_on_until_kept_or_merged(mgr):
    r = mgr.move([{"car": f"{A}/{CAR1}", "name": "101.jpg"}, {"car": f"{A}/{CAR1}", "name": "102.jpg"}], temporary=True)
    tmp_key = r["to"]
    assert r["temporary"] is True and r["created"] is True and tmp_key == f"{A}/aaaaaaaa_manual1"
    assert (mgr.temp / A / "aaaaaaaa_manual1" / "101.jpg").is_file() and not (mgr.images / A / "aaaaaaaa_manual1").exists()
    assert names(mgr, f"{A}/{CAR1}") == ["100.jpg"]
    s = mgr.summary()
    assert (s["temporary"], s["temporary_photos"], s["cars"], s["photos"]) == (1, 2, 4, 6)    # the trained-on counts do not include it
    by_key = {c["key"]: c for c in mgr.cars()["cars"]}
    assert by_key[tmp_key]["temporary"] is True and by_key[f"{A}/{CAR1}"]["temporary"] is False
    assert [c["key"] for c in mgr.cars(flt="temporary")["cars"]] == [tmp_key]
    assert tmp_key not in {c["key"] for c in mgr.cars(flt="used")["cars"]}
    assert {a["id"]: a["temporary"] for a in mgr.cars()["analyses"]}[A] == 1
    detail = mgr.car(tmp_key)
    assert detail["temporary"] is True and detail["photos"] == ["101.jpg", "102.jpg"]
    assert mgr.photo_file(tmp_key, "101.jpg").is_file()
    # more photos can join it, from another vehicle
    mgr.move([{"car": f"{A}/{CAR2}", "name": "200.jpg"}], to=tmp_key)
    assert sorted(p.name for p in (mgr.temp / A / "aaaaaaaa_manual1").iterdir()) == ["101.jpg", "102.jpg", "200.jpg"]
    # a new permanent vehicle never reuses the name of a set-aside one
    assert mgr.move([{"car": f"{A}/{CAR2}", "name": "201.jpg"}])["to"] == f"{A}/aaaaaaaa_manual2"
    mgr.undo()
    # keep it as a vehicle of its own: now it is trained on
    assert mgr.keep([tmp_key])["vehicles"] == 1
    assert names(mgr, tmp_key) == ["101.jpg", "102.jpg", "200.jpg"] and mgr.car(tmp_key)["temporary"] is False
    assert not mgr.temp.exists() or not any(mgr.temp.rglob("*.jpg"))
    mgr.undo()
    assert mgr.car(tmp_key)["temporary"] is True
    # or merge it into a vehicle you know
    r = mgr.merge([tmp_key], f"{A}/{CAR1}")
    assert r["moved"] == 3 and names(mgr, f"{A}/{CAR1}") == ["100.jpg", "101.jpg", "102.jpg", "200.jpg"]
    assert not (mgr.temp / A / "aaaaaaaa_manual1").exists()
    mgr.undo()
    assert mgr.car(tmp_key)["temporary"] is True and names(mgr, f"{A}/{CAR1}") == ["100.jpg"]


def test_whole_vehicles_can_be_set_aside_and_kept_several_at_once(mgr):
    r = mgr.hold([f"{A}/{CAR2}", f"{A}/{TINY}"])
    assert r["vehicles"] == 2 and r["moved"] == 3
    assert names(mgr, f"{A}/{CAR2}") is None and (mgr.temp / A / CAR2 / "200.jpg").is_file()
    assert mgr.car(f"{A}/{CAR2}")["temporary"] is True                                      # the same key, found in the temporary area
    assert mgr.summary()["temporary"] == 2 and mgr.summary()["cars"] == 2
    with pytest.raises(ViewerError, match="not a trained-on vehicle"):
        mgr.hold([f"{A}/{CAR2}"])
    with pytest.raises(ViewerError, match="not set aside"):
        mgr.keep([f"{A}/{CAR1}"])
    mgr.set_class([f"{A}/{CAR2}"], "bus")
    assert mgr.keep([f"{A}/{CAR2}", f"{A}/{TINY}"])["vehicles"] == 2
    assert names(mgr, f"{A}/{CAR2}") == ["200.jpg", "201.jpg"] and mgr.car(f"{A}/{CAR2}")["class"] == "bus"    # the class went along
    mgr.undo()                                                                              # undo the keep ...
    assert mgr.car(f"{A}/{CAR2}")["temporary"] is True
    mgr.undo()                                                                              # ... the class ...
    mgr.undo()                                                                              # ... and the hold
    assert mgr.summary()["temporary"] == 0 and names(mgr, f"{A}/{CAR2}") == ["200.jpg", "201.jpg"]
    with pytest.raises(ViewerError):
        mgr.hold([])
    with pytest.raises(ViewerError, match="not a trained-on vehicle"):
        mgr.hold([f"{A}/nobody"])


def test_set_aside_photos_are_never_in_the_folder_the_trainer_reads(mgr):
    mgr.move([{"car": f"{A}/{CAR1}", "name": "101.jpg"}], temporary=True)
    trained_on = {p.relative_to(mgr.images).as_posix() for p in mgr.images.rglob("*.jpg")}
    assert f"{A}/aaaaaaaa_manual1/101.jpg" not in trained_on
    assert mgr.temp.is_dir() and mgr.temp.parent == mgr.root                                # a sibling of images/, which is all the trainer reads


def test_the_most_alike_vehicles_are_listed_first(mgr):
    X, Y, Z = "aaaaaaaa_x", "aaaaaaaa_y", "aaaaaaaa_z"
    tint(mgr.ds, A, X, ["1.jpg", "2.jpg"], (200, 30, 30))
    tint(mgr.ds, A, Y, ["1.jpg", "2.jpg"], (30, 200, 30))
    tint(mgr.ds, A, Z, ["1.jpg", "2.jpg", "3.jpg"], (205, 35, 28))
    tint(mgr.ds, B, "bbbbbbbb_x", ["1.jpg"], (200, 30, 30))                                  # another analysis: never offered
    ranked = mgr.similar(f"{A}/{X}")["vehicles"]
    keys = [v["key"] for v in ranked]
    assert keys[0] == f"{A}/{Z}" and keys.index(f"{A}/{Y}") > keys.index(f"{A}/{Z}") and f"{B}/bbbbbbbb_x" not in keys
    assert ranked[0]["alike"] > 0.9 and ranked[0]["photos"] == 3 and ranked[0]["temporary"] is False
    mgr.move([{"car": f"{A}/{Z}", "name": "1.jpg"}, {"car": f"{A}/{Z}", "name": "2.jpg"}], temporary=True)
    again = {v["key"]: v for v in mgr.similar(f"{A}/{Y}", ["1.jpg"])["vehicles"]}
    assert again[f"{A}/aaaaaaaa_manual1"]["temporary"] is True and f"{A}/{X}" in again       # set-aside vehicles are offered too
    with pytest.raises(NotFound):
        mgr.similar(f"{A}/{X}", ["999.jpg"])
    with pytest.raises(ViewerError):
        mgr.similar(f"{A}/{X}", [])
    with pytest.raises(NotFound):
        mgr.similar(f"{A}/nobody")


def test_a_bike_and_a_truck_are_never_suggested_as_one_vehicle(mgr):
    mgr.state["scan"] = SCAN
    wait_job(mgr, mgr.start_scan()["id"])
    assert mgr.summary()["scan"]["jumps"] == 1
    mgr.set_class([f"{A}/{CAR2}"], "truck")
    mgr.set_class([f"{A}/{TINY}"], "motorcycle")
    assert mgr.summary()["scan"]["jumps"] == 0 and mgr.cars(flt="jumps")["cars"] == []
    mgr.set_class([f"{A}/{TINY}"], "truck")
    assert mgr.summary()["scan"]["jumps"] == 1


def test_removed_photos_of_a_set_aside_vehicle_return_to_it(mgr):
    tmp_key = mgr.move([{"car": f"{A}/{CAR1}", "name": "101.jpg"}, {"car": f"{A}/{CAR1}", "name": "102.jpg"}], temporary=True)["to"]
    mgr.remove([{"car": tmp_key, "name": "101.jpg"}])
    item = mgr.removed()["items"][0]
    assert item["car"] == "aaaaaaaa_manual1"
    mgr.restore([item])
    assert sorted(p.name for p in (mgr.temp / A / "aaaaaaaa_manual1").iterdir()) == ["101.jpg", "102.jpg"]
    assert not (mgr.images / A / "aaaaaaaa_manual1").exists()


def test_the_new_writes_are_refused_while_the_matcher_trains(mgr):
    mgr.state["training"] = True
    for call in (lambda: mgr.hold([f"{A}/{CAR2}"]), lambda: mgr.keep([f"{A}/{CAR2}"]), lambda: mgr.set_class([f"{A}/{CAR2}"], "car"),
                 lambda: mgr.move([{"car": f"{A}/{CAR1}", "name": "100.jpg"}], temporary=True)):
        with pytest.raises(TrainingBusy):
            call()
    assert names(mgr, f"{A}/{CAR2}") == ["200.jpg", "201.jpg"] and not mgr._classes


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


def test_the_new_routes_classes_temporary_and_similar(server):
    mgr, base = server
    code, body, _ = call(base, "/api/reid/class", {"cars": [f"{A}/{CAR1}", f"{A}/{TINY}"], "class": "tricycle"})
    assert code == 200 and json.loads(body)["changed"] == 2
    assert call(base, "/api/reid/class", {"cars": [f"{A}/{CAR1}"], "class": "spaceship"})[0] == 400
    cars = json.loads(call(base, "/api/reid/cars?class=tricycle")[1])["cars"]
    assert {c["key"] for c in cars} == {f"{A}/{CAR1}", f"{A}/{TINY}"} and cars[0]["class"] == "tricycle"
    assert call(base, "/api/reid/cars?class=spaceship")[0] == 400
    code, body, _ = call(base, "/api/reid/move", {"photos": [{"car": f"{A}/{CAR1}", "name": "101.jpg"}], "to": None, "temporary": True})
    moved = json.loads(body)
    assert code == 200 and moved["temporary"] is True and moved["to"] == f"{A}/aaaaaaaa_manual1"
    temp = json.loads(call(base, "/api/reid/cars?filter=temporary")[1])["cars"]
    assert [c["key"] for c in temp] == [moved["to"]] and temp[0]["temporary"] is True
    code, body, h = call(base, f"/api/reid/photo?key={moved['to']}&name=101.jpg&thumb=1")
    assert code == 200 and body[:2] == b"\xff\xd8"
    code, body, _ = call(base, "/api/reid/similar", {"key": f"{A}/{CAR2}", "photos": ["200.jpg"]})
    ranked = json.loads(body)["vehicles"]
    assert code == 200 and {v["key"] for v in ranked} == {f"{A}/{CAR1}", f"{A}/{TINY}", moved["to"]}
    assert call(base, "/api/reid/similar", {"key": f"{A}/{CAR2}", "photos": []})[0] == 400
    assert call(base, "/api/reid/similar", {"key": f"{A}/nobody"})[0] == 404
    assert call(base, "/api/reid/keep", {"cars": [moved["to"]]})[0] == 200
    assert call(base, "/api/reid/hold", {"cars": [moved["to"]]})[0] == 200
    assert call(base, "/api/reid/hold", {"cars": [moved["to"]]})[0] == 400                 # already set aside
    rows = json.loads(call(base, "/api/datasets")[1])["datasets"]
    assert rows[-1]["temporary"] == 1
    mgr.state["training"] = True
    assert call(base, "/api/reid/hold", {"cars": [f"{A}/{CAR2}"]})[0] == 409
    assert call(base, "/api/reid/class", {"cars": [f"{A}/{CAR2}"], "class": "car"})[0] == 409


def fake_suggestion(classes: dict):
    def runner(out: Path, training: bool):
        out.write_text(json.dumps({"ts": time.time(), "weights": "train-3", "vehicles": 4,
                                   "classes": {k: {"class": c, "agree": 3, "of": 4} for k, c in classes.items()}}), encoding="utf-8")
        return "[Suggest] ok"
    return runner


def test_suggested_classes_fill_in_vehicles_without_one_and_never_override_yours_or_the_tickets(mgr, tmp_path):
    write_report(tmp_path / "forensic", A, {"car2": ["car"]})
    mgr._forensic_root = tmp_path / "forensic"
    mgr._suggest_runner = fake_suggestion({f"{A}/{CAR1}": "truck", f"{A}/{CAR2}": "bus", f"{A}/{TINY}": "tricycle", f"{A}/gone": "car"})
    assert mgr.summary()["suggest"] is None and mgr.summary()["classes"] == {"unset": 3, "car": 1}   # car 2 has its ticket class
    done = wait_job(mgr, mgr.start_suggest()["id"])
    assert done["state"] == "done" and done["kind"] == "suggest" and done["text"] == "[Suggest] ok"
    by_key = {c["key"]: c for c in mgr.cars()["cars"]}
    assert (by_key[f"{A}/{CAR1}"]["class"], by_key[f"{A}/{CAR1}"]["class_source"]) == ("truck", "model")
    assert (by_key[f"{A}/{CAR2}"]["class"], by_key[f"{A}/{CAR2}"]["class_source"]) == ("car", "ticket")   # the ticket beats the model
    assert by_key[f"{A}/{TINY}"]["class"] == "tricycle" and by_key[f"{B}/bbbbbbbb_car1"]["class"] is None
    s = mgr.summary()
    assert s["suggest"]["count"] == 4 and s["suggest"]["weights"] == "train-3"
    assert s["classes"] == {"truck": 1, "car": 1, "tricycle": 1, "unset": 1}
    assert [c["key"] for c in mgr.cars(cls="truck")["cars"]] == [f"{A}/{CAR1}"]
    mgr.set_class([f"{A}/{CAR1}"], "motorcycle")                                                 # what you set beats the model
    assert mgr.car(f"{A}/{CAR1}")["class"] == "motorcycle" and mgr.car(f"{A}/{CAR1}")["class_source"] == "you"
    mgr.set_class([f"{A}/{CAR1}"], "auto")                                                       # and "auto" gives the suggestion back
    assert mgr.car(f"{A}/{CAR1}")["class"] == "truck" and mgr.car(f"{A}/{CAR1}")["class_source"] == "model"


def test_a_guess_from_the_model_never_hides_a_suspect_but_a_class_you_set_does(mgr):
    mgr.state["scan"] = SCAN
    wait_job(mgr, mgr.start_scan()["id"])
    mgr._suggest_runner = fake_suggestion({f"{A}/{CAR2}": "truck", f"{A}/{TINY}": "bus"})
    wait_job(mgr, mgr.start_suggest()["id"])
    assert mgr.summary()["scan"]["jumps"] == 1                                                    # two different guesses: still shown to you
    mgr.set_class([f"{A}/{CAR2}"], "truck")
    mgr.set_class([f"{A}/{TINY}"], "bus")
    assert mgr.summary()["scan"]["jumps"] == 0                                                    # two classes YOU set: a bike is not a truck


def test_only_one_job_runs_at_a_time_and_a_failed_suggestion_says_why(mgr):
    release = threading.Event()

    def slow(out, training):
        release.wait(5)
        return fake_suggestion({})(out, training)

    mgr._suggest_runner = slow
    first = mgr.start_suggest()
    assert mgr.start_scan()["id"] == first["id"] and mgr.summary()["job"]["kind"] == "suggest"      # the scan waits for the suggestion
    release.set()
    assert wait_job(mgr, first["id"])["state"] == "done"

    def boom(out, training):
        raise RuntimeError("no vehicle model found")

    mgr._suggest_runner = boom
    failed = wait_job(mgr, mgr.start_suggest()["id"])
    assert failed["state"] == "error" and "no vehicle model found" in failed["text"]


def test_the_suggest_route(server):
    mgr, base = server
    mgr._suggest_runner = fake_suggestion({f"{A}/{CAR1}": "bus"})
    code, body, _ = call(base, "/api/reid/suggest", {})
    job = json.loads(body)
    assert code == 200 and job["kind"] == "suggest" and wait_job(mgr, job["id"])["state"] == "done"
    cars = json.loads(call(base, "/api/reid/cars?class=bus")[1])["cars"]
    assert [c["key"] for c in cars] == [f"{A}/{CAR1}"] and cars[0]["class_source"] == "model"
