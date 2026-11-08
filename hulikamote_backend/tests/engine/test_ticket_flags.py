from engine.ticket_flags import annotate_tickets, find_identity_jumps


def _lev(a, b):
    if a == b:
        return 0
    return sum(x != y for x, y in zip(a, b)) + abs(len(a) - len(b))


def _m(x, t, w=200, h=200):
    return {"file": f"{t}.jpg", "bbox": [x, 500, w, h], "t": t}


def _ticket(meta, plate="unidentified"):
    return {"plate_text": plate, "evidence_meta": meta}


def test_steady_track_has_no_jump():
    assert find_identity_jumps(_ticket([_m(100, 0), _m(130, 0.2), _m(160, 0.4)])) == []


def test_teleporting_box_flags_jump_at_second_segment():
    flags = find_identity_jumps(_ticket([_m(700, 0), _m(720, 0.2), _m(1240, 0.4), _m(1250, 0.6)]))
    assert [f["frame_index"] for f in flags] == [2]


def test_similar_plates_flag_both_tickets():
    a, b = _ticket([_m(0, 0)], "AP05JED"), _ticket([_m(900, 50)], "AP05JEO")
    annotate_tickets([a, b], _lev)
    assert a["flags"][0]["other_uid"] == b["ticket_uid"]
    assert b["flags"][0]["other_uid"] == a["ticket_uid"]


def test_continuity_flags_adjacent_tickets_but_not_distant_ones():
    a, near, far = _ticket([_m(100, 0), _m(120, 1)]), _ticket([_m(180, 2)]), _ticket([_m(1500, 2)])
    annotate_tickets([a, near, far], _lev)
    assert [f["other_uid"] for f in a["flags"]] == [near["ticket_uid"]]
    assert far["flags"] == []


def test_missing_bbox_or_time_is_ignored():
    a = _ticket([{"file": "x.jpg", "bbox": None, "t": None}])
    b = _ticket([_m(0, 1)])
    annotate_tickets([a, b], _lev)
    assert a["flags"] == [] and b["flags"] == []


def test_sensitivity_scale_changes_jump_detection():
    # 250px leap on 200px boxes: flagged when sensitive, ignored when strict
    t = _ticket([_m(0, 0), _m(250, 0.2)])
    assert find_identity_jumps(t, sensitivity=7) != []
    assert find_identity_jumps(t, sensitivity=1) == []
