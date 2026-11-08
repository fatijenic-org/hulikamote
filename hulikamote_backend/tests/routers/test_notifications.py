"""routers/notifications.py - a phone is registered for push, and forgotten when its motorist signs out."""
import pytest

import store


@pytest.mark.anyio
async def test_a_phone_that_signs_out_gets_no_more_pushes_for_that_account(ac):
    await ac.post("/notifications/register-token", json={"token": "tok-a", "user_id": "user_001"})
    await ac.post("/notifications/register-token", json={"token": "tok-b", "user_id": "user_001"})
    assert sorted(await store._get_tokens_for_user("user_001")) == ["tok-a", "tok-b"]
    assert (await ac.post("/notifications/forget-token", json={"token": "tok-a"})).status_code == 200
    assert await store._get_tokens_for_user("user_001") == ["tok-b"]


@pytest.mark.anyio
async def test_a_phone_that_signs_in_as_someone_else_moves_to_them(ac):
    await ac.post("/notifications/register-token", json={"token": "tok-c", "user_id": "user_001"})
    await ac.post("/notifications/register-token", json={"token": "tok-c", "user_id": "user_002"})
    assert "tok-c" not in await store._get_tokens_for_user("user_001")
    assert "tok-c" in await store._get_tokens_for_user("user_002")


@pytest.mark.anyio
async def test_forgetting_an_unknown_phone_is_harmless(ac):
    assert (await ac.post("/notifications/forget-token", json={"token": "never-seen"})).status_code == 200
