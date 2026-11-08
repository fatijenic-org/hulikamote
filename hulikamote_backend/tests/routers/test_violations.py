"""routers/violations.py - list, create and delete violations."""
import pytest


@pytest.mark.anyio
async def test_list_violations_returns_paginated(ac):
    response = await ac.get("/violations")
    assert response.status_code == 200
    body = response.json()
    assert "total" in body
    assert "items" in body
    assert isinstance(body["items"], list)


@pytest.mark.anyio
async def test_create_violation(ac):
    payload = {"user_id": "user_001", "cls": "no_helmet", "confidence": 0.88}
    response = await ac.post("/violations", json=payload)
    assert response.status_code == 201
    body = response.json()
    assert body["cls"] == "no_helmet"
    assert body["confidence"] == 0.88
    assert body["user_id"] == "user_001"
    assert "id" in body
    assert "timestamp" in body


@pytest.mark.anyio
async def test_delete_all_violations(ac):
    # Create one first
    await ac.post("/violations", json={"user_id": "user_001", "cls": "red_light", "confidence": 0.9})
    # Delete all
    response = await ac.delete("/settings/violations")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "success"
    assert body["deleted"] >= 1
    # Verify empty
    check = await ac.get("/violations")
    assert check.json()["total"] == 0
