import re

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

import store
from demerit_points import normalize_plate
from passwords import hash_password, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])

MAX_PLATE_CHARS = 12
MIN_PASSWORD_CHARS = 6
EMAIL_SHAPE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class LoginRequest(BaseModel):
    password: str
    plate: str = ""                 # the phone app logs in with the plate number
    license_no: str = ""            # the old way, kept for the mock accounts


class RegisterRequest(BaseModel):
    name: str
    plate: str
    password: str
    email: str = ""                 # where to e-mail notices; optional


async def _profile(user: dict) -> dict:
    """The safe view of an account (never the password)."""
    plates = await store.get_user_plates(user["id"])
    return {
        "user_id": user["id"],
        "name": user["name"],
        "plate": plates[0] if plates else "",
        "email": user.get("email", ""),
        "license_no": user["license_no"],
        "license_type": user["license_type"],
        "restrictions": user["restrictions"] or "",
        "expiry": user["expiry"],
        "address": user["address"],
    }


@router.post("/login")
async def login(body: LoginRequest):
    user = await store.get_user_by_plate(body.plate) if body.plate.strip() else await store.get_user_by_license(body.license_no)
    if not user or not verify_password(body.password, user["password"]):
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return await _profile(user)


@router.post("/register", status_code=201)
async def register(body: RegisterRequest):
    """Create a motorist account with a plate number. The first account for a plate keeps it."""
    name, email = body.name.strip(), body.email.strip()
    key = normalize_plate(body.plate)
    if not name or len(name) > 80:
        raise HTTPException(status_code=400, detail="Enter your name")
    if not key or len(key) > MAX_PLATE_CHARS:
        raise HTTPException(status_code=400, detail=f"A plate has 1 to {MAX_PLATE_CHARS} letters and digits")
    if len(body.password) < MIN_PASSWORD_CHARS:
        raise HTTPException(status_code=400, detail=f"The password needs at least {MIN_PASSWORD_CHARS} characters")
    if email and (len(email) > 254 or not EMAIL_SHAPE.match(email)):
        raise HTTPException(status_code=400, detail="That does not look like an e-mail address")
    user = await store.create_motorist(name, body.plate, email, hash_password(body.password))
    if user is None:
        raise HTTPException(status_code=409, detail="That plate already has an account")
    return await _profile(user)
