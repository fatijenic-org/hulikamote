"""routers/auth.py - login (plate or licence number) and creating an account with a plate number."""
import pytest

import store


@pytest.mark.anyio
async def test_login_success(ac):
    payload = {"license_no": "N01-12-345678", "password": "password123"}
    response = await ac.post("/auth/login", json=payload)
    assert response.status_code == 200
    body = response.json()
    assert body["user_id"] == "user_001"
    assert body["name"] == "Juan Dela Cruz"


@pytest.mark.anyio
async def test_login_wrong_password(ac):
    payload = {"license_no": "N01-12-345678", "password": "wrong"}
    response = await ac.post("/auth/login", json=payload)
    assert response.status_code == 401


@pytest.mark.anyio
async def test_login_with_a_plate_however_it_is_typed(ac):
    await ac.put("/registry/plates/LOG 123", json={"user_id": "user_001"})
    for typed in ("LOG 123", "log-123", "LOG123"):
        response = await ac.post("/auth/login", json={"plate": typed, "password": "password123"})
        assert response.status_code == 200 and response.json()["user_id"] == "user_001"
    assert (await ac.post("/auth/login", json={"plate": "LOG 123", "password": "nope"})).status_code == 401
    assert (await ac.post("/auth/login", json={"plate": "NOBODY 9", "password": "password123"})).status_code == 401


@pytest.mark.anyio
async def test_a_new_account_is_made_with_a_plate_and_can_log_in(ac):
    response = await ac.post("/auth/register", json={"name": "  Ana Cruz ", "plate": "ana 777", "password": "secret1", "email": "ana@example.test"})
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "Ana Cruz" and body["plate"] == "ANA 777" and body["email"] == "ana@example.test"
    assert "password" not in body

    login = await ac.post("/auth/login", json={"plate": "ANA-777", "password": "secret1"})
    assert login.status_code == 200 and login.json()["user_id"] == body["user_id"]
    stored = await store.get_user_by_id(body["user_id"])
    assert "secret1" not in stored["password"]                                       # only the hash is kept
    assert (await store.get_user_by_plate("ANA777"))["id"] == body["user_id"]


@pytest.mark.anyio
async def test_a_plate_can_have_only_one_account(ac):
    first = {"name": "First", "plate": "ONE 111", "password": "secret1"}
    assert (await ac.post("/auth/register", json=first)).status_code == 201
    again = await ac.post("/auth/register", json={**first, "name": "Second", "plate": "one-111"})
    assert again.status_code == 409 and "already has an account" in again.json()["detail"]
    taken_by_a_mock_account = await ac.post("/auth/register", json={"name": "X", "plate": "ABC 1234", "password": "secret1"})
    assert taken_by_a_mock_account.status_code in (201, 409)                          # seeded in the live app, not in the test database


@pytest.mark.anyio
@pytest.mark.parametrize("payload,reason", [
    ({"name": "", "plate": "OK 1", "password": "secret1"}, "name"),
    ({"name": "A", "plate": "---", "password": "secret1"}, "plate"),
    ({"name": "A", "plate": "ABCDEFGHIJKLM", "password": "secret1"}, "plate"),
    ({"name": "A", "plate": "OK 2", "password": "12345"}, "at least 6"),
    ({"name": "A", "plate": "OK 3", "password": "secret1", "email": "not an email"}, "e-mail"),
])
async def test_bad_sign_ups_are_refused_with_a_reason(ac, payload, reason):
    response = await ac.post("/auth/register", json=payload)
    assert response.status_code == 400 and reason in response.json()["detail"].lower()


@pytest.mark.anyio
async def test_tickets_made_before_the_account_belong_to_the_new_owner(ac):
    await store.add_violation("no_helmet", 0.9, "unregistered", plate_text="OLD 555", notify=False, session_id="adopt1", status="approved")
    other = await store.add_violation("no_helmet", 0.9, "unregistered", plate_text="ELSE 1", notify=False, session_id="adopt2", status="approved")
    owner = (await ac.post("/auth/register", json={"name": "Old Owner", "plate": "OLD 555", "password": "secret1"})).json()
    mine = (await ac.get("/violations", params={"user_id": owner["user_id"], "status": "approved"})).json()
    assert [v["plate_text"] for v in mine["items"]] == ["OLD 555"]
    assert (await store.get_violation(other["id"]))["user_id"] == "unregistered"       # someone else's plate stays as it was
