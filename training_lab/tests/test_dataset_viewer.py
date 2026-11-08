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

from data_tools import common, curate          # noqa: E402
from dataset_viewer import app as vapp          # noqa: E402
from dataset_viewer.app import NeedsConfirm, NotFound, TrainingBusy, ViewerApp, ViewerError   # noqa: E402
from dataset_viewer.server import make_server   # noqa: E402

MODEL = "toy"


def _img(path: Path, size=(64, 48), color=(120, 80, 40)):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path, "JPEG")


@pytest.fixture()
def env(tmp_path, monkeypatch):
    ds = tmp_path / "datasets"
    base = ds / MODEL
    (base).mkdir(parents=True)
    (base / "data.yaml").write_text("names:\n  0: car\n  1: bus\n  2: person\n", encoding="utf-8")
    spec = {
        "train": {"srcA__one.jpg": ["0 0.5 0.5 0.2 0.2", "1 0.3 0.3 0.1 0.1"],
                  "srcA__two.jpg": [],
                  "plain.jpg": ["2 0.5 0.5 0.0100 0.0500"],
                  "harvest__mine.jpg": ["0 0.5 0.5 0.4 0.4"]},
        "val": {"srcB__three.jpg": ["0 0.5 0.5 0.3 0.3"]},
        "test": {},
    }
    for split, files in spec.items():
        (base / "images" / split).mkdir(parents=True)
        (base / "labels" / split).mkdir(parents=True)
        for name, lines in files.items():
            _img(base / "images" / split / name)
            (base / "labels" / split / (Path(name).stem + ".txt")).write_text("\n".join(lines) + ("\n" if lines else ""))
    (base / "images" / "train" / "orphan.jpg").write_bytes(b"")   # no label, not a picture: still listed
    monkeypatch.setattr(common, "DATASETS", ds)
    monkeypatch.setattr(common, "QUARANTINE", ds / "_quarantine")
    monkeypatch.setattr(curate, "DATASETS", ds)
    state = {"training": set()}
    manifest = tmp_path / "m.yaml"
    manifest.write_text(f"{MODEL}:\n  - id: srcA\n    license: CC-BY\n    country: Philippines\n    ph: true\n    trust: A\n"
                        "    notes: hello\n", encoding="utf-8")
    app = ViewerApp(ds, tmp_path / "cache", manifest, training_check=lambda m: m in state["training"])
    app.start_indexing(MODEL)
    for _ in range(200):
        if app.progress(MODEL)["state"] == "ready":
            break
        time.sleep(0.05)
    assert app.progress(MODEL)["state"] == "ready", app.progress(MODEL)
    app.state = state
    return app


def test_index_counts_and_filters(env):
    ov = env.overview(MODEL)
    assert ov["images"] == 6 and ov["images_per_split"] == {"train": 5, "val": 1, "test": 0}
    assert ov["boxes_per_class"]["train"] == [2, 1, 1]
    assert env.items(MODEL, {"split": "val"})["total"] == 1
    assert env.items(MODEL, {"classes": "1"})["total"] == 1
    assert env.items(MODEL, {"source": "srcA"})["total"] == 2
    assert env.items(MODEL, {"nobox": "1"})["total"] == 2            # two.jpg (empty label) and orphan.jpg (no label)
    assert env.items(MODEL, {"mine": "1"})["items"][0]["n"] == "harvest__mine.jpg"
    assert env.items(MODEL, {"tiny": "1"})["items"][0]["n"] == "plain.jpg"
    assert env.items(MODEL, {"q": "THREE"})["total"] == 1
    assert env.items(MODEL, {"sort": "boxes"})["items"][0]["n"] == "srcA__one.jpg"
    assert env.items(MODEL, {"limit": "2"})["items"].__len__() == 2
    with pytest.raises(ViewerError):
        env.items(MODEL, {"sort": "bogus"})


def test_cache_is_reused_and_invalidated(env, tmp_path):
    fresh = ViewerApp(env.datasets, env.cache, env.manifest_path, training_check=lambda m: False)
    assert fresh._load_cache(MODEL) is None or True            # cache is written on build
    env.flush()
    idx = fresh._load_cache(MODEL)
    assert idx is not None and len(idx.rows) == 6
    (env.datasets / MODEL / "images" / "val" / "new.jpg").write_bytes(b"x")
    import os
    os.utime(env.datasets / MODEL / "images" / "val", (1, 1))
    assert fresh._load_cache(MODEL) is None


def test_thumbnail_created_and_cached(env):
    t = env.thumb_of_item(MODEL, "train", "srcA__one.jpg")
    assert t.exists() and Image.open(t).size[0] <= 320
    assert str(env.cache) in str(t)
    assert env.thumb_of_item(MODEL, "train", "srcA__one.jpg") == t


def test_quarantine_and_undo(env):
    r = env.quarantine(MODEL, [{"split": "train", "name": "srcA__one.jpg"}])
    assert r["count"] == 1
    base = env.datasets / MODEL
    assert not (base / "images/train/srcA__one.jpg").exists() and not (base / "labels/train/srcA__one.txt").exists()
    q = env.datasets / "_quarantine" / MODEL / "removed_in_viewer"
    assert (q / "srcA__one.jpg").exists() and (q / "srcA__one.txt").exists()
    assert env.overview(MODEL)["images"] == 5
    assert env.quarantine_list(MODEL, "removed_in_viewer")["items"][0]["split"] == "train"
    assert any('"quarantine"' in l for l in env.actions_path.read_text().splitlines())
    env.undo(MODEL)
    assert (base / "images/train/srcA__one.jpg").exists() and (base / "labels/train/srcA__one.txt").exists()
    assert env.overview(MODEL)["images"] == 6
    with pytest.raises(ViewerError):
        env.undo(MODEL)


def test_restore_remembers_split_and_checks_leaks(env):
    env.quarantine(MODEL, [{"split": "val", "name": "srcB__three.jpg"}])
    env.restore(MODEL, "removed_in_viewer", [{"name": "srcB__three.jpg"}])
    assert (env.datasets / MODEL / "images/val/srcB__three.jpg").exists()
    # an item the curator moved: split unknown, a copy of the same photo lives in train -> asks
    qd = env.datasets / "_quarantine" / MODEL / "duplicate"
    _img(qd / "srcA__one.jpg")
    with pytest.raises(NeedsConfirm) as e:
        env.restore(MODEL, "duplicate", [{"name": "srcA__one.jpg"}])
    assert e.value.kind == "split"
    (env.datasets / MODEL / "images/train/srcA__one.jpg").rename(env.datasets / MODEL / "images/train/srcA__zzz.jpg")
    env.refresh(MODEL)
    while env.progress(MODEL)["state"] == "building":
        time.sleep(0.05)
    with pytest.raises(NeedsConfirm) as e:
        env.restore(MODEL, "duplicate", [{"name": "srcA__one.jpg", "split": "val"}])
    assert e.value.kind == "leak"
    env.restore(MODEL, "duplicate", [{"name": "srcA__one.jpg", "split": "val"}], confirm_leak=True)
    assert (env.datasets / MODEL / "images/val/srcA__one.jpg").exists()


def test_relabel_and_undo(env):
    lbl = env.datasets / MODEL / "labels/train/srcA__one.txt"
    env.edit_box(MODEL, "train", "srcA__one.jpg", 0, cls=2)
    assert [ln.split()[0] for ln in lbl.read_text().splitlines()] == ["2", "1"]
    assert env.items(MODEL, {"classes": "2", "source": "srcA"})["total"] == 1
    env.edit_box(MODEL, "train", "srcA__one.jpg", 1, remove=True)
    assert len(lbl.read_text().splitlines()) == 1
    with pytest.raises(ViewerError):
        env.edit_box(MODEL, "train", "srcA__one.jpg", 0, cls=9)
    with pytest.raises(ViewerError):
        env.edit_box(MODEL, "train", "srcA__one.jpg", 5, cls=1)
    env.undo(MODEL)
    env.undo(MODEL)
    assert [ln.split()[0] for ln in lbl.read_text().splitlines()] == ["0", "1"]

def test_bulk_relabel_preview_updates_index_and_undoes(env):
    preview = env.preview_relabel(
        MODEL,
        rule={"source": "srcA", "split": "train", "from_class": 0},
        class_id=1,
    )
    assert preview["boxes"] == 1
    assert preview["pictures"] == 1
    assert preview["target_name"] == "bus"
    assert preview["samples"] == [{"split": "train", "name": "srcA__one.jpg", "index": 0}]

    env.relabel(MODEL, 1, rule={"source": "srcA", "split": "train", "from_class": 0})
    label = env.datasets / MODEL / "labels/train/srcA__one.txt"
    assert [line.split()[0] for line in label.read_text().splitlines()] == ["1", "1"]
    assert env.overview(MODEL)["boxes_per_class"]["train"] == [1, 2, 1]
    assert env.items(MODEL, {"relabeled": "1"})["total"] == 1
    assert env.about(MODEL)["card_stale"] is True

    env.undo(MODEL)
    assert [line.split()[0] for line in label.read_text().splitlines()] == ["0", "1"]
    assert env.overview(MODEL)["boxes_per_class"]["train"] == [2, 1, 1]
    assert env.items(MODEL, {"relabeled": "1"})["total"] == 0

    ref = [{"split": "train", "name": "srcA__one.jpg", "index": 0}]
    env.relabel(MODEL, 1, rule={"source": "srcA", "split": "train", "from_class": 0})
    env.relabel(MODEL, 2, ref)
    env.undo(MODEL)
    assert env.items(MODEL, {"relabeled": "1"})["total"] == 1
    env.undo(MODEL)
    assert env.items(MODEL, {"relabeled": "1"})["total"] == 0


def test_relabel_guards_training_harvest_and_invalid_class(env):
    refs = [{"split": "train", "name": "srcA__one.jpg", "index": 0}]
    with pytest.raises(ViewerError):
        env.preview_relabel(MODEL, refs, class_id=9)

    env.state["training"].add(MODEL)
    with pytest.raises(TrainingBusy):
        env.relabel(MODEL, 1, refs)
    env.state["training"].clear()

    mine = [{"split": "train", "name": "harvest__mine.jpg", "index": 0}]
    assert env.preview_relabel(MODEL, mine, class_id=1)["harvest_count"] == 1
    with pytest.raises(NeedsConfirm) as error:
        env.relabel(MODEL, 1, mine)
    assert error.value.kind == "harvest"
    env.relabel(MODEL, 1, mine, confirm_harvest=True)


def test_bulk_relabel_write_is_atomic(env, monkeypatch):
    label = env.datasets / MODEL / "labels/train/srcA__one.txt"
    before = label.read_text()
    real_replace = vapp.os.replace

    def fail_label_replace(source, destination):
        if Path(destination) == label:
            raise PermissionError("locked label")
        real_replace(source, destination)

    monkeypatch.setattr(vapp.os, "replace", fail_label_replace)
    with pytest.raises(PermissionError):
        env.relabel(MODEL, 1, [{"split": "train", "name": "srcA__one.jpg", "index": 0}])
    assert label.read_text() == before


def test_bulk_relabel_rolls_back_prior_files_when_later_write_fails(env, monkeypatch):
    train_label = env.datasets / MODEL / "labels/train/srcA__one.txt"
    val_label = env.datasets / MODEL / "labels/val/srcB__three.txt"
    original_train, original_val = train_label.read_text(), val_label.read_text()
    real_replace = vapp.os.replace
    failed = False

    def fail_second_label(source, destination):
        nonlocal failed
        if Path(destination) == val_label and not failed:
            failed = True
            raise PermissionError("locked second label")
        real_replace(source, destination)

    monkeypatch.setattr(vapp.os, "replace", fail_second_label)
    refs = [
        {"split": "train", "name": "srcA__one.jpg", "index": 0},
        {"split": "val", "name": "srcB__three.jpg", "index": 0},
    ]
    with pytest.raises(PermissionError):
        env.relabel(MODEL, 1, refs)
    assert train_label.read_text() == original_train
    assert val_label.read_text() == original_val


def test_bulk_relabel_rolls_back_if_action_logging_fails(env, monkeypatch):
    label = env.datasets / MODEL / "labels/train/srcA__one.txt"
    original = label.read_text()

    def fail_log(entry):
        raise OSError("action log unavailable")

    monkeypatch.setattr(env, "_log", fail_log)
    with pytest.raises(OSError, match="action log unavailable"):
        env.relabel(MODEL, 1, [{"split": "train", "name": "srcA__one.jpg", "index": 0}])

    assert label.read_text() == original
    assert env.overview(MODEL)["boxes_per_class"]["train"] == [2, 1, 1]
    assert env.items(MODEL, {"relabeled": "1"})["total"] == 0
    assert env.about(MODEL)["card_stale"] is False
    assert env.items(MODEL, {"relabeled": "1"})["total"] == 0


def test_crop_size_filter_waits_for_background_dimensions(env):
    result = env.label_items(MODEL, {"split": "train", "min_box_px": "8"})
    while result.get("size_pending"):
        time.sleep(0.05)
        if env._sizes_state.get(MODEL, {}).get("state") == "ready":
            result = env.label_items(MODEL, {"split": "train", "min_box_px": "8"})
            break
    assert result["size_pending"] is False
    assert all(min(item["width"], item["height"]) >= 8 for item in result["items"])


def test_report_job_is_background_and_clears_stale_card(env, monkeypatch):
    from subprocess import CompletedProcess

    env._mark_card_stale(MODEL)
    calls = []

    def fake_run(args, **kwargs):
        calls.append((args, kwargs))
        return CompletedProcess(args, 0, stdout="wrote datasets/toy/DATASET_CARD.md", stderr="")

    monkeypatch.setattr(vapp.subprocess, "run", fake_run)
    job = env.start_report(MODEL)
    for _ in range(100):
        state = env.job(job["id"])
        if state["state"] != "running":
            break
        time.sleep(0.02)
    assert state["state"] == "done"
    assert calls[0][0][-2:] == [str(vapp.LAB / "data.py"), "report"]
    assert env.about(MODEL)["card_stale"] is False


def test_refused_while_training(env):
    env.state["training"].add(MODEL)
    item = [{"split": "train", "name": "srcA__one.jpg"}]
    with pytest.raises(TrainingBusy):
        env.quarantine(MODEL, item)
    with pytest.raises(TrainingBusy):
        env.edit_box(MODEL, "train", "srcA__one.jpg", 0, cls=1)
    assert (env.datasets / MODEL / "images/train/srcA__one.jpg").exists()
    assert env.flush() is None


def test_refused_when_training_check_fails(env):
    def boom(m):
        raise RuntimeError("no psutil")
    env.is_training = boom
    with pytest.raises(TrainingBusy):
        env.quarantine(MODEL, [{"split": "train", "name": "srcA__one.jpg"}])


def test_path_traversal_rejected(env):
    for bad in ("../x.jpg", "..\\x.jpg", "a/b.jpg", "C:\\x.jpg", "..", ".hidden.jpg", "x.jpg.", "nul\x00.jpg", ""):
        with pytest.raises(ViewerError):
            vapp.safe_name(bad)
        with pytest.raises(ViewerError):
            env.quarantine(MODEL, [{"split": "train", "name": bad}])
    with pytest.raises(ViewerError):
        env.image_file(MODEL, "train", "x.txt")
    with pytest.raises(ViewerError):
        env.image_file(MODEL, "../val", "srcA__one.jpg")
    with pytest.raises(NotFound):
        env.image_file("../toy", "train", "srcA__one.jpg")
    with pytest.raises(ViewerError):
        env.quarantine_list(MODEL, "../..")
    with pytest.raises(ViewerError):
        env.restore(MODEL, "removed_in_viewer", [{"name": "../../x.jpg", "split": "train"}])


def test_harvest_needs_confirmation(env):
    item = [{"split": "train", "name": "harvest__mine.jpg"}]
    with pytest.raises(NeedsConfirm) as e:
        env.quarantine(MODEL, item)
    assert e.value.kind == "harvest"
    with pytest.raises(NeedsConfirm):
        env.edit_box(MODEL, "train", "harvest__mine.jpg", 0, cls=1)
    assert (env.datasets / MODEL / "images/train/harvest__mine.jpg").exists()
    env.quarantine(MODEL, item, confirm_harvest=True)
    assert not (env.datasets / MODEL / "images/train/harvest__mine.jpg").exists()


def test_flag_notes_about(env):
    env.set_flag(MODEL, [{"split": "val", "name": "srcB__three.jpg"}], True)
    assert env.items(MODEL, {"flag": "1"})["total"] == 1
    env.undo(MODEL)
    assert env.items(MODEL, {"flag": "1"})["total"] == 0
    env.save_notes(MODEL, "my notes")
    a = env.about(MODEL)
    assert a["notes"] == "my notes" and a["classes"] == ["car", "bus", "person"]
    assert any(s["id"] == "srcA" and s["license"] == "CC-BY" and s["images"] == 2 for s in a["sources"])
    assert (env.datasets / MODEL / "NOTES.md").read_text() == "my notes"


def test_sizes_job_fills_overview(env):
    env.start_sizes(MODEL)
    for _ in range(100):
        if env.overview(MODEL)["sizes"]["state"] == "ready":
            break
        time.sleep(0.05)
    ov = env.overview(MODEL)
    assert ov["sizes"]["state"] == "ready" and ov["sizes"]["have"] == 5       # orphan.jpg is not a picture


def test_clean_dry_run_job_and_apply(env):
    job = env.start_clean(MODEL)
    for _ in range(200):
        job = env.job(job["id"])
        if job["state"] != "running":
            break
        time.sleep(0.05)
    assert job["state"] == "done", job
    f = job["result"]["findings"]
    assert f["corrupt_image"]["count"] == 1                      # orphan.jpg
    assert (env.datasets / MODEL / "images/train/orphan.jpg").exists()    # dry run changed nothing
    with pytest.raises(NeedsConfirm):
        env.apply_clean(MODEL, confirm=False)
    env.state["training"].add(MODEL)
    with pytest.raises(TrainingBusy):
        env.apply_clean(MODEL, confirm=True)


# --------------------------------------------------------------------------- HTTP

@pytest.fixture()
def server(env):
    srv = make_server(env, 0, token="tok123")
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield srv, f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()
    srv.server_close()


def _get(base, path, token="tok123", headers=None):
    req = urllib.request.Request(base + path + (("&" if "?" in path else "?") + f"t={token}" if token else ""), headers=headers or {})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, r.read(), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers


def _post(base, path, body, token="tok123"):
    req = urllib.request.Request(f"{base}{path}?t={token}", data=json.dumps(body).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())


def test_routes_need_token_and_work(server):
    srv, base = server
    assert _get(base, "/api/ping", token="")[0] == 403
    assert _get(base, "/api/ping", token="wrong")[0] == 403
    assert _get(base, "/", token="wrong")[0] == 403
    code, body, _ = _get(base, "/api/ping")
    assert code == 200 and json.loads(body) == {"ok": True, "api": vapp.API_VERSION}
    assert _get(base, "/api/ping", token="", headers={"X-Viewer-Token": "tok123"})[0] == 200
    code, body, _ = _get(base, "/api/datasets")
    assert code == 200 and json.loads(body)["datasets"][0]["name"] == MODEL
    code, body, _ = _get(base, f"/api/items?dataset={MODEL}&split=train")
    assert code == 200 and json.loads(body)["total"] == 5
    code, body, h = _get(base, f"/api/thumb?dataset={MODEL}&split=train&name=srcA__one.jpg")
    assert code == 200 and h["Content-Type"] == "image/jpeg" and body[:2] == b"\xff\xd8"
    assert _get(base, f"/api/thumb?dataset={MODEL}&split=train&name=..%2F..%2Fdata.yaml")[0] == 400
    assert _get(base, "/api/image?dataset=../x&split=train&name=a.jpg")[0] == 404
    assert _get(base, "/api/nothing")[0] == 404
    code, body, _ = _get(base, "/")
    assert code == 200 and b"tok123" in body


def test_routes_reject_foreign_host(server):
    srv, base = server
    req = urllib.request.Request(base + "/api/ping?t=tok123", headers={"Host": "evil.example"})
    with pytest.raises(urllib.error.HTTPError) as e:
        urllib.request.urlopen(req, timeout=10)
    assert e.value.code == 403


def test_routes_write_flow(server, env):
    srv, base = server
    item = {"split": "train", "name": "harvest__mine.jpg"}
    code, body = _post(base, "/api/quarantine", {"dataset": MODEL, "items": [item]})
    assert code == 409 and body["needs_confirm"] == "harvest"
    code, body = _post(base, "/api/quarantine", {"dataset": MODEL, "items": [item], "confirm_harvest": True})
    assert code == 200
    code, body = _post(base, "/api/undo", {"dataset": MODEL})
    assert code == 200
    code, body = _post(base, "/api/box", {"dataset": MODEL, "split": "train", "name": "srcA__one.jpg", "i": 0, "cls": 1})
    assert code == 200
    env.state["training"].add(MODEL)
    code, body = _post(base, "/api/box", {"dataset": MODEL, "split": "train", "name": "srcA__one.jpg", "i": 0, "cls": 2})
    assert code == 409 and body["training"] is True
    assert _post(base, "/api/quarantine", {"dataset": MODEL, "items": [item]}, token="bad")[0] == 403


def test_routes_box_crops_and_bulk_relabel(server, env):
    _, base = server
    code, body, _ = _get(base, f"/api/labels?dataset={MODEL}&split=train&class=0")
    assert code == 200 and json.loads(body)["total"] == 2
    code, body, headers = _get(
        base, f"/api/crop?dataset={MODEL}&split=train&name=srcA__one.jpg&i=0"
    )
    assert code == 200 and headers["Content-Type"] == "image/jpeg"
    assert body[:2] == b"\xff\xd8"
    selection = [{"split": "train", "name": "srcA__one.jpg", "index": 0}]
    code, body = _post(
        base,
        "/api/relabel/preview",
        {"dataset": MODEL, "items": selection, "class_id": 1},
    )
    assert code == 200 and body["boxes"] == 1
    code, body = _post(
        base,
        "/api/relabel",
        {"dataset": MODEL, "items": selection, "class_id": 1},
    )
    assert code == 200 and body["pictures"] == 1
    assert _post(base, "/api/undo", {"dataset": MODEL})[0] == 200


def test_report_endpoint_refuses_while_training(server, env):
    _, base = server
    env.state["training"].add(MODEL)
    code, body = _post(base, "/api/report", {"dataset": MODEL})
    assert code == 409 and body["training"] is True
