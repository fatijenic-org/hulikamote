"""
routers/forensic.py - Holding: photos the operator sets aside from a ticket (the tracker followed another car for a while),
and what can be done with them: make a new ticket, add them to another ticket, put them back, throw them away.
The report and holding.json are temp files; database writes and the ReID dataset are recorded fakes.
"""
import asyncio
import json

import pytest


def crop_result(file, text, t=1.0):
    return {"image_raw": file, "image_sr": None, "image_context": None, "t": t, "raw": text, "cleaned": text, "confidence": 0.9}


@pytest.fixture
def hold(tmp_path, monkeypatch):
    import engine.pipeline as pipeline
    import store
    from routers import forensic

    monkeypatch.setattr(pipeline, "EVIDENCE_DIR", tmp_path)
    out = tmp_path / "forensic" / "task1" / "output"
    out.mkdir(parents=True)
    u1 = {
        "ticket_uid": "u1", "track_id": 1, "violations": ["counterflow"], "plate_text": "AAA1111", "db_ids": ["r1"], "flags": [],
        "evidence_paths": ["p1.jpg", "p2.jpg", "p3.jpg"],
        "evidence_meta": [{"file": "p1.jpg", "t": 1.0, "crop": "c1.jpg", "plate": "AAA1111"},
                          {"file": "p2.jpg", "t": 2.0, "crop": "c2.jpg", "plate": "AAA1111"},
                          {"file": "p3.jpg", "t": 3.0, "crop": "c3.jpg", "plate": "BBB2222"}],
        "crop_results": [crop_result("c1.jpg", "AAA1111", 1.0), crop_result("c2.jpg", "AAA1111", 2.0), crop_result("c3.jpg", "BBB2222", 3.0)],
        "plate_crop_paths": ["c1.jpg", "c2.jpg", "c3.jpg"], "metadata": {"plate_format": "ph_standard"},
    }
    u2 = {
        "ticket_uid": "u2", "track_id": 2, "violations": ["red_light"], "plate_text": "CCC3333", "db_ids": ["r2"], "flags": [],
        "evidence_paths": ["q1.jpg", "q2.jpg"],
        "evidence_meta": [{"file": "q1.jpg", "t": 5.0, "crop": "d1.jpg", "plate": "CCC3333"},
                          {"file": "q2.jpg", "t": 6.0, "crop": "d2.jpg", "plate": "CCC3333"}],
        "crop_results": [crop_result("d1.jpg", "CCC3333", 5.0), crop_result("d2.jpg", "CCC3333", 6.0)],
        "plate_crop_paths": ["d1.jpg", "d2.jpg"], "metadata": {"plate_format": "ph_standard"},
    }
    report = out / "report.json"
    report.write_text(json.dumps([u1, u2]))
    (out / "forensic_config.json").write_text(json.dumps({"plate_format": "ph_standard", "flag_sensitivity": 4}))

    log = {"evidence": [], "plates": [], "merged": [], "added": [], "reid": []}

    async def fake_evidence(ids, paths):
        log["evidence"].append((list(ids), list(paths)))
        return len(ids)

    async def fake_plate(ids, plate, user_id):
        log["plates"].append((list(ids), plate, user_id))
        return len(ids)

    async def fake_merge_rows(keep_ids, drop_ids, evidence, plate, track_id):
        log["merged"].append((list(keep_ids), list(drop_ids), list(evidence), plate, track_id))
        return list(keep_ids)

    async def fake_add(**kwargs):
        row = {"id": f"new{len(log['added']) + 1}", **kwargs}
        log["added"].append(row)
        return row

    async def fake_owner(plate):
        return {"id": "user_001"} if plate == "BBB2222" else None

    monkeypatch.setattr(store, "set_violation_evidence", fake_evidence, raising=False)
    monkeypatch.setattr(store, "update_violation_plate", fake_plate, raising=False)
    monkeypatch.setattr(store, "merge_violation_rows", fake_merge_rows, raising=False)
    monkeypatch.setattr(forensic, "add_violation", fake_add)
    monkeypatch.setattr(forensic, "get_user_by_plate", fake_owner)
    monkeypatch.setattr(forensic, "_record_reid", lambda kind, task, groups: log["reid"].append((kind, groups)))
    forensic.forensic_tasks.pop("task1", None)

    def saved():
        return json.loads(report.read_text())

    def holding():
        return json.loads((out / "holding.json").read_text()) if (out / "holding.json").exists() else []

    def aside(frames=("p3.jpg",), uid="u1"):
        return asyncio.run(forensic.set_photos_aside(forensic.SetAsideRequest(task_id="task1", ticket_uid=uid, frames=list(frames))))

    def act(fn, batch_id, keep_uid=""):
        return asyncio.run(getattr(forensic, fn)(forensic.HoldingActionRequest(task_id="task1", batch_id=batch_id, keep_uid=keep_uid)))

    class Hold:
        pass

    h = Hold()
    h.forensic, h.saved, h.holding, h.aside, h.act, h.log = forensic, saved, holding, aside, act, log
    h.report_path = report
    return h


def test_photos_set_aside_leave_the_ticket_and_wait_in_holding(hold):
    res = hold.aside(["p3.jpg"])
    ticket = next(t for t in hold.saved() if t["ticket_uid"] == "u1")
    assert ticket["evidence_paths"] == ["p1.jpg", "p2.jpg"]                       # the ticket keeps the rest
    assert len(res["holding"]) == 1 and res["holding"] == hold.holding()
    batch = hold.holding()[0]
    assert batch["evidence_paths"] == ["p3.jpg"] and batch["from_uid"] == "u1" and batch["batch_id"]
    assert batch["plate_text"] == "BBB2222"                                       # the plate its own crop read
    assert "db_ids" not in batch                                                  # nothing is ticketed yet
    assert hold.log["evidence"] == [(["r1"], ["p1.jpg", "p2.jpg"])]               # the ticket's rows keep only what stays
    assert hold.log["reid"] == []                                                 # nothing decided about the photos yet


def test_a_ticket_cannot_set_aside_every_photo_and_unknown_tickets_are_404(hold):
    res = hold.aside(["p1.jpg", "p2.jpg", "p3.jpg"])
    assert res.status_code == 400 and hold.holding() == []
    assert hold.aside(["p1.jpg"], uid="ghost").status_code == 404


def test_holding_can_be_listed(hold):
    hold.aside(["p3.jpg"])
    res = asyncio.run(hold.forensic.get_holding("task1"))
    assert [b["evidence_paths"] for b in res["holding"]] == [["p3.jpg"]]
    assert asyncio.run(hold.forensic.get_holding("nope")).status_code == 404


def test_a_new_ticket_from_holding_has_its_own_plate_owner_and_rows(hold):
    hold.aside(["p3.jpg"])
    batch_id = hold.holding()[0]["batch_id"]
    res = hold.act("holding_make_ticket", batch_id)

    tickets = hold.saved()
    assert [t["ticket_uid"] for t in tickets][0] == "u1" and len(tickets) == 3     # inserted right after the source ticket
    new = tickets[1]
    assert new["ticket_uid"] == res["ticket_uid"] and new["evidence_paths"] == ["p3.jpg"]
    assert new["plate_text"] == "BBB2222" and new["violations"] == ["counterflow"]
    row = hold.log["added"][0]
    assert row["cls"] == "counterflow" and row["plate_text"] == "BBB2222" and row["user_id"] == "user_001"
    assert row["track_id"] == 1 and row["dedupe"] is False and new["db_ids"] == [row["id"]]
    assert hold.holding() == []
    kinds = [k for k, _ in hold.log["reid"]]
    assert kinds == ["split"]                                                      # two different cars: training data


def test_photos_in_holding_can_join_another_ticket(hold):
    hold.aside(["p3.jpg"])
    batch_id = hold.holding()[0]["batch_id"]
    hold.act("holding_add_to_ticket", batch_id, keep_uid="u2")

    tickets = {t["ticket_uid"]: t for t in hold.saved()}
    assert len(tickets) == 2
    assert tickets["u2"]["evidence_paths"] == ["p3.jpg", "q1.jpg", "q2.jpg"]       # in time order
    assert tickets["u2"]["violations"] == ["red_light"]                            # the ticket keeps its own violations
    assert tickets["u2"]["track_id"] == 2
    keep_ids, drop_ids, evidence, _, track = hold.log["merged"][0]
    assert keep_ids == ["r2"] and drop_ids == [] and evidence == ["p3.jpg", "q1.jpg", "q2.jpg"] and track == 2
    assert [k for k, _ in hold.log["reid"]] == ["merge"]                           # same car: training data
    assert hold.holding() == []
    assert hold.act("holding_add_to_ticket", "nope", keep_uid="u2").status_code == 404
    assert hold.act("holding_add_to_ticket", batch_id, keep_uid="").status_code in (400, 404)


def test_putting_photos_back_restores_the_ticket_without_teaching_anything(hold):
    hold.aside(["p3.jpg"])
    batch_id = hold.holding()[0]["batch_id"]
    hold.act("holding_put_back", batch_id)
    ticket = next(t for t in hold.saved() if t["ticket_uid"] == "u1")
    assert ticket["evidence_paths"] == ["p1.jpg", "p2.jpg", "p3.jpg"]
    assert hold.holding() == [] and hold.log["reid"] == []


def test_putting_photos_back_says_so_when_their_ticket_is_gone(hold):
    hold.aside(["p3.jpg"])
    batch_id = hold.holding()[0]["batch_id"]
    # the source ticket is merged away meanwhile
    hold.report_path.write_text(json.dumps([t for t in hold.saved() if t["ticket_uid"] != "u1"]))
    res = hold.act("holding_put_back", batch_id)
    assert res.status_code == 409 and "is gone" in json.loads(res.body)["error"]
    assert len(hold.holding()) == 1                                                # still waiting


def test_throwing_photos_away_only_empties_holding(hold):
    hold.aside(["p3.jpg"])
    before = hold.saved()
    batch_id = hold.holding()[0]["batch_id"]
    res = hold.act("holding_throw_away", batch_id)
    assert res["holding"] == [] and hold.holding() == []
    assert hold.saved() == before                                                  # tickets untouched
    assert hold.act("holding_throw_away", batch_id).status_code == 404
