"""main.py - the /status endpoint."""
import pytest


@pytest.mark.anyio
async def test_get_status(ac):
    response = await ac.get("/status")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["mode"] in ("mock", "real")
