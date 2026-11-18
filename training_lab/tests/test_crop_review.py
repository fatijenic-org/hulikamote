"""
Quick box review in the Dataset Viewer: add a class, decide a page of boxes, remember what was looked at, undo, put the decisions
back after a re-merge, and rank the unlooked boxes by a small classifier (never applied by itself). Temporary folders only.

    hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests/test_crop_review.py -q -p no:cacheprovider
"""
import sys
import time
from pathlib import Path

import numpy as np
import pytest
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from data_tools import common, curate, decisions    # noqa: E402,F401
from dataset_viewer import suggest                    # noqa: E402
from dataset_viewer.app import NeedsConfirm, TrainingBusy, ViewerApp, ViewerError   # noqa: E402

MODEL = "toy"
TRUCK, CAR = 1, 0
RED, BLUE = (220, 30, 30), (30, 30, 220)


def make_app(tmp_path, monkeypatch, pictures, training=None):
    """pictures: {split: [(name, [label lines], colour)]}"""
    ds = tmp_path / "datasets"
    base = ds / MODEL
    base.mkdir(parents=True)
    (base / "data.yaml").write_text("nc: 3\nnames:\n  0: car\n  1: truck\n  2: person\ntest: images/test\n", encoding="utf-8")
    for split, files in pictures.items():
        (base / "images" / split).mkdir(parents=True)
        (base / "labels" / split).mkdir(parents=True)
        for name, lines, colour in files:
            Image.new("RGB", (64, 48), colour).save(base / "images" / split / name, "JPEG")
            (base / "labels" / split / (Path(name).stem + ".txt")).write_text("\n".join(lines) + "\n")
    monkeypatch.setattr(common, "DATASETS", ds)
    monkeypatch.setattr(common, "QUARANTINE", ds / "_quarantine")
    monkeypatch.setattr(curate, "DATASETS", ds)
    state = training if training is not None else {"on": False}
    app = ViewerApp(ds, tmp_path / "cache", tmp_path / "m.yaml", training_check=lambda m: state["on"])
    app.state = state
    app.start_indexing(MODEL)
    for _ in range(200):
        if app.progress(MODEL)["state"] == "ready":
            break
        time.sleep(0.05)
    assert app.progress(MODEL)["state"] == "ready"
    return app


TRUCK_BOX = "1 0.5 0.5 0.4 0.4"


@pytest.fixture()
def app(tmp_path, monkeypatch):
    return make_app(tmp_path, monkeypatch, {
        "train": [("srcA__a1.jpg", [TRUCK_BOX, "0 0.2 0.2 0.1 0.1"], BLUE), ("srcA__a2.jpg", [TRUCK_BOX], BLUE),
                  ("srcA__a3.jpg", [TRUCK_BOX], BLUE), ("harvest__mine.jpg", [TRUCK_BOX], BLUE)],
        "val": [("srcB__v1.jpg", [TRUCK_BOX], BLUE)],
        "test": [("srcB__t1.jpg", [TRUCK_BOX], BLUE)],
    })


def refs(app, cls=TRUCK, names=None, **q):
    items = app.label_items(MODEL, {"class": str(cls), "limit": "200", **q})["items"]
    return [{"split": i["split"], "name": i["name"], "index": i["index"]} for i in items if names is None or i["name"] in names]


def label_of(app, split, name):
    return [b[0] for b in common.read_yolo(app.datasets / MODEL / "labels" / split / (Path(name).stem + ".txt"))]


# --- add a class ---------------------------------------------------------------

def test_adding_the_class_gives_it_the_next_number_and_keeps_the_old_ones(app):
    out = app.add_class(MODEL, "pickup")
    assert out["added"] and out["class_id"] == 3 and out["classes"] == ["car", "truck", "person", "pickup"]
    assert app.label_items(MODEL, {"class": "3"})["total"] == 0                   # the new class is accepted by the filters at once
    assert label_of(app, "train", "srcA__a1.jpg") == [1, 0]                       # labels untouched
    assert app.add_class(MODEL, "pickup")["added"] is False                       # safe to repeat


def test_adding_a_class_is_refused_while_the_model_trains(app):
    app.state["on"] = True
    with pytest.raises(TrainingBusy):
        app.add_class(MODEL, "pickup")
    assert "pickup" not in (app.datasets / MODEL / "data.yaml").read_text()


def test_a_bad_class_name_is_a_plain_error(app):
    with pytest.raises(ViewerError):
        app.add_class(MODEL, "Pick Up")


# --- deciding a page -------------------------------------------------------------

def test_picked_boxes_become_pickups_the_rest_of_the_page_is_remembered_as_looked_at(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"srcA__a1.jpg", "srcA__a2.jpg", "srcA__a3.jpg", "srcB__v1.jpg", "srcB__t1.jpg"})
    picked = [r for r in page if r["name"] in ("srcA__a1.jpg", "srcB__v1.jpg", "srcB__t1.jpg")]   # val and test too
    out = app.decide(MODEL, 3, TRUCK, picked, page)
    assert out["moved"] == 3 and out["kept"] == 2
    assert label_of(app, "train", "srcA__a1.jpg") == [3, 0]                       # the car next to it is untouched
    assert label_of(app, "val", "srcB__v1.jpg") == [3] and label_of(app, "test", "srcB__t1.jpg") == [3]
    assert label_of(app, "train", "srcA__a2.jpg") == [1]                          # looked at, still a truck
    assert out["review"]["reviewed"] == 5 and out["review"]["moved"] == 3 and out["review"]["total"] == 6


def test_reviewed_boxes_do_not_come_back_but_stay_findable(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"srcA__a1.jpg", "srcA__a2.jpg"})
    app.decide(MODEL, 3, TRUCK, [page[0]], page)
    left = app.label_items(MODEL, {"class": str(TRUCK), "unreviewed": "1", "limit": "50"})
    assert {i["name"] for i in left["items"]} == {"srcA__a3.jpg", "harvest__mine.jpg", "srcB__v1.jpg", "srcB__t1.jpg"}
    everything = app.label_items(MODEL, {"class": str(TRUCK), "limit": "50"})
    assert next(i for i in everything["items"] if i["name"] == "srcA__a2.jpg")["decision"] == "keep"
    assert everything["review"]["reviewed"] == 2


def test_a_page_with_no_pickups_is_a_decision_too_and_undo_takes_it_back(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"srcA__a1.jpg", "srcA__a2.jpg"})
    out = app.decide(MODEL, 3, TRUCK, [], page)
    assert out["moved"] == 0 and out["kept"] == 2
    assert app.review_counts(MODEL, TRUCK)["reviewed"] == 2
    app.undo(MODEL)
    assert app.review_counts(MODEL, TRUCK)["reviewed"] == 0


def test_undo_takes_back_the_labels_and_the_journal_together(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"srcA__a1.jpg", "srcA__a2.jpg"})
    app.decide(MODEL, 3, TRUCK, [page[0]], page)
    app.undo(MODEL)
    assert label_of(app, "train", "srcA__a1.jpg") == [1, 0]
    assert app.review_counts(MODEL, TRUCK) == {"class": "truck", "class_id": 1, "reviewed": 0, "moved": 0, "kept": 0, "total": 6}


def test_a_stale_page_is_safe_boxes_that_changed_class_are_not_touched(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"srcA__a1.jpg", "srcA__a2.jpg"})
    app.edit_box(MODEL, "train", "srcA__a2.jpg", 0, cls=0)                        # meanwhile it became a car
    out = app.decide(MODEL, 3, TRUCK, page, page)
    assert out["moved"] == 1 and label_of(app, "train", "srcA__a2.jpg") == [0]


def test_your_own_harvest_pictures_need_the_extra_yes_and_nothing_is_written_without_it(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"harvest__mine.jpg", "srcA__a2.jpg"})
    with pytest.raises(NeedsConfirm):
        app.decide(MODEL, 3, TRUCK, page, page)
    assert app.review_counts(MODEL, TRUCK)["reviewed"] == 0 and label_of(app, "train", "harvest__mine.jpg") == [1]
    assert app.decide(MODEL, 3, TRUCK, page, page, confirm_harvest=True)["moved"] == 2


def test_nothing_is_decided_while_the_model_trains(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"srcA__a1.jpg"})
    app.state["on"] = True
    with pytest.raises(TrainingBusy):
        app.decide(MODEL, 3, TRUCK, page, page)
    assert app.review_counts(MODEL, TRUCK)["reviewed"] == 0


def test_bad_requests_are_plain_errors(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"srcA__a1.jpg"})
    bad_box = [{"split": "train", "name": "nope.jpg", "index": 0}]
    for args in ((3, 3, page, page), (9, TRUCK, page, page), (3, TRUCK, [], []), (3, TRUCK, bad_box, [])):
        with pytest.raises(Exception) as e:
            app.decide(MODEL, *args)
        assert isinstance(e.value, (ViewerError, KeyError))


# --- the journal survives a re-merge -----------------------------------------------

def test_reapply_puts_the_pickups_back_after_the_label_files_were_rewritten(app):
    app.add_class(MODEL, "pickup")
    page = refs(app, names={"srcA__a1.jpg", "srcA__a2.jpg", "srcB__v1.jpg"})
    app.decide(MODEL, 3, TRUCK, [page[0], page[2]], page)
    for split, name in (("train", "srcA__a1.jpg"), ("val", "srcB__v1.jpg")):        # a re-merge: the source labels come back
        (app.datasets / MODEL / "labels" / split / (Path(name).stem + ".txt")).write_text(
            TRUCK_BOX + "\n" + ("0 0.2 0.2 0.1 0.1\n" if name == "srcA__a1.jpg" else ""))
    (app.datasets / MODEL / "data.yaml").write_text("nc: 3\nnames:\n  0: car\n  1: truck\n  2: person\n", encoding="utf-8")   # the class went too
    app.refresh(MODEL)
    for _ in range(200):
        if app.progress(MODEL)["state"] == "ready":
            break
        time.sleep(0.05)
    out = app.reapply_decisions(MODEL)
    assert out["applied"] == 2 and out["class_id"] == 3
    assert label_of(app, "train", "srcA__a1.jpg") == [3, 0] and label_of(app, "val", "srcB__v1.jpg") == [3]
    assert app.label_items(MODEL, {"class": "3"})["total"] == 2                    # the viewer sees them without a restart
    assert app.reapply_decisions(MODEL)["applied"] == 0                            # safe to repeat


def test_reapply_is_refused_while_the_model_trains(app):
    app.add_class(MODEL, "pickup")
    app.state["on"] = True
    with pytest.raises(TrainingBusy):
        app.reapply_decisions(MODEL)


# --- suggestions ---------------------------------------------------------------------

def colour_embedder(paths, progress):
    """A stand-in for the car matcher's network: a picture's colour is its fingerprint (red = pickup, blue = truck)."""
    out = []
    for n, p in enumerate(paths, 1):
        with Image.open(p) as im:
            r, g, b = np.asarray(im.convert("RGB").resize((4, 4))).reshape(-1, 3).mean(axis=0) / 255.0
        v = np.zeros(512, dtype="float32")
        v[:3] = (r, g, b)
        out.append(v / np.linalg.norm(v))
        progress(n, len(paths))
    return np.array(out)


@pytest.fixture()
def many(tmp_path, monkeypatch):
    pics = []
    for i in range(260):                              # 130 red + 130 blue to mark, then 40 unlooked (20 red, 20 blue)
        pics.append((f"srcA__m{i:04d}.jpg", [TRUCK_BOX], RED if i % 2 == 0 else BLUE))
    for i in range(40):
        pics.append((f"srcA__u{i:04d}.jpg", [TRUCK_BOX], RED if i % 2 == 0 else BLUE))
    app = make_app(tmp_path, monkeypatch, {"train": pics})
    app.add_class(MODEL, "pickup")
    app._suggester = suggest.Suggester(app, embed_fn=colour_embedder)
    return app


def mark(app):
    while True:                                               # page after page, like the person does (a page holds at most 200)
        page = [r for r in refs(app, unreviewed="1") if r["name"].startswith("srcA__m")]
        if not page:
            return
        red = [r for r in page if int(r["name"][-8:-4]) % 2 == 0]
        app.decide(MODEL, 3, TRUCK, red, page)


def test_suggestions_need_enough_marked_boxes_first(many):
    with pytest.raises(ViewerError) as e:
        many.suggester.start(MODEL, "truck", wait=True)
    assert "100" in str(e.value)
    assert many.suggester.status(MODEL, "truck")["can_start"] is False


def test_suggestions_rank_the_unlooked_boxes_and_never_change_a_label(many):
    mark(many)
    st = many.suggester.start(MODEL, "truck", wait=True)
    assert st["state"] == "ready" and st["accuracy"] >= 0.95 and st["scored"] == 40
    before = {p.name: p.read_text() for p in (many.datasets / MODEL / "labels" / "train").glob("srcA__u*.txt")}
    out = many.label_items(MODEL, {"class": str(TRUCK), "order": "suggest", "unreviewed": "1", "limit": "40"})
    names = [i["name"] for i in out["items"]]
    assert all(int(n[-8:-4]) % 2 == 0 for n in names[:20]) and all(int(n[-8:-4]) % 2 == 1 for n in names[20:])   # red ones first
    assert out["items"][0]["score"] > 0.9 > 0.1 > out["items"][-1]["score"]
    after = {p.name: p.read_text() for p in (many.datasets / MODEL / "labels" / "train").glob("srcA__u*.txt")}
    assert before == after                                                         # a suggestion is only an order


def test_suggestions_are_asked_for_only_after_a_run_and_survive_a_restart(many):
    mark(many)
    with pytest.raises(ViewerError):
        many.label_items(MODEL, {"class": str(TRUCK), "order": "suggest"})
    many.suggester.start(MODEL, "truck", wait=True)
    fresh = suggest.Suggester(many)                                                # a new helper reads what was saved
    assert len(fresh.scores(MODEL, "truck")) == 40 and fresh.status(MODEL)["state"] == "ready"


def test_a_failing_picture_reader_is_explained_not_a_crash(many):
    mark(many)

    def broken(paths, progress):
        raise RuntimeError("the reader stopped")
    many._suggester = suggest.Suggester(many, embed_fn=broken)
    st = many.suggester.start(MODEL, "truck", wait=True)
    assert st["state"] == "error" and "reader stopped" in st["error"]


def test_the_classifier_alone_separates_two_clouds_of_points():
    rng = np.random.default_rng(1)
    X = np.concatenate([rng.normal(1, 0.3, (60, 8)), rng.normal(-1, 0.3, (60, 8))])
    y = np.array([1] * 60 + [0] * 60, dtype="float64")
    w, b = suggest.fit_logistic(X, y)
    p = suggest.predict(X, w, b)
    assert ((p >= 0.5) == (y == 1)).all()


# --- the routes ------------------------------------------------------------------------

def test_the_routes_work_end_to_end(app):
    import json
    import threading
    import urllib.error
    import urllib.request
    from dataset_viewer.server import make_server
    srv = make_server(app, 0, token="tok")
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = f"http://127.0.0.1:{srv.server_address[1]}"

    def call(method, path, body=None):
        req = urllib.request.Request(f"{base}{path}{'&' if '?' in path else '?'}t=tok", method=method,
                                     data=None if body is None else json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    try:
        assert call("GET", "/api/ping")[1]["api"] >= 2
        assert call("POST", "/api/class/add", {"dataset": MODEL, "name": "Pick Up"})[0] == 400
        code, out = call("POST", "/api/class/add", {"dataset": MODEL, "name": "pickup"})
        assert code == 200 and out["class_id"] == 3
        code, out = call("GET", f"/api/review?dataset={MODEL}")
        assert code == 200 and out["target_id"] == 3 and out["counts"]["truck"]["total"] == 6
        code, out = call("GET", f"/api/labels?dataset={MODEL}&class=1&unreviewed=1&limit=3")
        assert code == 200 and len(out["items"]) == 3 and out["review"]["reviewed"] == 0
        picked = [{k: i[k] for k in ("split", "name", "index")} for i in out["items"][:1]]
        page = [{k: i[k] for k in ("split", "name", "index")} for i in out["items"]]
        code, res = call("POST", "/api/decide", {"dataset": MODEL, "to_class": 3, "from_class": 1, "picked": picked, "page": page,
                                                  "confirm_harvest": True})
        assert code == 200 and res["moved"] == 1 and res["kept"] == 2
        assert call("POST", "/api/decide", {"dataset": MODEL, "to_class": 1, "from_class": 1, "picked": picked})[0] == 400
        assert call("GET", f"/api/review?dataset={MODEL}")[1]["counts"]["truck"]["reviewed"] == 3
        code, out = call("GET", f"/api/suggest?dataset={MODEL}&class=1")
        assert code == 200 and out["can_start"] is False and out["min_each"] == 100
        assert call("POST", "/api/suggest/start", {"dataset": MODEL, "from_class": 1})[0] == 400      # too few marked
        assert call("POST", "/api/undo", {"dataset": MODEL})[0] == 200
        assert call("GET", f"/api/review?dataset={MODEL}")[1]["counts"]["truck"]["reviewed"] == 0
        assert call("POST", "/api/decisions/reapply", {"dataset": MODEL})[1]["applied"] == 0
        app.state["on"] = True
        assert call("POST", "/api/decisions/reapply", {"dataset": MODEL})[0] == 409
    finally:
        srv.shutdown()
        srv.server_close()
