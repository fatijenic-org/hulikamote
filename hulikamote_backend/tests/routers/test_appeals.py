"""routers/appeals.py - a motorist contests a confirmed ticket from the phone app."""
import itertools

import pytest

import store

_videos = itertools.count(1)


async def ticket(user_id, status="approved"):
    v = await store.add_violation("no_helmet", 0.9, user_id, plate_text=f"AP{next(_videos)}", notify=False,
                                  session_id=f"ap{next(_videos)}", status=status)
    return v["id"]


@pytest.mark.anyio
async def test_a_motorist_can_appeal_their_confirmed_ticket_once(ac):
    ticket_id = await ticket("user_001")
    response = await ac.post("/appeals", json={"violation_id": ticket_id, "user_id": "user_001", "reason": "  I was parked legally. "})
    assert response.status_code == 201
    assert response.json()["status"] == "pending" and response.json()["reason"] == "I was parked legally."

    listed = (await ac.get("/appeals", params={"user_id": "user_001"})).json()["appeals"]
    assert [a["violation_id"] for a in listed] == [ticket_id]

    again = await ac.post("/appeals", json={"violation_id": ticket_id, "user_id": "user_001", "reason": "Again"})
    assert again.status_code == 409


@pytest.mark.anyio
@pytest.mark.parametrize("owner,status,reason,code", [
    ("user_002", "approved", "Not mine", 403),                  # somebody else's ticket
    ("user_001", "pending", "Too early", 400),                  # not confirmed yet
    ("user_001", "approved", "   ", 400),                       # no reason
    ("user_001", "approved", "x" * 1001, 400),                  # too long
])
async def test_appeals_that_cannot_be_filed_are_refused(ac, owner, status, reason, code):
    ticket_id = await ticket("user_001", status)
    response = await ac.post("/appeals", json={"violation_id": ticket_id, "user_id": owner, "reason": reason})
    assert response.status_code == code


@pytest.mark.anyio
async def test_appealing_a_ticket_that_does_not_exist_is_a_404(ac):
    assert (await ac.post("/appeals", json={"violation_id": "nope", "user_id": "user_001", "reason": "x"})).status_code == 404
