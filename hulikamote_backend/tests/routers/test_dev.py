"""routers/dev.py - the temporary developer tools: off unless HK_DEV=1, guarded, and mirrored to the phone cloud."""
import pytest

import cloud
import store

DEV = {"X-HK-Dev": "1"}


@pytest.fixture
def dev_on(monkeypatch):
    monkeypatch.setenv("HK_DEV", "1")


@pytest.fixture
def cloud_calls(monkeypatch):
    """Cloud set up, with every change it is asked to make recorded instead of sent."""
    calls = []
    monkeypatch.setenv("HK_SUPABASE_URL", "https://abc.supabase.co")
    monkeypatch.setenv("HK_SUPABASE_SERVICE_KEY", "secret")
    monkeypatch.setattr(cloud, "ensure_account", lambda a: calls.append(("ensure", a["plate"], a["password"])) or "created")
    monkeypatch.setattr(cloud, "update_account", lambda plate, **kw: calls.append(("update", plate, kw)))
    monkeypatch.setattr(cloud, "add_plates", lambda owner, plates: calls.append(("add", owner, list(plates))))
    monkeypatch.setattr(cloud, "remove_plate", lambda plate: calls.append(("remove", plate)))
    monkeypatch.setattr(cloud, "delete_account", lambda plate: calls.append(("delete", plate)) or True)
    return calls


async def sign_up(ac, plate, name="Dev Tester", password="secret1"):
    return (await ac.post("/auth/register", json={"name": name, "plate": plate, "password": password})).json()


@pytest.mark.anyio
async def test_the_tools_are_off_unless_the_backend_was_started_for_them(ac):
    response = await ac.get("/dev/accounts", headers=DEV)
    assert response.status_code == 404 and "run_demo_backend.bat" in response.json()["detail"]


@pytest.mark.anyio
async def test_a_request_that_is_not_from_the_tools_is_refused(ac, dev_on):
    assert (await ac.get("/dev/accounts")).status_code == 403
    assert (await ac.post("/dev/accounts", json={"name": "x", "plate": "X 1", "password": "secret1"})).status_code == 403


@pytest.mark.anyio
async def test_accounts_are_listed_with_their_plates_and_never_a_password(ac, dev_on):
    await sign_up(ac, "DEV 100", name="Lister")
    body = (await ac.get("/dev/accounts", headers=DEV)).json()
    mine = next(a for a in body["accounts"] if a["name"] == "Lister")
    assert mine["plates"] == ["DEV 100"] and mine["login_plate"] == "DEV 100" and "password" not in mine and "password" not in str(body)


@pytest.mark.anyio
async def test_an_account_can_be_created_and_signed_in_and_the_cloud_gets_it_too(ac, dev_on, cloud_calls):
    response = await ac.post("/dev/accounts", headers=DEV, json={"name": "New Demo", "plate": "dev 200", "password": "pass1234", "email": "n@example.test"})
    assert response.status_code == 201 and response.json()["cloud"] == "ok"
    assert response.json()["account"]["plates"] == ["DEV 200"]                                     # stored in capitals
    assert (await ac.post("/auth/login", json={"plate": "DEV-200", "password": "pass1234"})).status_code == 200
    assert cloud_calls == [("ensure", "dev 200", "pass1234")]


@pytest.mark.anyio
@pytest.mark.parametrize("payload,code", [
    ({"name": "", "plate": "DEV 1", "password": "secret1"}, 400),
    ({"name": "A", "plate": "---", "password": "secret1"}, 400),
    ({"name": "A", "plate": "DEV 1", "password": "12345"}, 400),
])
async def test_a_bad_new_account_is_refused(ac, dev_on, payload, code):
    assert (await ac.post("/dev/accounts", headers=DEV, json=payload)).status_code == code


@pytest.mark.anyio
async def test_a_plate_that_has_an_account_is_refused_with_409(ac, dev_on):
    await sign_up(ac, "DEV 300")
    assert (await ac.post("/dev/accounts", headers=DEV, json={"name": "X", "plate": "dev-300", "password": "secret1"})).status_code == 409


@pytest.mark.anyio
async def test_a_cloud_failure_never_undoes_the_local_account(ac, dev_on, monkeypatch):
    def down(account):
        raise cloud.CloudError("Cannot reach Supabase: down")
    monkeypatch.setenv("HK_SUPABASE_URL", "https://abc.supabase.co")
    monkeypatch.setenv("HK_SUPABASE_SERVICE_KEY", "secret")
    monkeypatch.setattr(cloud, "ensure_account", down)
    response = await ac.post("/dev/accounts", headers=DEV, json={"name": "Local Only", "plate": "DEV 400", "password": "secret1"})
    assert response.status_code == 201 and response.json()["cloud"] == "failed: Cannot reach Supabase: down"
    assert (await ac.post("/auth/login", json={"plate": "DEV 400", "password": "secret1"})).status_code == 200


@pytest.mark.anyio
async def test_name_email_password_and_plates_can_be_changed_and_the_cloud_follows(ac, dev_on, cloud_calls):
    made = await sign_up(ac, "DEV 500", name="Before")
    body = {"name": "After", "email": "after@example.test", "password": "newpass1", "add_plates": ["DEV 501"], "remove_plates": []}
    response = await ac.put(f"/dev/accounts/{made['user_id']}", headers=DEV, json=body)
    account = response.json()["account"]
    assert response.status_code == 200 and (account["name"], account["email"]) == ("After", "after@example.test")
    assert set(account["plates"]) == {"DEV 500", "DEV 501"}
    assert (await ac.post("/auth/login", json={"plate": "DEV 501", "password": "newpass1"})).status_code == 200      # new password, any of its plates
    assert (await ac.post("/auth/login", json={"plate": "DEV 500", "password": "secret1"})).status_code == 401       # the old one is gone
    assert ("update", "DEV 500", {"name": "After", "email": "after@example.test", "password": "newpass1"}) in cloud_calls
    assert ("add", "DEV 500", ["DEV 501"]) in cloud_calls


@pytest.mark.anyio
async def test_an_extra_plate_can_be_removed_but_not_the_one_the_account_signs_in_with(ac, dev_on, cloud_calls):
    made = await sign_up(ac, "DEV 600")
    await ac.put(f"/dev/accounts/{made['user_id']}", headers=DEV, json={"add_plates": ["DEV 601"]})
    refused = await ac.put(f"/dev/accounts/{made['user_id']}", headers=DEV, json={"remove_plates": ["dev-600"]})
    assert refused.status_code == 400 and "signs in with" in refused.json()["detail"]
    ok = await ac.put(f"/dev/accounts/{made['user_id']}", headers=DEV, json={"remove_plates": ["DEV 601"]})
    assert ok.status_code == 200 and ok.json()["account"]["plates"] == ["DEV 600"]
    assert ("remove", "DEV 601") in cloud_calls


@pytest.mark.anyio
async def test_a_short_new_password_or_an_unknown_account_is_refused(ac, dev_on):
    made = await sign_up(ac, "DEV 700")
    assert (await ac.put(f"/dev/accounts/{made['user_id']}", headers=DEV, json={"password": "123"})).status_code == 400
    assert (await ac.put("/dev/accounts/nobody", headers=DEV, json={"name": "x"})).status_code == 404
    assert (await ac.delete("/dev/accounts/nobody", headers=DEV)).status_code == 404


@pytest.mark.anyio
async def test_deleting_removes_the_account_and_its_plates_but_keeps_its_tickets(ac, dev_on, cloud_calls):
    made = await sign_up(ac, "DEV 800")
    ticket = await store.add_violation("no_helmet", 0.9, made["user_id"], plate_text="DEV 800", notify=False, session_id="dev-del")
    response = await ac.delete(f"/dev/accounts/{made['user_id']}", headers=DEV)
    assert response.status_code == 200 and response.json()["cloud"] == "ok"
    assert (await ac.post("/auth/login", json={"plate": "DEV 800", "password": "secret1"})).status_code == 401
    assert await store.get_user_by_plate("DEV 800") is None
    assert (await store.get_violation(ticket["id"])) is not None
    assert ("delete", "DEV 800") in cloud_calls
