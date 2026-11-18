"""
Send each picture right away: with it on, a picture is written to the dataset and moved the moment a person finishes it,
instead of waiting for the "Build the dataset" button. Temporary folders only.

    hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests/test_live_send.py -q -p no:cacheprovider
"""
import json
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from harvest_tool import folder_labeller as fl           # noqa: E402
from harvest_tool.web import HarvestApp                  # noqa: E402
from test_folder_labeller import env, write_img          # noqa: E402,F401  (env is a fixture)


def start(env_, tmp_path, model="plate_specialist"):
    paths, store, evidence = env_
    app = HarvestApp(paths, store)
    r = fl.scan(paths, store, model, evidence)
    dest = tmp_path / "out"
    app.labeller_live(model, r["task"], str(dest))
    return app, store, r["task"], dest / model


def waiting(store, task, model="plate_specialist"):
    return store.items(model, ("label",), task=task)


def test_a_finished_picture_is_in_the_dataset_at_once_and_gone_from_the_folder(env, tmp_path):
    app, store, task, out = start(env, tmp_path)
    item = waiting(store, task)[0]
    src = Path(item.src_path)
    app.save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]])
    assert not src.exists()                                              # moved right away
    saved = [p for s in ("train", "val") for p in (out / "images" / s).glob(src.name)]
    assert len(saved) == 1
    label = out / "labels" / saved[0].parent.name / (src.stem + ".txt")
    assert label.read_text().startswith("0 ")
    assert store.get(item.id).state == "accepted"                        # nothing is left for the Build button
    assert len(waiting(store, task)) == 6                                # the other six are still waiting


def test_nothing_here_is_sent_as_an_empty_label_and_blur_is_applied(env, tmp_path):
    app, store, task, out = start(env, tmp_path)
    items = waiting(store, task)
    app.save(items[0].id, [])
    app.save(items[1].id, [], [[0, 0.5, 0.5, 0.4, 0.4]])
    sent = sorted((out / "labels").rglob("*.txt"))
    assert len(sent) == 2 and all(p.read_text() == "" for p in sent)     # empty labels, blur is not a label
    summary = app.labeller_live("plate_specialist", task, "")["summary"]
    assert summary["exported"] == 2 and summary["empty_labels"] == 2 and summary["blurred_pictures"] == 1


def test_not_sure_is_not_sent(env, tmp_path):
    app, store, task, out = start(env, tmp_path)
    item = waiting(store, task)[0]
    app.skip(item.id)
    assert Path(item.src_path).exists() and not list((out / "images").rglob("*.jpg"))


def test_turning_it_off_gives_the_totals_writes_the_report_and_stops_sending(env, tmp_path):
    app, store, task, out = start(env, tmp_path)
    items = waiting(store, task)
    app.save(items[0].id, [[0, 0.5, 0.5, 0.3, 0.2]])
    off = app.labeller_live("plate_specialist", task, "")
    assert off["live"] is False and off["summary"]["exported"] == 1
    assert json.loads((out / "report.json").read_text())["exported"] == 1
    app.save(items[1].id, [[0, 0.5, 0.5, 0.3, 0.2]])                     # off now: finished, but not sent
    assert Path(items[1].src_path).exists() and store.get(items[1].id).state == "ready"


def test_the_picture_can_still_be_shown_after_it_was_sent(env, tmp_path):
    app, store, task, out = start(env, tmp_path)
    item = waiting(store, task)[0]
    app.save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]])
    assert store.image_path("plate_specialist", item.id).exists() or not Path(item.src_path).exists()
    # the labelling screen's own link stays, so going back one picture still shows it
    fl.prepare(store, [store.get(item.id)])
    assert store.image_path("plate_specialist", item.id).exists()


def test_a_copy_of_a_picture_already_sent_is_counted_not_written_twice(env, tmp_path):
    paths, store, evidence = env
    app, store, task, out = start(env, tmp_path)
    first = waiting(store, task)[0]
    shutil.copy2(first.src_path, evidence / "twin.jpg")                  # the very same picture under another name
    r = fl.scan(paths, store, "plate_specialist", evidence)
    app.save(first.id, [[0, 0.5, 0.5, 0.3, 0.2]])
    twin_item = next(i for i in waiting(store, task) if i.src_path.endswith("twin.jpg"))
    app.save(twin_item.id, [[0, 0.5, 0.5, 0.3, 0.2]])
    assert Path(twin_item.src_path).exists()                             # the copy stays in the folder
    assert app.labeller_live("plate_specialist", task, "")["summary"]["duplicates"] == 1


def test_a_bad_destination_is_refused_before_anything_is_sent(env, tmp_path):
    paths, store, evidence = env
    app = HarvestApp(paths, store)
    r = fl.scan(paths, store, "plate_specialist", evidence)
    with pytest.raises(ValueError):
        app.labeller_live("plate_specialist", r["task"], str(evidence / "inside"))      # inside the folder being labelled
    with pytest.raises(ValueError):
        app.labeller_live("plate_specialist", r["task"], "relative/path")
    item = waiting(store, r["task"])[0]
    app.save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]])
    assert Path(item.src_path).exists()                                  # nothing was sending


def test_sending_is_per_folder_and_per_model(env, tmp_path):
    paths, store, evidence = env
    app = HarvestApp(paths, store)
    r = fl.scan(paths, store, "plate_specialist", evidence)
    other = fl.scan(paths, store, "helmet_specialist", evidence)
    app.labeller_live("plate_specialist", r["task"], str(tmp_path / "out"))
    h = store.items("helmet_specialist", ("label",), task=other["task"])[0]
    app.save(h.id, [[0, 0.5, 0.5, 0.3, 0.2]])
    assert Path(h.src_path).exists()                                     # the helmet pictures were not sent


def test_copying_keeps_the_original_for_other_models_and_this_model_does_not_ask_again(env, tmp_path):
    paths, store, evidence = env
    app = HarvestApp(paths, store)
    r = fl.scan(paths, store, "plate_specialist", evidence)
    app.labeller_live("plate_specialist", r["task"], str(tmp_path / "out"), move=False)
    item = waiting(store, r["task"])[0]
    app.save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]], [[0, 0.5, 0.5, 0.2, 0.2]])         # even with blur: the original keeps its faces
    assert Path(item.src_path).exists()
    assert len(list((tmp_path / "out" / "plate_specialist" / "images").rglob("*.jpg"))) == 1
    assert store.get(item.id).state == "accepted"
    # another model still sees the picture; the same model finds it already labelled
    other = fl.scan(paths, store, "helmet_specialist", evidence)
    assert other["already_labelled"] == 0 and other["new"] == other["found"]
    again = fl.scan(paths, store, "plate_specialist", evidence)
    assert again["already_labelled"] >= 1
    assert app.labeller_live("plate_specialist", r["task"], "")["summary"]["moved"] is False
