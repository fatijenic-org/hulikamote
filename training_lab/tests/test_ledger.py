"""
The labelled ledger: a record, outside the inbox database, of which pictures are already labelled for which model.
Temporary folders only (the real ledger is never touched).

    hulikamote_backend/venv/Scripts/python.exe -m pytest training_lab/tests/test_ledger.py -q -p no:cacheprovider
"""
import gc
import json
import shutil
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from harvest_tool import folder_labeller as fl           # noqa: E402
from harvest_tool import ledger                          # noqa: E402
from harvest_tool.store import Store                     # noqa: E402
from harvest_tool.web import HarvestApp                  # noqa: E402
from test_folder_labeller import env, label_all, write_img  # noqa: E402,F401  (env is a fixture)


def lines(file: Path) -> list[dict]:
    return [json.loads(x) for x in file.read_text(encoding="utf-8").splitlines() if x.strip()]


def first_item(store, task):
    return store.items("plate_specialist", ("label",), task=task)[0]


def test_saving_a_picture_writes_a_ledger_line_outside_the_inbox(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    item = first_item(store, r["task"])
    HarvestApp(paths, store).save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]], [[0, 0.2, 0.2, 0.1, 0.1]])
    file = ledger.ledger_file(paths, "plate_specialist")
    assert file.parent == paths.lab / "labelled_ledger" and not str(file).startswith(str(paths.inbox))
    (entry,) = lines(file)
    assert entry["status"] == "labelled" and entry["labels"] == 1 and entry["blur"] == 1
    assert entry["name"] == Path(item.src_path).name and entry["sha1"] == ledger.digest(item.src_path)


def test_not_sure_is_not_recorded(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    HarvestApp(paths, store).skip(first_item(store, r["task"]).id)
    assert not ledger.ledger_file(paths, "plate_specialist").exists()


def test_a_renamed_copy_of_a_labelled_picture_is_left_out_of_the_next_scan(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    item = first_item(store, r["task"])
    HarvestApp(paths, store).save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]])
    other = tmp_path / "elsewhere"
    other.mkdir()
    shutil.copy2(item.src_path, other / "renamed_by_hand.jpg")
    write_img(other / "new_one.jpg", seed=99)
    r2 = fl.scan(paths, store, "plate_specialist", other)
    assert r2["found"] == 2 and r2["already_labelled"] == 1 and r2["new"] == 1


def test_labelled_for_one_model_is_not_hidden_from_another(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    item = first_item(store, r["task"])
    HarvestApp(paths, store).save(item.id, [[0, 0.5, 0.5, 0.3, 0.2]])
    r2 = fl.scan(paths, store, "helmet_specialist", evidence)
    assert r2["already_labelled"] == 0


def test_the_mark_survives_losing_the_inbox(env):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    HarvestApp(paths, store).save(first_item(store, r["task"]).id, [[0, 0.5, 0.5, 0.3, 0.2]])
    total = r["found"]
    del store
    gc.collect()                                       # let go of the database file (Windows keeps it locked)
    shutil.rmtree(paths.inbox)                         # the work area is cleaned
    fresh = Store(paths)
    r2 = fl.scan(paths, fresh, "plate_specialist", evidence)
    assert r2["already_labelled"] == 1 and r2["new"] == total - 1


def test_export_records_each_picture_centrally_and_beside_the_dataset_blurred_copy_too(env, tmp_path):
    paths, store, evidence = env
    r = fl.scan(paths, store, "plate_specialist", evidence)
    items = store.items("plate_specialist", ("label",), task=r["task"])
    store.save_boxes(items[0].id, [[0, 0.5, 0.5, 0.3, 0.3]], [[0, 0.3, 0.3, 0.2, 0.2]])      # this one is blurred
    store.save_boxes(items[1].id, [[0, 0.5, 0.5, 0.3, 0.3]])
    out = fl.export(paths, store, "plate_specialist", r["task"], tmp_path / "out")
    assert out["exported"] == 2
    central = lines(ledger.ledger_file(paths, "plate_specialist"))
    beside = lines(tmp_path / "out" / "plate_specialist" / ledger.COPY_NAME)
    assert len(beside) == 3 and len(central) == 3                       # 2 originals + the blurred copy (a different file)
    assert {e["status"] for e in central} == {"exported"} and all(e["moved_to"] for e in central)
    # after the move, scanning the destination images recognises them: nothing is queued twice
    r2 = fl.scan(paths, store, "plate_specialist", tmp_path / "out" / "plate_specialist" / "images")
    assert r2["already_labelled"] == 2 and r2["new"] == 0


def test_a_broken_ledger_line_is_ignored(env):
    paths, store, evidence = env
    file = ledger.ledger_file(paths, "plate_specialist")
    file.parent.mkdir(parents=True)
    file.write_text('not json\n{"sha1": "abc", "size": 3}\n', encoding="utf-8")
    assert list(ledger.load(paths, "plate_specialist")) == ["abc"]
