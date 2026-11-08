from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

import store

router = APIRouter(prefix="/appeals", tags=["appeals"])

MAX_REASON_CHARS = 1000


class AppealBody(BaseModel):
    violation_id: str
    user_id: str
    reason: str


@router.post("", status_code=201)
async def file_appeal(body: AppealBody):
    """A motorist contests one of their confirmed tickets. One appeal per ticket."""
    reason = body.reason.strip()
    if not reason or len(reason) > MAX_REASON_CHARS:
        raise HTTPException(status_code=400, detail=f"Write your reason (up to {MAX_REASON_CHARS} characters)")
    ticket = await store.get_violation(body.violation_id)
    if not ticket:
        raise HTTPException(status_code=404, detail="Ticket not found")
    if ticket["user_id"] != body.user_id:
        raise HTTPException(status_code=403, detail="That ticket is not yours")
    if ticket["status"] != "approved":
        raise HTTPException(status_code=400, detail="Only confirmed tickets can be appealed")
    if await store.get_appeal_for(ticket["id"]):
        raise HTTPException(status_code=409, detail="You already appealed this ticket")
    return await store.add_appeal(ticket["id"], body.user_id, reason)


@router.get("")
async def my_appeals(user_id: str):
    return {"appeals": await store.list_appeals(user_id)}
