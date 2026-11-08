"""engine/reid_dataset.py - review decisions saved as ReID training photos."""


def test_reid_record_saves_crops_per_identity(tmp_path, monkeypatch):
    import json
    from engine import reid_dataset
    monkeypatch.setattr(reid_dataset, "REID_DIR", tmp_path / "reid")
    ev = tmp_path / "ev"
    ev.mkdir()
    (ev / "a_crop.jpg").write_bytes(b"x")
    (ev / "b_crop.jpg").write_bytes(b"y")
    groups = {"t_A": [{"file": "a.jpg", "car_crop": "a_crop.jpg"}],
              "t_B": [{"file": "b.jpg", "car_crop": "b_crop.jpg"}, {"file": "gone.jpg"}]}
    assert reid_dataset.record("split", "task1", groups, ev) == 2
    assert (tmp_path / "reid" / "images" / "task1" / "t_A" / "a_crop.jpg").exists()
    line = json.loads((tmp_path / "reid" / "decisions.jsonl").read_text().splitlines()[0])
    assert line["kind"] == "split" and set(line["identities"]) == {"t_A", "t_B"}
