"""routers/demerit.py - points appear when a reviewer approves a ticket and go away when it is not approved."""
import itertools

import pytest

from store import add_violation


_videos = itertools.count(1)


async def make_ticket(plate, cls="no_helmet"):
    # a new video each time: inside one video the same plate + violation is merged into a single ticket
    v = await add_violation(cls, 0.9, "unregistered", plate_text=plate, notify=False, session_id=f"video{next(_videos)}")
    return v["id"]                                                                         # starts as pending


@pytest.mark.anyio
async def test_nothing_counts_until_a_reviewer_approves_it(ac):
    await ac.delete("/settings/violations")
    await make_ticket("AAA111")
    assert (await ac.get("/demerit")).json() == {"plates": []}
    assert (await ac.get("/demerit/AAA111")).json()["points"] == 0


@pytest.mark.anyio
async def test_approving_adds_a_point_and_rejecting_adds_none(ac):
    await ac.delete("/settings/violations")
    approved = await make_ticket("BBB222")
    rejected = await make_ticket("BBB222", "red_light")
    assert (await ac.patch(f"/violations/{approved}", json={"status": "approved"})).status_code == 200
    assert (await ac.patch(f"/violations/{rejected}", json={"status": "rejected"})).status_code == 200

    body = (await ac.get("/demerit/bbb-222")).json()                         # typed differently on purpose
    assert body["points"] == 1 and body["by_class"] == {"no_helmet": 1}
    assert [v["id"] for v in body["violations"]] == [approved]


@pytest.mark.anyio
async def test_changing_your_mind_takes_the_point_back(ac):
    await ac.delete("/settings/violations")
    ticket_id = await make_ticket("CCC333")
    await ac.patch(f"/violations/{ticket_id}", json={"status": "approved"})
    assert (await ac.get("/demerit/CCC333")).json()["points"] == 1
    await ac.patch(f"/violations/{ticket_id}", json={"status": "rejected"})
    assert (await ac.get("/demerit/CCC333")).json()["points"] == 0


@pytest.mark.anyio
async def test_standings_rank_plates_by_points(ac):
    await ac.delete("/settings/violations")
    for plate, how_many in (("LOW111", 1), ("TOP999", 3), ("MID555", 2)):
        for _ in range(how_many):
            await ac.patch(f"/violations/{await make_ticket(plate)}", json={"status": "approved"})
    plates = (await ac.get("/demerit")).json()["plates"]
    assert [(p["plate"], p["points"]) for p in plates] == [("TOP999", 3), ("MID555", 2), ("LOW111", 1)]
