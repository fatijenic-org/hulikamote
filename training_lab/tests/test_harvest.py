"""
Harvest tool tests. Everything runs in a temporary folder: no real datasets, evidence,
database or models are read or written, so these are safe to run during a training.

    hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests -q -p no:cacheprovider
"""
import json
import sqlite3
import sys
import threading
import urllib.error
import urllib.request
from pathlib import Path

import cv2
import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from harvest_tool import accept as accept_mod            # noqa: E402
from harvest_tool import collect as collect_mod          # noqa: E402
from harvest_tool.config import Paths                    # noqa: E402
from harvest_tool.cut_plates import cut_one, cut_plates, read_plate_boxes  # noqa: E402
from harvest_tool.detect import Det, Detector, nms       # noqa: E402
from harvest_tool.sources import read_statuses, review_counts, set_protected, tickets  # noqa: E402
from harvest_tool.store import Item, Store, clean_boxes  # noqa: E402
from harvest_tool.web import HarvestApp, make_server     # noqa: E402


# ─── a fake lab + backend on disk ────────────────────────────────────────────

def write_img(path: Path, w: int, h: int, seed: int = 0) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(seed)
    cv2.imwrite(str(path), rng.integers(0, 255, (h, w, 3), dtype=np.uint8))


def make_env(tmp_path: Path) -> Paths:
    lab, backend = tmp_path / "lab", tmp_path / "backend"
    paths = Paths(lab=lab, backend=backend)
    # datasets (plate uses train/images, helmet uses images/train - both layouts exist in the project)
    plate = lab / "datasets" / "plate_specialist"
    plate.mkdir(parents=True)
    (plate / "data.yaml").write_text("train: train/images\nval: valid/images\ntest: test/images\n"
                                     "names:\n  0: license_plate\n")
    helmet = lab / "datasets" / "helmet_specialist"
    helmet.mkdir(parents=True)
    (helmet / "data.yaml").write_text("path: datasets/helmet_specialist\ntrain: images/train\nval: images/val\n"
                                      "nc: 2\nnames:\n  0: rider_with_helmet\n  1: rider_without_helmet\n")
    # tickets database
    backend.mkdir(parents=True)
    con = sqlite3.connect(backend / "hulikamote.db")
    con.execute("CREATE TABLE violations (id TEXT, cls TEXT, status TEXT, source TEXT)")
    con.executemany("INSERT INTO violations VALUES (?,?,?,?)", [
        ("v1", "no_plate", "pending", "forensic"),
        ("v2", "counterflow", "approved", "forensic"),
        ("v3", "no_plate", "approved", "forensic"),
        ("v4", "no_helmet", "rejected", "forensic"),
        ("v5", "counterflow", "pending", "forensic"),
    ])
    con.commit()
    con.close()
    # one analysis with five tickets
    ev = paths.evidence
    report = [
        ticket("tA", 1, ["no_plate"], "unidentified", ["v1"], [("a1", 200, 160), ("a2", 200, 160), ("a3", 200, 160)]),
        ticket("tB", 2, ["counterflow"], "AB1234", ["v2"], [("b1", 220, 170)], plate_crops=["p.jpg"]),
        ticket("tC", 3, ["no_plate"], "unidentified", ["v3"], [("c1", 180, 150)]),
        ticket("tD", 4, ["no_helmet"], "unidentified", ["v4"], [("d1", 150, 190)]),
        ticket("tE", 5, ["counterflow"], "unidentified", ["v5"], [("e1", 40, 30)]),     # too small to use
    ]
    for t in report:
        for m in t["evidence_meta"]:
            w, h = m["clean_box"][2:]
            write_img(ev / m["clean"], w, h, seed=hash(m["clean"]) % 1000)
    out = paths.forensic / "task1" / "output"
    out.mkdir(parents=True)
    (out / "report.json").write_text(json.dumps(report))
    return paths


def ticket(uid, track, violations, plate, db_ids, frames, plate_crops=()):
    return {"ticket_uid": uid, "track_id": track, "violations": violations, "plate_text": plate, "db_ids": db_ids,
            "plate_crop_paths": list(plate_crops),
            "evidence_meta": [{"file": f"{n}.jpg", "bbox": [5, 5, w - 10, h - 10], "t": i * 0.5,
                               "car_crop": f"{n}_car.jpg", "clean": f"{n}.jpg", "clean_box": [0, 0, w, h],
                               "vclass": "car"} for i, (n, w, h) in enumerate(frames)]}


class StubDet:
    """Stands in for a Detector: `fn(image) -> list[Det]`."""

    def __init__(self, fn):
        self.fn, self.calls = fn, 0

    def detect(self, image, conf=0.25, **kw):
        self.calls += 1
        return self.fn(image)


class StubDetectors:
    def __init__(self, mapping):
        self.mapping = mapping

    def get(self, model):
        return self.mapping.get(model)


def plate_box_if_wide(image):
    """A plate is 'found' only on 200-px-wide pictures (ticket A)."""
    return [Det(0, 0.9, 60, 100, 120, 125)] if image.shape[1] == 200 else []


def tree(root: Path) -> set:
    return {str(p.relative_to(root)) for p in root.rglob("*")} if root.exists() else set()


# ─── detect ──────────────────────────────────────────────────────────────────

class FakeSession:
    """Returns a fixed raw output; records the blob it was given."""

    def __init__(self, output, size=320):
        self.output, self.size, self.blob = output, size, None

    def get_inputs(self):
        return [type("I", (), {"name": "images", "shape": [1, 3, self.size, self.size]})()]

    def run(self, _, feed):
        self.blob = feed["images"]
        return [self.output]


def raw_output(anchors, n=2100, nc=1):
    out = np.zeros((1, 4 + nc, n), dtype=np.float32)
    for i, (cx, cy, w, h, cls, score) in enumerate(anchors):
        out[0, 0:4, i] = (cx, cy, w, h)
        out[0, 4 + cls, i] = score
    return out


def test_letterbox_decode_recovers_original_pixels():
    # 200x100 picture, plate-ish box at x 50..90, y 20..60 in the ORIGINAL picture.
    # letterbox: scale 1.6, vertical padding 80 -> input box x 80..144, y 112..176
    session = FakeSession(raw_output([(112, 144, 64, 64, 0, 0.9)]))
    det = Detector(session, 320).detect(np.zeros((100, 200, 3), np.uint8), conf=0.5)
    assert len(det) == 1
    d = det[0]
    assert (round(d.x1), round(d.y1), round(d.x2), round(d.y2)) == (50, 20, 90, 60)
    assert d.yolo(200, 100) == pytest.approx([0, 0.35, 0.4, 0.2, 0.4], abs=1e-3)


def test_input_is_rgb_not_bgr():
    img = np.zeros((320, 320, 3), np.uint8)
    img[:, :] = (255, 0, 0)                     # pure BLUE in OpenCV's BGR order
    session = FakeSession(raw_output([]))
    Detector(session, 320).detect(img)
    blob = session.blob                          # (1, 3, H, W) in RGB order -> blue lands in channel 2
    assert blob[0, 2].mean() == pytest.approx(1.0) and blob[0, 0].mean() == pytest.approx(0.0)
    Detector(session, 320).detect(img, rgb=False)
    assert session.blob[0, 0].mean() == pytest.approx(1.0)           # the app's current (BGR) feeding


def test_stretch_mode_and_nms_and_end2end_format():
    session = FakeSession(raw_output([(160, 160, 100, 100, 0, 0.9), (162, 160, 100, 100, 0, 0.6)]))
    dets = Detector(session, 320).detect(np.zeros((320, 320, 3), np.uint8), conf=0.3, letterbox=False)
    assert len(dets) == 1 and dets[0].conf == pytest.approx(0.9, abs=1e-5)       # overlapping duplicate removed

    end2end = np.zeros((1, 300, 6), np.float32)
    end2end[0, 0] = (50, 50, 150, 150, 0.8, 1)
    dets = Detector(FakeSession(end2end), 320).detect(np.zeros((320, 320, 3), np.uint8), conf=0.3)
    assert len(dets) == 1 and dets[0].cls == 1 and round(dets[0].x2) == 150

    boxes = np.array([[0, 0, 10, 10], [1, 1, 11, 11], [50, 50, 60, 60]], float)
    assert nms(boxes, np.array([0.5, 0.9, 0.7]), 0.5) == [1, 2]


# ─── sources ─────────────────────────────────────────────────────────────────

def test_statuses_tickets_and_review_counts(tmp_path):
    paths = make_env(tmp_path)
    assert read_statuses(paths.db, ["v1", "v2", "nope"]) == {"v1": ("no_plate", "pending"),
                                                            "v2": ("counterflow", "approved")}
    ts = {t.uid: t for t in tickets(paths, "task1")}
    assert ts["tA"].status_by_violation == {"no_plate": "pending"} and not ts["tA"].plate_found
    assert ts["tB"].plate_found and ts["tB"].status_by_violation == {"counterflow": "approved"}
    assert len(ts["tA"].frames) == 3 and ts["tE"].frames == []          # 40x30 is below the minimum side
    counts = review_counts(paths.db)
    assert counts["counterflow"] == {"approved": 1, "rejected": 0, "pending": 1}


def test_database_is_opened_read_only(tmp_path):
    paths = make_env(tmp_path)
    before = paths.db.stat().st_mtime_ns
    read_statuses(paths.db, ["v1"])
    review_counts(paths.db)
    assert paths.db.stat().st_mtime_ns == before
    assert not list(paths.backend.glob("*.db-journal"))


# ─── routing + collect ───────────────────────────────────────────────────────

def test_routing_rows():
    mk = lambda **kw: collect_mod.Ticket("t", "u", 1, kw.pop("violations"), kw.pop("plate_text", "unidentified"),  # noqa: E731
                                         kw.pop("plate_found", False), [], [], kw.pop("status", {}))
    w = collect_mod.wants_for(mk(violations=["no_plate"], status={"no_plate": "rejected"}))
    assert [(x.model, x.intent, x.priority) for x in w] == [("plate_specialist", "find_plate", 0)]
    w = collect_mod.wants_for(mk(violations=["counterflow"]))                 # plate was never read
    assert (w[0].intent, w[0].priority) == ("find_plate", 3)
    w = collect_mod.wants_for(mk(violations=["counterflow"], plate_found=True, plate_text="ABC123"))
    assert (w[0].intent, w[0].priority) == ("plate_present", 4)
    w = collect_mod.wants_for(mk(violations=["no_helmet"], status={"no_helmet": "rejected"}))
    assert ("helmet_specialist", "riders") in [(x.model, x.intent) for x in w]
    w = collect_mod.wants_for(mk(violations=["no_seatbelt", "missing_side_mirror"]))
    assert [x.model for x in w].count("cabin_specialist") == 2


def test_collect_states_dedupe_protection_and_isolation(tmp_path):
    paths = make_env(tmp_path)
    store = Store(paths)
    dets = StubDetectors({"plate_specialist": StubDet(plate_box_if_wide)})   # no helmet model deployed yet
    before = tree(paths.lab / "datasets") | {f"backend:{p}" for p in tree(paths.backend)}

    dry = collect_mod.collect(paths, store, dets, dry_run=True)
    assert dry["added"]["plate_specialist"]["check"] > 0 and store.counts("plate_specialist")["needs_eyes"] == 0

    s = collect_mod.collect(paths, store, dets)
    plate = s["added"]["plate_specialist"]
    assert plate["check"] >= 3 and plate["label"] >= 1         # A's frames got a box; C is a confirmed negative
    items = {i.ticket_uid: i for i in store.items("plate_specialist", ("check", "label"))}
    a = [i for i in store.items("plate_specialist", ("check",)) if i.ticket_uid == "tA"]
    assert a and all(i.suggested and len(i.boxes) == 1 for i in a)
    c = items["tC"]                                              # operator confirmed 'no plate', no detection
    assert c.state == "check" and c.boxes == [] and c.suggested and c.priority == 2
    d = [i for i in store.items("plate_specialist", ("check", "label")) if i.ticket_uid == "tD"]
    assert [(i.state, i.priority) for i in d] == [("label", 3)]       # plate never read on a helmet ticket
    helmet = store.items("helmet_specialist", ("check", "label"))
    assert [(i.ticket_uid, i.state, i.priority) for i in helmet] == [("tD", "label", 0)]   # rejected -> first
    assert "tE" not in {i.ticket_uid for i in store.items("plate_specialist", ("check", "label"))}
    assert store.image_path("plate_specialist", a[0].id).exists()

    again = collect_mod.collect(paths, store, dets)             # nothing new the second time
    assert sum(b["check"] + b["label"] for b in again["added"].values()) == 0 and again["already_have"] > 0

    # nothing outside the inbox changed: no dataset files, nothing inside the backend
    after = tree(paths.lab / "datasets") | {f"backend:{p}" for p in tree(paths.backend)}
    assert after == before


def test_protected_clips_are_skipped(tmp_path):
    paths = make_env(tmp_path)
    set_protected(paths, "task1")
    s = collect_mod.collect(paths, Store(paths), StubDetectors({}))
    assert s["protected_tasks"] == 1 and s["tickets"] == 0 and s["added"] == {}


def test_suggestions_arrive_when_a_model_is_deployed_later(tmp_path):
    paths = make_env(tmp_path)
    store = Store(paths)
    collect_mod.collect(paths, store, StubDetectors({}))                         # no model yet: all 'label'
    assert store.counts("plate_specialist")["check"] == 1                        # only the confirmed negative
    models = paths.models
    (models / "Plate Models").mkdir(parents=True)
    (models / "Plate Models" / "plate_specialist.onnx").write_bytes(b"x")        # "deploy" a model
    n = collect_mod.refresh_suggestions(paths, store, StubDetectors({"plate_specialist": StubDet(plate_box_if_wide)}))
    assert n == 2 and store.counts("plate_specialist")["check"] == 3     # ticket A's two frames got a box
    # same model file again: no repeated work
    assert collect_mod.refresh_suggestions(paths, store, StubDetectors({"plate_specialist": StubDet(lambda i: [])})) == 0


# ─── review + accept ─────────────────────────────────────────────────────────

def ready_item(store, paths, model, name, group, boxes, hint=None):
    write_img(store.image_path(model, name), 64, 48, seed=len(name))
    store.add(Item(id=name, model=model, state="check", source="ticket", group_id=group, split_hint=hint,
                   boxes=boxes, width=64, height=48))
    store.save_boxes(name, boxes)


def test_boxes_are_validated_and_saved(tmp_path):
    paths = make_env(tmp_path)
    store = Store(paths)
    cleaned = clean_boxes([[0, .5, .5, .2, .2], [5, .5, .5, .2, .2], [0, .5, .5, 0, .2], [0, 1.2, .5, .6, .4]], 2)
    # bad class and zero size dropped; the box sticking out of the picture is clamped to it
    assert np.allclose(cleaned, [[0, .5, .5, .2, .2], [0, 0.95, 0.5, 0.1, 0.4]])
    ready_item(store, paths, "plate_specialist", "a" * 16, "g1", [[0, .5, .5, .3, .2]])
    assert store.label_path("plate_specialist", "a" * 16).read_text().startswith("0 0.500000 0.500000")
    store.skip("a" * 16)
    assert store.get("a" * 16).state == "skipped"
    # "nothing here" is a real answer: an EMPTY label file, not a missing one and not a box
    ready_item(store, paths, "plate_specialist", "c" * 16, "g2", [])
    assert store.label_path("plate_specialist", "c" * 16).read_text() == ""
    assert store.get("c" * 16).state == "ready" and store.get("c" * 16).boxes == []


def test_accept_places_files_keeps_groups_together_and_never_touches_test(tmp_path, monkeypatch):
    paths = make_env(tmp_path)
    store = Store(paths)
    monkeypatch.setattr(accept_mod, "training_models", lambda: set())
    for i in range(30):                                      # 3 frames per car, 10 cars
        ready_item(store, paths, "plate_specialist", f"{i:016x}", f"car{i // 3}", [[0, .5, .5, .3, .2]])
    ready_item(store, paths, "plate_specialist", "f" * 16, "photo:x", [], hint="val")   # a 'nothing here'
    dry = accept_mod.accept(paths, store, "plate_specialist", dry_run=True)
    assert dry["ready"] == 31 and not (paths.datasets / "plate_specialist" / "train").exists()

    r = accept_mod.accept(paths, store, "plate_specialist")
    assert r["added"] == 31 and r["empty_labels"] == 1 and r["train"] + r["val"] == 31
    ds = paths.datasets / "plate_specialist"
    trained = {p.stem for p in (ds / "train" / "images").glob("harvest__*.jpg")}
    valed = {p.stem for p in (ds / "valid" / "images").glob("harvest__*.jpg")}
    assert len(trained) + len(valed) == 31 and not (ds / "test").exists()
    # the three frames of one car are never split across train and val
    for car in range(10):
        names = {f"harvest__{i:016x}" for i in range(car * 3, car * 3 + 3)}
        assert names <= trained or names <= valed
    assert "harvest__" + "f" * 16 in valed                                  # hint honoured
    assert (ds / "valid" / "labels" / ("harvest__" + "f" * 16 + ".txt")).read_text() == ""
    assert store.counts("plate_specialist")["accepted"] == 31
    assert accept_mod.accept(paths, store, "plate_specialist")["added"] == 0          # nothing twice


def test_accept_is_refused_while_the_model_trains(tmp_path, monkeypatch):
    paths = make_env(tmp_path)
    store = Store(paths)
    ready_item(store, paths, "helmet_specialist", "b" * 16, "g", [[1, .5, .5, .4, .6]])
    monkeypatch.setattr(accept_mod, "training_models", lambda: {"helmet_specialist"})
    with pytest.raises(accept_mod.TrainingBusy):
        accept_mod.accept(paths, store, "helmet_specialist")
    assert not (paths.datasets / "helmet_specialist" / "images").exists()           # nothing written
    assert store.counts("helmet_specialist")["ready"] == 1                          # and nothing lost
    monkeypatch.setattr(accept_mod, "training_models", lambda: {"cabin_specialist"})
    assert accept_mod.accept(paths, store, "helmet_specialist")["added"] == 1       # other model: fine


# ─── cutting plate photos into vehicle pictures ──────────────────────────────

def test_cut_one_moves_the_plate_box_into_the_crop():
    img = np.full((300, 400, 3), 40, np.uint8)
    img[200:220, 150:210] = 255                                     # the plate: x 150..210, y 200..220
    plate = [((150 + 210) / 2 / 400, (200 + 220) / 2 / 300, 60 / 400, 20 / 300)]
    other_vehicle_plate = [(0.9, 0.1, 0.05, 0.03)]                  # belongs to a vehicle we did not find
    vehicle = Det(2, 0.9, 100, 80, 300, 260)                        # 200 x 180
    (crop, labels), = cut_one(img, plate + other_vehicle_plate, [vehicle], margin=0.0, min_side=50)
    assert crop.shape[:2] == (180, 200) and len(labels) == 1
    _, cx, cy, w, h = labels[0]
    x1, x2 = round((cx - w / 2) * 200), round((cx + w / 2) * 200)
    y1, y2 = round((cy - h / 2) * 180), round((cy + h / 2) * 180)
    inside = crop[y1:y2, x1:x2]
    assert inside.min() == 255                                      # the label box sits exactly on the white plate
    assert crop[y1 - 4:y1 - 1].max() < 255 or y1 < 4

    # a plate mostly outside the vehicle crop is not labelled (a fragment is not a plate)
    edge_plate = [(103 / 400, 150 / 300, 60 / 400, 20 / 300)]             # spans x 73..133; crop starts at 100: 55% in
    assert cut_one(img, edge_plate, [vehicle], margin=0.0, min_side=50) == []
    mostly_in = [(112 / 400, 150 / 300, 60 / 400, 20 / 300)]              # spans x 82..142: 70% in -> kept
    assert len(cut_one(img, mostly_in, [vehicle], margin=0.0, min_side=50)) == 1


def test_cut_plates_end_to_end(tmp_path):
    paths = make_env(tmp_path)
    store = Store(paths)
    ds = paths.datasets / "plate_specialist"
    for split, name in (("train", "p1"), ("valid", "p2"), ("test", "p3")):
        img = np.full((300, 400, 3), 40, np.uint8)
        (ds / split / "images").mkdir(parents=True)
        (ds / split / "labels").mkdir(parents=True)
        cv2.imwrite(str(ds / split / "images" / f"{name}.jpg"), img)
        (ds / split / "labels" / f"{name}.txt").write_text("0 0.5 0.7 0.15 0.07\n")
    vehicles = StubDet(lambda image: [Det(2, 0.9, 100, 80, 300, 260)])
    r = cut_plates(paths, store, _wrap(vehicles))
    assert r["photos"] == 2 and r["crops"] == 2                      # test photo is never used
    rows = {i.split_hint for i in store.ready("plate_specialist")}
    assert rows == {"train", "val"}
    assert all(i.source == "plate_photo_cut" for i in store.ready("plate_specialist"))
    again = cut_plates(paths, store, _wrap(vehicles))
    assert again["crops"] == 0 and again["already_cut"] == 2
    # "redo" forgets only what was never added to a dataset
    keep = store.ready("plate_specialist")[0]
    store.mark_accepted(keep.id, "harvest__x.jpg")
    assert store.forget("plate_specialist", "plate_photo_cut") == 1
    assert store.get(keep.id) is not None and store.image_path("plate_specialist", keep.id).exists()
    assert cut_plates(paths, store, _wrap(vehicles))["crops"] == 1                # the forgotten one is cut again
    assert not any(p.name.startswith("harvest__") for p in (ds / "train" / "images").iterdir())   # dataset untouched


def _wrap(stub):
    """A Detector-shaped object for cut_plates: names unknown -> COCO vehicle ids."""
    stub.names = {}
    return stub


def test_read_plate_boxes_accepts_boxes_and_polygons(tmp_path):
    f = tmp_path / "x.txt"
    f.write_text("0 0.5 0.5 0.2 0.1\n0 0.1 0.1 0.3 0.1 0.3 0.3 0.1 0.3\n")
    boxes = read_plate_boxes(f)
    assert boxes[0] == (0.5, 0.5, 0.2, 0.1) and boxes[1] == pytest.approx((0.2, 0.2, 0.2, 0.2))


# ─── the page's server ───────────────────────────────────────────────────────

@pytest.fixture
def server(tmp_path, monkeypatch):
    paths = make_env(tmp_path)
    monkeypatch.setattr(accept_mod, "training_models", lambda: set())
    import harvest_tool.web as web
    monkeypatch.setattr(web, "training_models", lambda: set())
    app = HarvestApp(paths)
    srv = make_server(app, 0, token="secret")
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_address[1]}"
    yield app, base, paths
    srv.shutdown()
    srv.server_close()


def call(base, path, body=None, token="secret"):
    url = f"{base}{path}{'&' if '?' in path else '?'}t={token}"
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"} if data else {})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read(), r.headers.get("Content-Type")
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers.get("Content-Type")


def test_page_requires_the_token(server):
    _, base, _ = server
    assert call(base, "/api/board", token="wrong")[0] == 403
    assert call(base, "/", token="")[0] == 403
    status, body, ctype = call(base, "/")
    assert status == 200 and b"Harvest" in body and "text/html" in ctype


def test_page_flow_board_queue_save_skip_accept(server, monkeypatch):
    app, base, paths = server
    collect_mod.collect(paths, app.store, StubDetectors({"plate_specialist": StubDet(plate_box_if_wide)}))

    board = json.loads(call(base, "/api/board")[1])
    plate = next(m for m in board["models"] if m["key"] == "plate_specialist")
    assert plate["counts"]["needs_eyes"] >= 4 and plate["classes"] == ["license_plate"]
    assert {r["violation"] for r in board["rules"]} >= {"counterflow", "no_plate"}

    q = json.loads(call(base, "/api/queue?model=plate_specialist")[1])
    first, second = q["items"][0], q["items"][1]
    priorities = [i["priority"] for i in q["items"]]
    assert priorities == sorted(priorities)                                      # most likely wrong ones first
    status, body, ctype = call(base, f"/img/plate_specialist/{first['id']}.jpg")
    assert status == 200 and ctype == "image/jpeg" and body[:2] == b"\xff\xd8"
    assert call(base, "/img/plate_specialist/..%2F..%2Fx.jpg")[0] == 404
    assert call(base, "/img/nope/" + first["id"] + ".jpg")[0] == 404

    saved = json.loads(call(base, "/api/save", {"id": first["id"], "boxes": [[0, .5, .5, .4, .2], [9, .5, .5, .1, .1]]})[1])
    assert saved["counts"]["ready"] == 1
    kept = app.store.get(first["id"]).boxes
    assert len(kept) == 1 and kept[0][0] == 0 and kept[0][3] == pytest.approx(.4)   # the invalid class was dropped
    assert json.loads(call(base, "/api/skip", {"id": second["id"]})[1])["counts"]["skipped"] == 1
    assert call(base, "/api/save", {"id": "0" * 16, "boxes": []})[0] == 400

    import harvest_tool.web as web
    monkeypatch.setattr(accept_mod, "training_models", lambda: {"plate_specialist"})
    status, body, _ = call(base, "/api/accept", {"model": "plate_specialist"})
    assert status == 409 and b"training" in body
    monkeypatch.setattr(accept_mod, "training_models", lambda: set())
    status, body, _ = call(base, "/api/accept", {"model": "plate_specialist"})
    assert status == 200 and json.loads(body)["added"] == 1
    assert web.PAGE.exists()


def test_one_analysis_can_be_asked_about_on_its_own(server):
    app, base, paths = server
    # a second analysis, collected earlier: its pictures must not leak into the first one's session
    app.store.add(Item(id="b" * 16, model="plate_specialist", state="check", source="ticket", group_id="other:t",
                       task_id="other", ticket_uid="tZ", width=64, height=48, boxes=[[0, .5, .5, .3, .2]]))
    app.store.mark_collected("other", collect_mod.COLLECT_VERSION)
    before = json.loads(call(base, "/api/session?task=task1")[1])
    assert before["collected"] is False and before["protected"] is False             # nothing of task1 collected yet
    assert json.loads(call(base, "/api/session?task=other")[1])["collected"] is True
    assert json.loads(call(base, "/api/session")[1])["collected"] is True            # no task = every analysis

    collect_mod.collect(paths, app.store, StubDetectors({"plate_specialist": StubDet(plate_box_if_wide)}), task_ids=["task1"])
    s = json.loads(call(base, "/api/session?task=task1")[1])
    plate = next(m for m in s["models"] if m["key"] == "plate_specialist")
    assert s["collected"] is True and plate["counts"]["needs_eyes"] >= 4 and plate["classes"] == ["license_plate"]
    assert "other" not in json.dumps(s)

    q = json.loads(call(base, "/api/queue?model=plate_specialist&task=task1")[1])
    assert q["items"] and {i["task"] for i in q["items"]} == {"task1"} and q["total"] == plate["counts"]["needs_eyes"]
    assert all(i["ticket"] for i in q["items"])
    other = json.loads(call(base, "/api/queue?model=plate_specialist&task=other")[1])
    assert [i["id"] for i in other["items"]] == ["b" * 16]
    assert json.loads(call(base, "/api/queue?model=plate_specialist&task=nobody")[1])["items"] == []
    everything = json.loads(call(base, "/api/queue?model=plate_specialist")[1])
    assert len(everything["items"]) == len(q["items"]) + 1

    assert call(base, "/api/session?task=..%2F..%2Fx")[0] == 400                      # an id is never a path
    assert call(base, "/api/queue?model=plate_specialist&task=a%20b")[0] == 400


def test_protected_analysis_is_reported_as_such(server):
    app, base, paths = server
    set_protected(paths, "task1")
    assert json.loads(call(base, "/api/session?task=task1")[1])["protected"] is True


def test_collect_can_be_limited_to_one_analysis(server, monkeypatch):
    app, base, paths = server
    import harvest_tool.web as web
    seen = []
    monkeypatch.setattr(web, "collect", lambda p, s, task_ids=None, **kw: seen.append(task_ids) or {"tasks": 1})
    monkeypatch.setattr(web, "refresh_suggestions", lambda p, s: 0)

    def wait():
        for _ in range(100):
            if not app._collect["running"]:
                return
            threading.Event().wait(0.05)
        raise AssertionError("collect never finished")

    assert json.loads(call(base, "/api/collect", {"task": "task1"})[1])["task"] == "task1"
    wait()
    call(base, "/api/collect", {})
    wait()
    assert seen == [["task1"], None]                                                    # one analysis, then all of them
    assert call(base, "/api/collect", {"task": "../x"})[0] == 400


def test_every_request_counts_as_activity_for_the_idle_exit(tmp_path):
    paths = make_env(tmp_path)
    srv = make_server(HarvestApp(paths), 0, token="secret")
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    try:
        srv.last_request = 0
        call(f"http://127.0.0.1:{srv.server_address[1]}", "/api/ping")
        assert srv.last_request > 0
    finally:
        srv.shutdown()
        srv.server_close()


# ─── gallery: the snapshot the Forensic Analyzer's Harvest tab reads ──────────

def test_gallery_groups_every_picture_by_use_and_state(tmp_path):
    from harvest_tool.gallery import write_gallery
    paths = make_env(tmp_path)
    store = Store(paths)
    collect_mod.collect(paths, store, StubDetectors({"plate_specialist": StubDet(plate_box_if_wide)}))
    waiting = store.items("plate_specialist", ("check", "label"))
    store.save_boxes(waiting[0].id, [[0, .5, .5, .3, .2]])
    store.skip(waiting[1].id)
    # data the app collects by itself
    write_img(paths.lab / "datasets" / "plate_ocr" / "images" / "train" / "AB1234_1790380231712.jpg", 60, 20)
    car = paths.lab / "datasets" / "reid" / "images" / "task9" / "car1"
    write_img(car / "1.jpg", 30, 30)
    write_img(car / "2.jpg", 30, 30)
    before = tree(paths.lab / "datasets") | {f"backend:{p}" for p in tree(paths.backend)}

    target = write_gallery(paths, store, busy={"helmet_specialist"})
    data = json.loads(target.read_text(encoding="utf-8"))
    assert target == paths.inbox / "gallery.json" and data["schema"] == 1
    cats = {c["key"]: c for c in data["categories"]}
    assert list(cats) == ["plate_specialist", "helmet_specialist", "cabin_specialist", "primary_anchor", "plate_ocr", "reid"]

    plate = cats["plate_specialist"]
    c = store.counts("plate_specialist")
    total = sum(c[s] for s in ("check", "label", "ready", "skipped", "accepted"))
    assert plate["counts"]["total"] == len(plate["items"]) == total
    assert plate["counts"]["ready"] == 1 and plate["counts"]["skipped"] == 1
    order = ["check", "label", "ready", "skipped", "accepted"]
    states = [i["state"] for i in plate["items"]]
    assert states == sorted(states, key=order.index)                          # waiting pictures first
    assert plate["used_for"] and plate["fed_by"] and plate["your_job"]
    assert plate["classes"][0]["name"] == "license_plate" and plate["classes"][0]["help"]
    item = plate["items"][0]
    assert (paths.inbox / item["image"]).exists() and item["why"] and item["reason"] and item["violation"]
    assert [s["key"] for s in plate["sources"]] == ["ticket"] and plate["sources"][0]["label"]
    assert cats["helmet_specialist"]["violations"] == ["no_helmet"]
    assert cats["helmet_specialist"]["training"] is True and plate["training"] is False
    assert [i["why"] for i in cats["helmet_specialist"]["items"]] == ["'no helmet' ticket"]

    ocr = cats["plate_ocr"]
    assert ocr["kind"] == "automatic" and ocr["count"] == 1
    assert ocr["samples"][0]["label"] == "AB1234"
    assert ocr["samples"][0]["path"] == "datasets/plate_ocr/images/train/AB1234_1790380231712.jpg"
    reid = cats["reid"]
    assert reid["count"] == 1 and reid["groups"][0]["n"] == 2 and len(reid["groups"][0]["photos"]) == 2

    # the snapshot lives inside the inbox: no dataset file and nothing in the backend changed
    after = tree(paths.lab / "datasets") | {f"backend:{p}" for p in tree(paths.backend)}
    assert after == before


def test_gallery_keeps_the_last_known_training_flags_when_not_checked(tmp_path):
    from harvest_tool.gallery import read_gallery, write_gallery
    paths = make_env(tmp_path)
    store = Store(paths)
    write_gallery(paths, store, busy={"plate_specialist"})
    write_gallery(paths, store, busy=None)                       # e.g. after labelling one picture
    flags = {c["key"]: c["training"] for c in read_gallery(paths)["categories"] if c["kind"] == "detector"}
    assert flags == {"plate_specialist": True, "helmet_specialist": False, "cabin_specialist": False,
                     "primary_anchor": False}
    write_gallery(paths, store, busy=set())
    assert not any(c["training"] for c in read_gallery(paths)["categories"] if c["kind"] == "detector")


def test_labelling_a_picture_refreshes_the_snapshot(tmp_path):
    from harvest_tool.gallery import read_gallery
    paths = make_env(tmp_path)
    app = HarvestApp(paths)
    ready_item(app.store, paths, "plate_specialist", "a" * 16, "g1", [])           # becomes ready
    write_img(app.store.image_path("plate_specialist", "b" * 16), 64, 48)
    app.store.add(Item(id="b" * 16, model="plate_specialist", state="check", source="ticket", group_id="g2",
                       width=64, height=48))
    assert read_gallery(paths) is None                                              # nothing published yet
    app.save("b" * 16, [[0, .5, .5, .3, .2]])
    plate = next(c for c in read_gallery(paths)["categories"] if c["key"] == "plate_specialist")
    assert plate["counts"]["ready"] == 2
    app.skip("a" * 16)
    plate = next(c for c in read_gallery(paths)["categories"] if c["key"] == "plate_specialist")
    assert plate["counts"]["skipped"] == 1 and plate["counts"]["ready"] == 1


# ─── "same car?" questions ───────────────────────────────────────────────────

def solid(path: Path, w: int, h: int, bgr) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), np.full((h, w, 3), bgr, np.uint8))


def car_ticket(paths, uid, track, colour, times, x, vclass="car"):
    meta = []
    for i, t in enumerate(times):
        name = f"{uid}_{i}"
        solid(paths.evidence / f"{name}.jpg", 120, 160, colour)
        meta.append({"file": f"{name}.jpg", "bbox": [x, 100, 120, 160], "t": t, "car_crop": f"{name}.jpg",
                     "clean": f"{name}.jpg", "clean_box": [x, 100, 120, 160], "vclass": vclass})
    return {"ticket_uid": uid, "track_id": track, "violations": ["counterflow"], "plate_text": "", "db_ids": [],
            "plate_crop_paths": [], "evidence_meta": meta}


def pair_env(tmp_path: Path, extra=()) -> Paths:
    """Red car A (0-2 s), then red car B right after (2.5-5 s), and a blue car C present the whole time."""
    paths = Paths(lab=tmp_path / "lab", backend=tmp_path / "backend")
    report = [car_ticket(paths, "tA", 1, (0, 0, 200), [0.0, 1.0, 2.0], 100),
              car_ticket(paths, "tB", 2, (0, 0, 200), [2.5, 3.5, 5.0], 140),
              car_ticket(paths, "tC", 3, (200, 0, 0), [0.0, 2.5, 5.0], 600), *extra]
    out = paths.forensic / "task1" / "output"
    out.mkdir(parents=True)
    (out / "report.json").write_text(json.dumps(report))
    return paths


def test_a_car_that_vanishes_as_a_look_alike_appears_is_asked_about(tmp_path):
    from harvest_tool.pairs import build_pairs
    paths = pair_env(tmp_path)
    store = Store(paths)
    assert build_pairs(paths, store, "task1", dry_run=True) == 1 and store.open_pairs() == []     # a dry run writes nothing
    assert build_pairs(paths, store, "task1") == 1
    assert build_pairs(paths, store, "task1") == 0                                              # asking twice adds nothing
    (pair,) = store.open_pairs()
    assert pair.kind == "gap" and {pair.a_label, pair.b_label} == {"task1_tA", "task1_tB"}      # the blue car is not a candidate
    assert pair.a_label == "task1_tA" and len(pair.a_files) == 3 and len(pair.b_files) == 3
    assert store.pair_image_path(pair.id, "a").exists() and store.pair_image_path(pair.id, "b").exists()
    assert store.pair_counts("task1") == {"open": 1, "same": 0, "different": 0, "skipped": 0}
    assert store.pair_counts("elsewhere")["open"] == 0


def test_same_car_puts_both_cars_in_one_identity_folder_like_the_review_screens(tmp_path):
    from harvest_tool.pairs import answer_pair, build_pairs
    paths = pair_env(tmp_path)
    store = Store(paths)
    build_pairs(paths, store, "task1")
    (pair,) = store.open_pairs()
    # the second car had been recorded alone earlier (a review decision): its photos must move, not be duplicated
    old = paths.datasets / "reid" / "images" / "task1" / "task1_tB"
    solid(old / "tB_0.jpg", 120, 160, (0, 0, 200))
    done = answer_pair(paths, store, pair.id, "same")
    assert done.state == "same"
    images = paths.datasets / "reid" / "images" / "task1"
    assert sorted(f.name for f in (images / "task1_tA").iterdir()) == sorted(
        [f"tA_{i}.jpg" for i in range(3)] + [f"tB_{i}.jpg" for i in range(3)])
    assert not (images / "task1_tB").exists()
    line = json.loads((paths.datasets / "reid" / "decisions.jsonl").read_text().splitlines()[-1])
    assert line["kind"] == "merge" and line["source"] == "harvest" and list(line["identities"]) == ["task1_tA"]
    assert answer_pair(paths, store, pair.id, "same").state == "same"                            # answering twice is harmless
    with pytest.raises(ValueError):
        answer_pair(paths, store, pair.id, "different")                                         # a decided pair cannot flip
    assert store.open_pairs() == []


def test_different_cars_stay_in_their_own_folders_and_not_sure_teaches_nothing(tmp_path):
    from harvest_tool.pairs import answer_pair, build_pairs
    paths = pair_env(tmp_path)
    store = Store(paths)
    build_pairs(paths, store, "task1")
    (pair,) = store.open_pairs()
    assert answer_pair(paths, store, pair.id, "skip").state == "skipped"
    assert not (paths.datasets / "reid").exists()                                               # nothing was written
    assert answer_pair(paths, store, pair.id, "different").state == "different"                 # a skipped one can still be answered
    images = paths.datasets / "reid" / "images" / "task1"
    assert len(list((images / "task1_tA").iterdir())) == 3 and len(list((images / "task1_tB").iterdir())) == 3
    line = json.loads((paths.datasets / "reid" / "decisions.jsonl").read_text().splitlines()[-1])
    assert line["kind"] == "not_same" and sorted(line["identities"]) == ["task1_tA", "task1_tB"]
    with pytest.raises(ValueError):
        answer_pair(paths, store, pair.id, "maybe")
    with pytest.raises(KeyError):
        answer_pair(paths, store, "0" * 16, "same")


def test_two_look_alikes_on_screen_together_are_a_twin_question_and_pairs_already_judged_are_not_asked(tmp_path):
    from harvest_tool.pairs import build_pairs
    twin = car_ticket(Paths(lab=tmp_path / "lab", backend=tmp_path / "backend"), "tD", 4, (0, 0, 200), [0.0, 2.0, 4.0], 300)
    paths = pair_env(tmp_path, extra=[twin])
    store = Store(paths)
    # a person already said A and B are different cars in the review screen: do not ask again
    reid = paths.datasets / "reid"
    reid.mkdir(parents=True)
    (reid / "decisions.jsonl").write_text(json.dumps({"kind": "not_same", "task_id": "task1",
                                                      "identities": {"task1_tA": [], "task1_tB": []}}) + "\n")
    build_pairs(paths, store, "task1")
    asked = [(p.kind, frozenset((p.a_label, p.b_label))) for p in store.open_pairs()]
    assert ("twin", frozenset(("task1_tB", "task1_tD"))) in asked                                # B and D overlap in time and look alike
    assert not any(k == frozenset(("task1_tA", "task1_tB")) for _, k in asked)
    kinds = [k for k, _ in asked]
    assert kinds == sorted(kinds, key=lambda k: 0 if k == "gap" else 1)                          # likeliest split cars come first


def test_cars_of_different_kinds_are_never_asked_about(tmp_path):
    from harvest_tool.pairs import build_pairs
    paths = pair_env(tmp_path)
    report_file = paths.forensic / "task1" / "output" / "report.json"
    report = json.loads(report_file.read_text())
    for m in report[1]["evidence_meta"]:
        m["vclass"] = "bus"                                                                     # A is a car, B is a bus
    report_file.write_text(json.dumps(report))
    assert build_pairs(paths, Store(paths), "task1") == 0


# ─── the clip's own pictures ─────────────────────────────────────────────────

CAR, BIKE, RIDER = Det(2, .9, 40, 60, 200, 200), Det(3, .9, 210, 100, 300, 220), Det(0, .9, 225, 40, 285, 130)
WALKER = Det(0, .9, 5, 10, 25, 70)


class Finder(StubDet):
    names = {0: "person", 2: "car", 3: "motorcycle"}


def write_clip(path: Path, frames: int = 20, fps: int = 10, size=(320, 240)) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    out = cv2.VideoWriter(str(path), cv2.VideoWriter_fourcc(*"mp4v"), fps, size)
    for i in range(frames):
        out.write(np.full((size[1], size[0], 3), 20 + i, np.uint8))
    out.release()


def clip_env(tmp_path: Path, ticketed: bool = False) -> Paths:
    paths = make_env(tmp_path)
    write_clip(paths.forensic / "task1" / "input_video.mp4")
    if ticketed:        # the car has a ticket, photographed where it is in the clip
        report = json.loads((paths.forensic / "task1" / "output" / "report.json").read_text())
        t = car_ticket(paths, "tZ", 9, (50, 50, 50), [0.0, 1.0, 2.0], 40)
        for m in t["evidence_meta"]:
            m["clean_box"] = [40, 60, 160, 140]
        report.append(t)
        (paths.forensic / "task1" / "output" / "report.json").write_text(json.dumps(report))
    (paths.datasets / "primary_anchor").mkdir(parents=True, exist_ok=True)
    (paths.datasets / "primary_anchor" / "data.yaml").write_text(
        "train: images/train\nval: images/val\nnames:\n  0: motorcycle\n  1: car\n  2: bus\n  3: truck\n  4: person\n  5: tricycle\n")
    return paths


def detectors_for(finder_dets):
    return StubDetectors({"primary_anchor": Finder(lambda img: list(finder_dets)),
                          "plate_specialist": StubDet(lambda img: [Det(0, .9, 10, 10, 40, 25)]),
                          "helmet_specialist": StubDet(lambda img: []), "cabin_specialist": StubDet(lambda img: [])})


def test_frames_of_a_kept_video_become_vehicle_pictures_with_the_finders_guess(tmp_path):
    from harvest_tool.frames import harvest_frames
    paths = clip_env(tmp_path)
    store = Store(paths)
    s = harvest_frames(paths, store, detectors_for([CAR, BIKE, RIDER, WALKER]), collect_mod.suggest, "task1", [])
    assert s["video"] is True and s["frames"] == 8
    frames = store.items("primary_anchor", ("check", "label"))
    assert len(frames) == 8 and {f.source for f in frames} == {"frame"} and {f.group_id for f in frames} == {"task1:frames"}
    boxes = frames[0].boxes
    assert sorted(b[0] for b in boxes) == [0, 1, 4]                 # motorcycle, car, and only the rider (not the walker)
    assert frames[0].state == "check" and frames[0].width == 320 and frames[0].height == 240
    assert store.image_path("primary_anchor", frames[0].id).exists()
    assert harvest_frames(paths, store, detectors_for([CAR, BIKE, RIDER]), collect_mod.suggest, "task1", [])["frames"] == 0   # once only


def test_a_frame_the_finder_sees_nothing_in_is_a_picture_to_label(tmp_path):
    from harvest_tool.frames import harvest_frames
    paths = clip_env(tmp_path)
    store = Store(paths)
    harvest_frames(paths, store, detectors_for([]), collect_mod.suggest, "task1", [])
    assert {f.state for f in store.items("primary_anchor", ("check", "label"))} == {"label"}


def test_unticketed_vehicles_become_plate_helmet_and_cabin_pictures_and_ticketed_ones_do_not(tmp_path):
    from harvest_tool.frames import harvest_frames
    paths = clip_env(tmp_path, ticketed=True)
    store = Store(paths)
    tix = tickets(paths, "task1")
    s = harvest_frames(paths, store, detectors_for([CAR, BIKE]), collect_mod.suggest, "task1", tix)
    # the car is ticketed (tZ), so only the motorcycle is left to learn from: plate + helmet crops, no cabin crops
    assert s["crops"] == {"plate_specialist": 8, "helmet_specialist": 8} and "cabin_specialist" not in s["crops"]
    plate = store.items("plate_specialist", ("check", "label"))
    assert len(plate) == 8 and all(i.source == "frame" and i.ticket_uid is None and i.violation is None for i in plate)
    assert {i.state for i in plate} == {"check"} and all(i.reason.startswith("No ticket") for i in plate)
    assert min(i.width for i in plate) >= 80 and min(i.height for i in plate) >= 80
    assert {i.state for i in store.items("helmet_specialist", ("check", "label"))} == {"label"}      # helmet model saw nothing

    nobody = clip_env(tmp_path / "second")                         # same clip, nothing ticketed: the car gets cabin crops too
    s2 = harvest_frames(nobody, Store(nobody), detectors_for([CAR, BIKE]), collect_mod.suggest, "task1", [])
    assert s2["crops"]["cabin_specialist"] == 8 and s2["crops"]["plate_specialist"] == 12       # capped per analysis


def test_helmet_pictures_are_asked_for_far_more_often_than_the_others(tmp_path):
    """The helmet model misses riders seen from behind / above, so a clip offers up to 60 riders (plates and cabins stay at 12)."""
    from harvest_tool.frames import harvest_frames
    paths = clip_env(tmp_path)
    store = Store(paths)
    bikes = [Det(3, .9, 5 + i * 3, 5 + (i % 3) * 10, 105 + i * 3, 105 + (i % 3) * 10) for i in range(10)]    # ten 100 x 100 motorcycles
    s = harvest_frames(paths, store, detectors_for(bikes), collect_mod.suggest, "task1", [])
    assert s["crops"]["helmet_specialist"] == 60 and s["crops"]["plate_specialist"] == 12
    assert len(store.items("helmet_specialist", ("check", "label"))) == 60


def test_an_analysis_without_its_video_or_without_a_finder_gives_no_frames(tmp_path):
    from harvest_tool.frames import harvest_frames, task_video
    paths = make_env(tmp_path)
    store = Store(paths)
    assert task_video(paths, "task1") is None
    assert harvest_frames(paths, store, detectors_for([CAR]), collect_mod.suggest, "task1", []) == {"video": False, "frames": 0, "crops": {}}
    write_clip(paths.forensic / "task1" / "input_video.mp4")
    s = harvest_frames(paths, store, StubDetectors({}), collect_mod.suggest, "task1", [])
    assert s["video"] is True and s["no_finder"] is True and s["frames"] == 0


def test_collect_gathers_frames_and_pairs_and_remembers_the_analysis_was_gathered(tmp_path):
    paths = clip_env(tmp_path)
    report = json.loads((paths.forensic / "task1" / "output" / "report.json").read_text())
    report += [car_ticket(paths, "tR1", 11, (0, 0, 200), [0.0, 1.0], 100), car_ticket(paths, "tR2", 12, (0, 0, 200), [1.5, 2.5], 130)]
    (paths.forensic / "task1" / "output" / "report.json").write_text(json.dumps(report))
    store = Store(paths)
    assert not store.is_collected("task1", collect_mod.COLLECT_VERSION)
    summary = collect_mod.collect(paths, store, detectors_for([CAR, BIKE]), task_ids=["task1"])
    assert summary["frames"] == 8 and summary["pairs"] >= 1 and summary["no_video"] == 0
    assert summary["frame_crops"]["plate_specialist"] > 0
    assert store.is_collected("task1", collect_mod.COLLECT_VERSION) and not store.is_collected("task1", collect_mod.COLLECT_VERSION + 1)
    again = collect_mod.collect(paths, store, detectors_for([CAR, BIKE]), task_ids=["task1"])
    assert again["frames"] == 0 and again["pairs"] == 0                          # nothing is added twice
    dry_paths = clip_env(tmp_path / "d")
    dry = collect_mod.collect(dry_paths, Store(dry_paths), detectors_for([CAR]), task_ids=["task1"], dry_run=True)
    assert dry["frames"] == 0                                                    # a dry run does not read the video


def test_a_model_the_finder_was_not_trained_on_still_suggests_by_class_name(tmp_path):
    from harvest_tool.frames import anchor_boxes
    anchor = ["motorcycle", "car", "bus", "truck", "person", "tricycle"]
    coco = {0: "person", 2: "car", 3: "motorcycle", 5: "bus", 7: "truck", 1: "bicycle"}
    dets = [Det(7, .9, 0, 0, 100, 50), Det(1, .9, 0, 0, 10, 10), Det(5, .9, 0, 50, 100, 100)]
    assert [b[0] for b in anchor_boxes(dets, coco, anchor, 200, 200)] == [3, 2]         # truck, bus; the bicycle is ignored
    assert [b[0] for b in anchor_boxes([Det(2, .9, 0, 0, 100, 50)], {}, anchor, 200, 200)] == [1]   # no names: COCO ids


# ─── the helper's new questions over HTTP ────────────────────────────────────

def test_session_pairs_and_answers_over_the_helper(server):
    from harvest_tool.pairs import build_pairs
    app, base, paths = server
    status, body, _ = call(base, "/api/ping")
    assert json.loads(body) == {"ok": True, "api": 4}
    s = json.loads(call(base, "/api/session?task=task1")[1])
    assert s["has_video"] is False and s["pairs"] == {"open": 0, "same": 0, "different": 0, "skipped": 0}
    assert [m["key"] for m in s["models"]][-1] == "primary_anchor"
    assert json.loads(call(base, "/api/session")[1])["has_video"] is None                         # no task: not asked

    report = json.loads((paths.forensic / "task1" / "output" / "report.json").read_text())
    report += [car_ticket(paths, "tR1", 11, (0, 0, 200), [0.0, 1.0], 100), car_ticket(paths, "tR2", 12, (0, 0, 200), [1.5, 2.5], 130)]
    (paths.forensic / "task1" / "output" / "report.json").write_text(json.dumps(report))
    assert build_pairs(paths, app.store, "task1") >= 1
    write_clip(paths.forensic / "task1" / "input_video.mp4")
    assert json.loads(call(base, "/api/session?task=task1")[1])["has_video"] is True

    q = json.loads(call(base, "/api/pairs?task=task1")[1])
    assert q["total"] == len(q["items"]) >= 1 and set(q["items"][0]) == {"id", "kind", "reason", "score", "task"}
    pid = q["items"][0]["id"]
    assert json.loads(call(base, "/api/pairs?task=other")[1])["items"] == []
    assert call(base, "/api/pairs?task=a%20b")[0] == 400

    assert call(base, "/api/pair", {"id": pid, "answer": "maybe"})[0] == 400
    assert call(base, "/api/pair", {"id": "../x", "answer": "same"})[0] == 400
    assert call(base, "/api/pair", {"id": "0" * 16, "answer": "same"})[0] == 400                   # unknown pair
    status, body, _ = call(base, "/api/pair", {"id": pid, "answer": "same"})
    assert status == 200 and json.loads(body)["counts"]["same"] == 1
    assert json.loads(call(base, "/api/session?task=task1")[1])["pairs"]["same"] == 1
    assert pid not in {i["id"] for i in json.loads(call(base, "/api/pairs?task=task1")[1])["items"]}


# ─── check one car at a time ─────────────────────────────────────────────────

def test_a_ticket_the_analyzer_merged_from_two_tracks_still_opens_in_the_cars_tile(tmp_path):
    from harvest_tool.cars import car_list
    from harvest_tool.sources import _track_number
    paths = pair_env(tmp_path)
    report_file = paths.forensic / "task1" / "output" / "report.json"
    report = json.loads(report_file.read_text())
    report[1]["track_id"] = "412 & 5"                                          # what a merged ticket says
    report_file.write_text(json.dumps(report))
    assert tickets(paths, "task1")[1].track_id == 412
    assert sorted(c["track"] for c in car_list(paths, Store(paths), "task1")["items"]) == [1, 3, 412]
    assert _track_number(7) == 7 and _track_number(None) == -1 and _track_number("no number") == -1


def test_cars_of_an_analysis_are_listed_by_number_and_a_car_with_one_photo_is_left_out(tmp_path):
    from harvest_tool.cars import car_counts, car_list
    paths = pair_env(tmp_path, extra=[car_ticket(Paths(lab=tmp_path / "lab", backend=tmp_path / "backend"), "tOne", 9, (0, 9, 0), [1.0], 50)])
    store = Store(paths)
    data = car_list(paths, store, "task1")
    assert [c["track"] for c in data["items"]] == [1, 2, 3] and data["counts"] == {"open": 3, "checked": 0, "split": 0}
    first = data["items"][0]
    assert first["uid"] == "tA" and first["label"] == "task1_tA" and first["photos"] == 3 and first["first"] == "tA_0.jpg"
    assert first["state"] == "open" and first["violations"] == ["counterflow"]
    assert data["evidence_dir"] == str(paths.evidence)
    assert car_counts(paths, store, "task1") == {"open": 3, "checked": 0, "split": 0}
    assert car_counts(paths, store, "nobody") == {"open": 0, "checked": 0, "split": 0}      # no report: nothing to check, no error
    with pytest.raises(KeyError):
        car_list(paths, store, "nobody")


def test_one_car_in_time_order_with_nothing_marked_at_first(tmp_path):
    from harvest_tool.cars import car_detail
    paths = pair_env(tmp_path)
    d = car_detail(paths, Store(paths), "task1", "tB")
    assert d["photos"] == ["tB_0.jpg", "tB_1.jpg", "tB_2.jpg"] and d["marked"] == [] and d["state"] == "open" and d["track"] == 2
    with pytest.raises(KeyError):
        car_detail(paths, Store(paths), "task1", "nope")


def test_all_one_car_files_every_photo_under_one_identity(tmp_path):
    from harvest_tool.cars import check_car
    paths = pair_env(tmp_path)
    store = Store(paths)
    done = check_car(paths, store, "task1", "tA", [])
    assert done["state"] == "checked" and done["kept"] == 3 and done["other"] == 0 and done["counts"]["checked"] == 1
    folder = paths.datasets / "reid" / "images" / "task1" / "task1_tA"
    assert sorted(f.name for f in folder.iterdir()) == ["tA_0.jpg", "tA_1.jpg", "tA_2.jpg"]
    line = json.loads((paths.datasets / "reid" / "decisions.jsonl").read_text().splitlines()[-1])
    assert line["kind"] == "checked" and line["source"] == "harvest" and list(line["identities"]) == ["task1_tA"]
    assert store.car_checks("task1") == {"tA": ("checked", [])}


def test_marked_photos_become_another_car_and_can_be_changed_later(tmp_path):
    from harvest_tool.cars import car_detail, check_car
    paths = pair_env(tmp_path)
    store = Store(paths)
    images = paths.datasets / "reid" / "images" / "task1"
    solid(images / "task1_tA" / "tA_2.jpg", 120, 160, (0, 0, 200))           # an earlier review decision filed it under the car
    done = check_car(paths, store, "task1", "tA", ["tA_2.jpg", "tA_1.jpg"])
    assert done["state"] == "split" and done["kept"] == 1 and done["other"] == 2
    assert [f.name for f in (images / "task1_tA").iterdir()] == ["tA_0.jpg"]
    assert sorted(f.name for f in (images / "task1_tA_b").iterdir()) == ["tA_1.jpg", "tA_2.jpg"]          # moved, not duplicated
    line = json.loads((paths.datasets / "reid" / "decisions.jsonl").read_text().splitlines()[-1])
    assert line["kind"] == "split" and sorted(line["identities"]) == ["task1_tA", "task1_tA_b"]
    assert car_detail(paths, store, "task1", "tA")["marked"] == ["tA_1.jpg", "tA_2.jpg"]
    assert car_detail(paths, store, "task1", "tA")["state"] == "split"

    check_car(paths, store, "task1", "tA", ["tA_2.jpg"])                      # changed their mind about one photo
    assert sorted(f.name for f in (images / "task1_tA").iterdir()) == ["tA_0.jpg", "tA_1.jpg"]
    assert [f.name for f in (images / "task1_tA_b").iterdir()] == ["tA_2.jpg"]

    check_car(paths, store, "task1", "tA", [])                                # and then that all of it is one car
    assert not (images / "task1_tA_b").exists()                               # an empty folder is not a car
    assert len(list((images / "task1_tA").iterdir())) == 3
    assert store.car_checks("task1")["tA"][0] == "checked"


def test_what_cannot_be_marked_is_refused_and_nothing_is_written(tmp_path):
    from harvest_tool.cars import check_car
    paths = pair_env(tmp_path)
    store = Store(paths)
    with pytest.raises(ValueError):
        check_car(paths, store, "task1", "tA", ["tA_0.jpg"])                  # the first photo IS the original
    with pytest.raises(ValueError):
        check_car(paths, store, "task1", "tA", ["tB_1.jpg"])                  # a photo of another car
    with pytest.raises(ValueError):
        check_car(paths, store, "task1", "tA", ["../../hulikamote.db"])       # never a path
    with pytest.raises(KeyError):
        check_car(paths, store, "task1", "tZ", [])
    assert not (paths.datasets / "reid").exists() and store.car_checks("task1") == {}


def test_cars_over_the_helper(server):
    app, base, paths = server
    report = json.loads((paths.forensic / "task1" / "output" / "report.json").read_text())
    report += [car_ticket(paths, "tR1", 11, (0, 0, 200), [0.0, 1.0, 2.0], 100)]
    (paths.forensic / "task1" / "output" / "report.json").write_text(json.dumps(report))
    s = json.loads(call(base, "/api/session?task=task1")[1])
    assert s["cars"] == {"open": 2, "checked": 0, "split": 0}                # tA has 3 photos, tR1 has 3; the rest have 1
    assert json.loads(call(base, "/api/session")[1])["cars"] == {"open": 0, "checked": 0, "split": 0}

    listing = json.loads(call(base, "/api/cars?task=task1")[1])
    assert [c["uid"] for c in listing["items"]] == ["tA", "tR1"] and listing["evidence_dir"] == str(paths.evidence)
    assert call(base, "/api/cars")[0] == 400 and call(base, "/api/cars?task=nobody")[0] == 400
    assert call(base, "/api/cars?task=a%20b")[0] == 400

    one = json.loads(call(base, "/api/car?task=task1&uid=tR1")[1])
    assert one["photos"] == ["tR1_0.jpg", "tR1_1.jpg", "tR1_2.jpg"] and one["marked"] == []
    assert call(base, "/api/car?task=task1&uid=nope")[0] == 400 and call(base, "/api/car?task=task1")[0] == 400
    assert call(base, "/api/car?task=task1&uid=..%2Fx")[0] == 400

    assert call(base, "/api/car", {"task": "task1", "uid": "tR1", "different": ["tR1_0.jpg"]})[0] == 400      # the original
    assert call(base, "/api/car", {"task": "task1", "uid": "tR1", "different": "tR1_1.jpg"})[0] == 400         # not a list
    status, body, _ = call(base, "/api/car", {"task": "task1", "uid": "tR1", "different": ["tR1_2.jpg"]})
    assert status == 200 and json.loads(body)["state"] == "split" and json.loads(body)["counts"]["split"] == 1
    assert json.loads(call(base, "/api/session?task=task1")[1])["cars"] == {"open": 1, "checked": 0, "split": 1}
    assert json.loads(call(base, "/api/car?task=task1&uid=tR1")[1])["marked"] == ["tR1_2.jpg"]


# ─── the car folders in the shape the repo's own ReID trainer reads ──────────

def test_reid_export_writes_a_resized_split_copy_with_the_same_cars_in_both_folders(tmp_path):
    from harvest_tool.reid_export import reid_export
    paths = Paths(lab=tmp_path / "lab", backend=tmp_path / "backend")
    images = paths.datasets / "reid" / "images"
    for i in range(12):
        write_img(images / "t1" / "t1_carA" / f"{i:02d}.jpg", 100 + i, 200)        # pictures of any size
    for i in range(5):
        write_img(images / "t2" / "t2_carC" / f"{i}.jpg", 90, 140)
    for i in range(3):
        write_img(images / "t1" / "t1_carB" / f"{i}.jpg", 80, 160)                  # too few pictures to learn from
    for i in range(6):
        write_img(paths.datasets / "reid_public" / "images" / "simveri" / "0001" / f"{i}.jpg", 70, 130)
    before = tree(paths.datasets)

    out = tmp_path / "export"
    r = reid_export(paths, out)
    assert r["cars"] == 2 and r["skipped_cars"] == 1 and r["train"] == 10 + 4 and r["val"] == 2 + 1
    cars_train = sorted(p.name for p in (out / "train").iterdir())
    assert cars_train == sorted(p.name for p in (out / "val").iterdir()) == ["t1_carA", "t2_carC"]   # same cars: class numbers match
    for split in ("train", "val"):
        for f in (out / split).rglob("*.jpg"):
            assert cv2.imread(str(f)).shape[:2] == (128, 64)                         # 128 tall, 64 wide: what train.py needs
    assert (out / "HOW_TO_TRAIN.txt").exists()
    assert tree(paths.datasets) == before                                             # the dataset itself is never touched

    other = reid_export(paths, tmp_path / "export2", include_public=True)
    assert other["cars"] == 3 and (tmp_path / "export2" / "train" / "simveri_0001").exists()


def test_reid_export_refuses_a_busy_folder_or_one_that_lies_in_the_dataset_and_says_nothing_to_export(tmp_path):
    from harvest_tool.reid_export import reid_export
    paths = Paths(lab=tmp_path / "lab", backend=tmp_path / "backend")
    for i in range(6):
        write_img(paths.datasets / "reid" / "images" / "t1" / "t1_car" / f"{i}.jpg", 80, 160)
    (tmp_path / "busy").mkdir()
    (tmp_path / "busy" / "x.txt").write_text("x")
    for bad in (tmp_path / "busy", paths.datasets / "reid" / "images" / "copy", paths.datasets / "reid", paths.datasets):
        with pytest.raises(ValueError):
            reid_export(paths, bad)
    empty = Paths(lab=tmp_path / "lab2", backend=tmp_path / "backend")
    r = reid_export(empty, tmp_path / "nothing")
    assert r["cars"] == 0 and not (tmp_path / "nothing" / "HOW_TO_TRAIN.txt").exists()


def test_the_harvest_command_line_knows_reid_export():
    import subprocess
    r = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / "harvest.py"), "reid-export", "--help"],
                       capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and "--public" in r.stdout and "--val-every" in r.stdout


# ─── "the rest are fine": file every car nobody opened ───────────────────────

def test_the_rest_are_fine_files_every_unopened_car_and_leaves_the_opened_ones_alone(tmp_path):
    from harvest_tool.cars import check_car, fill_cars
    paths = pair_env(tmp_path)
    store = Store(paths)
    check_car(paths, store, "task1", "tA", ["tA_2.jpg"])                    # a person opened this one and found a stranger in it
    done = fill_cars(paths, store, "task1")
    assert done["filled"] == 2 and done["counts"] == {"open": 0, "checked": 2, "split": 1}
    images = paths.datasets / "reid" / "images" / "task1"
    assert [f.name for f in (images / "task1_tA_b").iterdir()] == ["tA_2.jpg"]            # their answer stays
    assert sorted(f.name for f in (images / "task1_tB").iterdir()) == ["tB_0.jpg", "tB_1.jpg", "tB_2.jpg"]
    assert len(list((images / "task1_tC").iterdir())) == 3
    assert fill_cars(paths, store, "task1")["filled"] == 0                                # nothing left to file
    with pytest.raises(KeyError):
        fill_cars(paths, store, "nobody")


def test_the_rest_are_fine_over_the_helper_and_on_the_command_line(server):
    app, base, paths = server
    report = json.loads((paths.forensic / "task1" / "output" / "report.json").read_text())
    report += [car_ticket(paths, "tR1", 11, (0, 0, 200), [0.0, 1.0, 2.0], 100)]
    (paths.forensic / "task1" / "output" / "report.json").write_text(json.dumps(report))
    assert call(base, "/api/cars/fill", {})[0] == 400 and call(base, "/api/cars/fill", {"task": "nobody"})[0] == 400
    assert call(base, "/api/cars/fill", {"task": "a b"})[0] == 400
    status, body, _ = call(base, "/api/cars/fill", {"task": "task1"})
    assert status == 200 and json.loads(body)["filled"] == 2 and json.loads(body)["counts"] == {"open": 0, "checked": 2, "split": 0}
    assert json.loads(call(base, "/api/session?task=task1")[1])["cars"]["checked"] == 2

    import subprocess
    r = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / "harvest.py"), "reid-fill", "--help"],
                       capture_output=True, text=True, timeout=60)
    assert r.returncode == 0 and "--task" in r.stdout
