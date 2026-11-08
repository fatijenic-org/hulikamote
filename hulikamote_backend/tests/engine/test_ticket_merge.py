from engine.ticket_merge import merge_tickets


def _t(tid, plate, score, files_t, violations=("counterflow",), db=("r1",)):
    return {
        "track_id": tid, "plate_text": plate, "vote_tally": {plate: score} if score else {},
        "violations": list(violations), "db_ids": list(db),
        "evidence_meta": [{"file": f"{t}.jpg", "bbox": [0, 0, 10, 10], "t": t} for t in files_t],
        "evidence_paths": [f"{t}.jpg" for t in files_t],
    }


def test_merge_orders_evidence_and_combines_ids():
    m = merge_tickets(_t(7, "unidentified", 0, [3, 4]), _t(3, "AP05JEO", 21.5, [1, 2], db=("r2",)))
    assert m["evidence_paths"] == ["1.jpg", "2.jpg", "3.jpg", "4.jpg"]
    assert m["track_id"] == "7 & 3" and m["merged_track_ids"] == [7, 3]
    assert m["db_ids"] == ["r1", "r2"]


def test_stronger_plate_wins_either_direction():
    a, b = _t(1, "AP05JED", 21.2, [1]), _t(2, "AP05JEO", 23.0, [2])
    assert merge_tickets(a, b)["plate_text"] == "AP05JEO"
    assert merge_tickets(b, a)["plate_text"] == "AP05JEO"


def test_violations_unioned_and_inputs_not_mutated():
    a, b = _t(1, "unidentified", 0, [1]), _t(2, "unidentified", 0, [2], violations=("illegal_parking",))
    m = merge_tickets(a, b)
    assert m["violations"] == ["counterflow", "illegal_parking"]
    assert a["violations"] == ["counterflow"]


def test_split_moves_frames_and_clears_plate():
    from engine.ticket_merge import split_ticket
    import pytest
    t = _t(10, "AP05JEO", 21.0, [1, 2, 3, 4])
    t["ticket_uid"] = "abc"
    rem, new = split_ticket(t, ["3.jpg", "4.jpg"])
    assert rem["evidence_paths"] == ["1.jpg", "2.jpg"] and new["evidence_paths"] == ["3.jpg", "4.jpg"]
    assert rem["plate_text"] == "AP05JEO" and new["plate_text"] == "unidentified"
    assert new["track_id"] == "10 (split)" and "ticket_uid" not in new
    with pytest.raises(ValueError):
        split_ticket(t, ["1.jpg", "2.jpg", "3.jpg", "4.jpg"])
    with pytest.raises(ValueError):
        split_ticket(t, [])


# ── plate crops follow the evidence frames they are linked to ────────────────
def _linked_ticket():
    meta = [
        {"file": f"f{i}.jpg", "bbox": [0, 0, 10, 10], "t": float(i), "crop": f"c{i}.jpg", "plate": p}
        for i, p in enumerate(["AAA1111", "AAA1111", "BBB2222", "BBB2222"])
    ]
    crops = [
        {"image_raw": f"c{i}.jpg", "cleaned": p, "raw": p, "confidence": 0.9, "t": float(i)}
        for i, p in enumerate(["AAA1111", "AAA1111", "BBB2222", "BBB2222"])
    ]
    return {
        "ticket_uid": "u1", "track_id": 5, "violations": ["counterflow"],
        "plate_text": "AAA1111", "vote_tally": {"AAA1111": 2.9, "BBB2222": 2.9},
        "evidence_meta": meta, "evidence_paths": [m["file"] for m in meta],
        "crop_results": crops, "plate_crop_paths": [c["image_raw"] for c in crops],
        "metadata": {"plate_format": "uk_standard"}, "db_ids": ["x"],
    }


def test_split_moves_linked_plate_crops_and_revotes():
    from engine.ticket_merge import split_ticket
    remaining, new = split_ticket(_linked_ticket(), ["f2.jpg", "f3.jpg"])
    assert remaining["plate_text"] == "AAA1111"
    assert new["plate_text"] == "BBB2222"
    assert [c["image_raw"] for c in new["crop_results"]] == ["c2.jpg", "c3.jpg"]
    assert [c["image_raw"] for c in remaining["crop_results"]] == ["c0.jpg", "c1.jpg"]
    assert new["plate_crop_paths"] == ["c2.jpg", "c3.jpg"]


def test_split_without_links_keeps_old_behaviour():
    from engine.ticket_merge import split_ticket
    t = _linked_ticket()
    for m in t["evidence_meta"]:
        m.pop("crop")
    remaining, new = split_ticket(t, ["f2.jpg", "f3.jpg"])
    assert remaining["plate_text"] == "AAA1111"
    assert new["plate_text"] == "unidentified"
    assert new["crop_results"] == []


def test_merge_only_selected_frames_of_other_ticket():
    from engine.ticket_merge import split_ticket, merge_tickets
    keep = {"ticket_uid": "k", "track_id": 1, "violations": ["counterflow"], "plate_text": "unidentified",
            "evidence_meta": [{"file": "k0.jpg", "t": 0.0}], "evidence_paths": ["k0.jpg"], "db_ids": []}
    src = _linked_ticket()
    remaining, moved = split_ticket(src, ["f0.jpg", "f1.jpg"])
    moved["track_id"] = src["track_id"]
    merged = merge_tickets(keep, moved)
    assert merged["evidence_paths"] == ["k0.jpg", "f0.jpg", "f1.jpg"]
    assert merged["plate_text"] == "AAA1111"          # stronger plate from the moved frames wins
    assert remaining["evidence_paths"] == ["f2.jpg", "f3.jpg"]
    assert remaining["plate_text"] == "BBB2222"
    assert merged["merged_track_ids"] == [1, 5]


# ── operator plate edit ──────────────────────────────────────────────────────
def test_normalize_plate_keeps_capitals_and_digits_only():
    from engine.ticket_merge import normalize_plate
    assert normalize_plate(" hle-150 ") == "HLE150"
    assert normalize_plate("ab 12 cd") == "AB12CD"
    assert normalize_plate(None) == ""


def test_plate_edit_remembers_the_ocr_read_once():
    from engine.ticket_merge import apply_plate_edit
    t = _t(1, "KM0522K", 9.0, [1])
    a = apply_plate_edit(t, "kmo 522k")
    assert (a["plate_text"], a["plate_manual"], a["plate_ocr"]) == ("KMO522K", True, "KM0522K")
    b = apply_plate_edit(a, "KMO5228")            # a second edit keeps the first OCR read
    assert (b["plate_text"], b["plate_ocr"]) == ("KMO5228", "KM0522K")
    assert t["plate_text"] == "KM0522K" and "plate_manual" not in t     # the input is untouched


def test_plate_edit_can_clear_and_revert():
    from engine.ticket_merge import apply_plate_edit
    t = _t(1, "KMO522K", 9.0, [1])
    cleared = apply_plate_edit(t, "")
    assert cleared["plate_text"] == "unidentified" and cleared["plate_manual"] is True
    assert cleared["plate_ocr"] == "KMO522K"
    back = apply_plate_edit(cleared, "", revert=True)
    assert back["plate_text"] == "KMO522K" and "plate_manual" not in back and "plate_ocr" not in back
    # reverting a ticket nobody edited changes nothing
    assert apply_plate_edit(t, "", revert=True) == t


def test_plate_edit_to_the_same_plate_is_not_an_edit():
    from engine.ticket_merge import apply_plate_edit
    t = _t(1, "KMO522K", 9.0, [1])
    assert "plate_manual" not in apply_plate_edit(t, "kmo-522k")


def test_plate_edit_sets_the_length_warning():
    from engine.ticket_merge import apply_plate_edit
    t = _t(1, "unidentified", 0, [1])
    assert apply_plate_edit(t, "ABC12")["plate_length_warning"] is True
    assert apply_plate_edit(t, "ABC1234")["plate_length_warning"] is False
    assert apply_plate_edit(t, "ABC12", plate_format="free")["plate_length_warning"] is False


def test_a_typed_plate_beats_a_stronger_ocr_vote_in_a_merge():
    from engine.ticket_merge import apply_plate_edit
    typed = apply_plate_edit(_t(1, "unidentified", 0, [1]), "ABC1234")
    strong = _t(2, "XYZ9999", 30.0, [2])
    for keep, drop in ((typed, strong), (strong, typed)):
        m = merge_tickets(keep, drop)
        assert m["plate_text"] == "ABC1234" and m["plate_manual"] is True
    # and an ordinary merge does not invent the flag
    assert "plate_manual" not in merge_tickets(strong, _t(3, "unidentified", 0, [3]))


def test_split_keeps_a_typed_plate_with_the_remaining_ticket():
    from engine.ticket_merge import split_ticket
    t = _linked_ticket()
    t.update(plate_text="ZZZ9999", plate_manual=True, plate_ocr="AAA1111")
    rem, new = split_ticket(t, ["f2.jpg", "f3.jpg"])
    assert rem["plate_text"] == "ZZZ9999" and rem["plate_manual"] is True
    assert new["plate_text"] == "BBB2222" and "plate_manual" not in new and "plate_ocr" not in new
