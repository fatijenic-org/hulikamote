import re

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

import store
from demerit_points import normalize_plate

router = APIRouter(prefix="/registry", tags=["registry"])

MAX_PLATE_CHARS = 12                      # same limit as the plate edit in the review screen
EMAIL_SHAPE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


class EmailBody(BaseModel):
    email: str = ""                       # empty = do not e-mail this motorist


class PlateBody(BaseModel):
    user_id: str


@router.get("")
async def motorists():
    """Every motorist with the e-mail and plates on file (never the password)."""
    return {"motorists": await store.list_registry()}


@router.put("/motorists/{user_id}/email")
async def set_email(user_id: str, body: EmailBody):
    email = body.email.strip()
    if email and (len(email) > 254 or not EMAIL_SHAPE.match(email)):
        raise HTTPException(status_code=400, detail="That does not look like an e-mail address")
    if not await store.set_user_email(user_id, email):
        raise HTTPException(status_code=404, detail="No such motorist")
    return {"user_id": user_id, "email": email}


@router.put("/plates/{plate}")
async def register_plate(plate: str, body: PlateBody):
    """Register a plate to a motorist. A plate that belonged to someone else moves to this motorist."""
    key = normalize_plate(plate)
    if not key or len(key) > MAX_PLATE_CHARS:
        raise HTTPException(status_code=400, detail=f"A plate has 1 to {MAX_PLATE_CHARS} letters and digits")
    registered = await store.register_plate(plate, body.user_id)
    if registered is None:
        raise HTTPException(status_code=404, detail="No such motorist")
    return registered


@router.delete("/plates/{plate}")
async def unregister_plate(plate: str):
    if not await store.unregister_plate(plate):
        raise HTTPException(status_code=404, detail="That plate is not registered")
    return {"plate": plate.strip().upper(), "registered": False}
