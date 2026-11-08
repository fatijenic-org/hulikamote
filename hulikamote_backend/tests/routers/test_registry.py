"""routers/registry.py + store: which motorist owns a plate, and the e-mail that goes out when a ticket is approved."""
import itertools

import pytest

import emailer
import store

_videos = itertools.count(1)


async def ticket_for(plate, user_id="unregistered", cls="no_helmet"):
    v = await store.add_violation(cls, 0.9, user_id, plate_text=plate, notify=False, session_id=f"video{next(_videos)}")
    return v["id"]


@pytest.fixture
def mailbox(monkeypatch):
    """Everything the system tries to send, instead of sending it."""
    sent = []
    monkeypatch.setenv("HK_NOTIFY_MODE", "online")
    monkeypatch.setattr(emailer, "send", lambda msg: sent.append(msg) or emailer.Result("sent", ""))
    return sent


@pytest.mark.anyio
async def test_the_registry_lists_motorists_with_their_plates_and_never_a_password(ac):
    await ac.put("/registry/plates/LST 111", json={"user_id": "user_001"})
    motorists = (await ac.get("/registry")).json()["motorists"]
    juan = next(m for m in motorists if m["id"] == "user_001")
    assert juan["name"] == "Juan Dela Cruz" and "LST 111" in juan["plates"] and "email" in juan
    assert all("password" not in m for m in motorists)


@pytest.mark.anyio
async def test_a_plate_finds_its_owner_however_it_is_typed(ac):
    await ac.put("/registry/plates/Own 222", json={"user_id": "user_002"})
    for typed in ("OWN222", "own 222", "OWN-222"):
        assert (await store.get_user_by_plate(typed))["id"] == "user_002"
    assert await store.get_user_by_plate("NOT999") is None
    assert await store.get_user_by_plate("unidentified") is None


@pytest.mark.anyio
async def test_a_plate_can_move_to_another_motorist_and_be_removed(ac):
    await ac.put("/registry/plates/MOV 333", json={"user_id": "user_001"})
    await ac.put("/registry/plates/mov-333", json={"user_id": "user_003"})
    assert (await store.get_user_by_plate("MOV333"))["id"] == "user_003"
    assert (await ac.delete("/registry/plates/MOV 333")).status_code == 200
    assert await store.get_user_by_plate("MOV333") is None
    assert (await ac.delete("/registry/plates/MOV 333")).status_code == 404


@pytest.mark.anyio
@pytest.mark.parametrize("plate,user,code", [
    ("unidentified", "user_001", 400), ("---", "user_001", 400), ("ABCDEFGHIJKLM", "user_001", 400),
    ("OK 123", "nobody", 404),
])
async def test_bad_plates_and_unknown_motorists_are_refused(ac, plate, user, code):
    assert (await ac.put(f"/registry/plates/{plate}", json={"user_id": user})).status_code == code


@pytest.mark.anyio
async def test_the_email_address_is_checked_and_can_be_cleared(ac):
    assert (await ac.put("/registry/motorists/user_001/email", json={"email": "juan@example.test"})).status_code == 200
    assert (await ac.put("/registry/motorists/user_001/email", json={"email": "not an email"})).status_code == 400
    assert (await ac.put("/registry/motorists/nobody/email", json={"email": "a@b.test"})).status_code == 404
    juan = next(m for m in (await ac.get("/registry")).json()["motorists"] if m["id"] == "user_001")
    assert juan["email"] == "juan@example.test"                                  # the bad one changed nothing
    assert (await ac.put("/registry/motorists/user_001/email", json={"email": ""})).status_code == 200


@pytest.mark.anyio
async def test_approving_a_ticket_emails_the_plate_owner_even_if_the_plate_was_registered_later(ac, mailbox):
    ticket_id = await ticket_for("LATE 444")                                    # made while nobody owned the plate
    await ac.put("/registry/plates/LATE 444", json={"user_id": "user_002"})
    await ac.put("/registry/motorists/user_002/email", json={"email": "maria@example.test"})

    approved = (await ac.patch(f"/violations/{ticket_id}", json={"status": "approved"})).json()

    assert approved["user_id"] == "user_002"                                    # the ticket now belongs to her (and her app)
    assert [m["To"] for m in mailbox] == ["maria@example.test"]
    assert "LATE 444" in mailbox[0]["Subject"]


@pytest.mark.anyio
async def test_rejecting_or_leaving_a_ticket_pending_sends_nothing(ac, mailbox):
    await ac.put("/registry/plates/NOP 555", json={"user_id": "user_003"})
    await ac.put("/registry/motorists/user_003/email", json={"email": "pedro@example.test"})
    ticket_id = await ticket_for("NOP 555")
    await ac.patch(f"/violations/{ticket_id}", json={"status": "rejected"})
    assert mailbox == []


@pytest.mark.anyio
async def test_no_email_on_file_means_no_email_but_the_approval_still_works(ac, mailbox):
    await ac.put("/registry/plates/MUT 666", json={"user_id": "user_003"})
    await ac.put("/registry/motorists/user_003/email", json={"email": ""})
    response = await ac.patch(f"/violations/{await ticket_for('MUT 666')}", json={"status": "approved"})
    assert response.status_code == 200 and response.json()["status"] == "approved"
    assert mailbox == []


@pytest.mark.anyio
async def test_a_broken_mail_server_never_blocks_the_review(ac, monkeypatch):
    def explode(msg):
        raise RuntimeError("mail server on fire")
    monkeypatch.setenv("HK_NOTIFY_MODE", "online")
    monkeypatch.setattr(emailer, "send", explode)
    await ac.put("/registry/plates/ERR 777", json={"user_id": "user_001"})
    await ac.put("/registry/motorists/user_001/email", json={"email": "juan@example.test"})
    response = await ac.patch(f"/violations/{await ticket_for('ERR 777')}", json={"status": "approved"})
    assert response.status_code == 200 and response.json()["status"] == "approved"


@pytest.mark.anyio
async def test_a_plate_nobody_owns_is_left_unregistered(ac, mailbox):
    response = await ac.patch(f"/violations/{await ticket_for('UNK 888')}", json={"status": "approved"})
    assert response.json()["user_id"] == "unregistered" and mailbox == []


@pytest.mark.anyio
async def test_the_demo_plates_are_given_only_while_nobody_has_one(ac):
    registered = {p for m in (await ac.get("/registry")).json()["motorists"] for p in m["plates"]}
    await store.seed_registry()                                                 # others exist from the tests above: no-op
    after = {p for m in (await ac.get("/registry")).json()["motorists"] for p in m["plates"]}
    assert after == registered
