"""
dev.py - TEMPORARY developer tools for the phone app's developer mode: list, create, edit and delete the demo motorists.

Switched on only when the backend runs with HK_DEV=1 (tools/run_demo_backend.bat does that); otherwise every call is refused.
Whatever changes here is also done in the phone cloud when it is set up. Delete this file and its line in main.py to remove it.
"""
import asyncio
import os

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

import cloud
import emailer
import store
from demerit_points import normalize_plate
from passwords import hash_password

MIN_PASSWORD_CHARS = 6


def _allowed(request: Request) -> None:
    emailer.load_env()
    if os.environ.get("HK_DEV") != "1":
        raise HTTPException(status_code=404, detail="Developer tools are off on this laptop. Start the backend with tools\\run_demo_backend.bat.")
    if request.headers.get("X-HK-Dev") != "1":
        raise HTTPException(status_code=403, detail="Not a developer request.")


router = APIRouter(prefix="/dev", tags=["dev"], dependencies=[Depends(_allowed)])


class NewAccount(BaseModel):
    name: str
    plate: str
    password: str
    email: str = ""


class AccountChange(BaseModel):
    name: str | None = None
    email: str | None = None
    password: str | None = None
    add_plates: list[str] = []
    remove_plates: list[str] = []


def _login_plate_key(motorist: dict) -> str:
    """The plate this account signs in with: the one it was made with (a demo account: its demo plate)."""
    if motorist["license_no"].startswith("PLATE-"):
        return motorist["license_no"][len("PLATE-"):]
    demo = store.DEMO_PLATES.get(motorist["id"])
    return normalize_plate(demo) if demo else normalize_plate(motorist["plates"][0] if motorist["plates"] else "")


async def _motorist(user_id: str) -> dict:
    found = next((m for m in await store.list_registry() if m["id"] == user_id), None)
    if found is None:
        raise HTTPException(status_code=404, detail="No such account")
    return found


def _view(motorist: dict) -> dict:
    return {"id": motorist["id"], "name": motorist["name"], "email": motorist["email"], "plates": motorist["plates"],
            "login_plate": next((p for p in motorist["plates"] if normalize_plate(p) == _login_plate_key(motorist)), "")}


async def _cloud(call) -> str:
    """Run a cloud change in a thread. 'off' when the cloud is not set up, 'ok', or a sentence saying what failed."""
    if not cloud.configured():
        return "off"
    try:
        await asyncio.to_thread(call)
        return "ok"
    except cloud.CloudError as exc:
        return f"failed: {exc}"


@router.get("/accounts")
async def accounts():
    return {"accounts": [_view(m) for m in await store.list_registry()]}


@router.post("/accounts", status_code=201)
async def create_account(body: NewAccount):
    name, email, key = body.name.strip(), body.email.strip(), normalize_plate(body.plate)
    if not name or not key or len(key) > 12:
        raise HTTPException(status_code=400, detail="Enter a name and a plate (up to 12 letters and digits)")
    if len(body.password) < MIN_PASSWORD_CHARS:
        raise HTTPException(status_code=400, detail=f"The password needs at least {MIN_PASSWORD_CHARS} characters")
    user = await store.create_motorist(name, body.plate, email, hash_password(body.password))
    if user is None:
        raise HTTPException(status_code=409, detail="That plate already has an account")
    account = {"name": name, "plate": body.plate, "plates": [body.plate], "password": body.password, "email": email}
    return {"account": _view(await _motorist(user["id"])), "cloud": await _cloud(lambda: cloud.ensure_account(account))}


@router.put("/accounts/{user_id}")
async def change_account(user_id: str, body: AccountChange):
    motorist = await _motorist(user_id)
    if body.password is not None and len(body.password) < MIN_PASSWORD_CHARS:
        raise HTTPException(status_code=400, detail=f"The password needs at least {MIN_PASSWORD_CHARS} characters")
    login_key = _login_plate_key(motorist)
    for plate in body.remove_plates:
        if normalize_plate(plate) == login_key:
            raise HTTPException(status_code=400, detail="That is the plate this account signs in with. It cannot be removed.")

    await store.update_motorist(user_id, name=body.name.strip() if body.name else None,
                                password_hash=hash_password(body.password) if body.password else None)
    if body.email is not None:
        await store.set_user_email(user_id, body.email.strip())
    for plate in body.add_plates:
        if await store.register_plate(plate, user_id) is None:
            raise HTTPException(status_code=400, detail=f"'{plate}' is not a plate")
    for plate in body.remove_plates:
        await store.unregister_plate(plate)

    owner_plate = next((p for p in motorist["plates"] if normalize_plate(p) == login_key), motorist["plates"][0] if motorist["plates"] else "")

    def sync_cloud():
        cloud.update_account(owner_plate, name=body.name.strip() if body.name else None,
                             email=body.email.strip() if body.email is not None else None, password=body.password or None)
        cloud.add_plates(owner_plate, body.add_plates)
        for plate in body.remove_plates:
            cloud.remove_plate(plate)

    return {"account": _view(await _motorist(user_id)), "cloud": await _cloud(sync_cloud)}


@router.delete("/accounts/{user_id}")
async def delete_account(user_id: str):
    motorist = await _motorist(user_id)
    owner_plate = motorist["plates"][0] if motorist["plates"] else ""
    await store.delete_motorist(user_id)
    return {"deleted": user_id, "cloud": await _cloud(lambda: cloud.delete_account(owner_plate)) if owner_plate else "off"}
