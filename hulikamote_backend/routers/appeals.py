import asyncio
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

import cloud
import store

router = APIRouter(prefix="/appeals", tags=["appeals"])

MAX_REASON_CHARS = 1000
MAX_NOTE_CHARS = 500


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


# ─── the officer's side: read the appeals and decide them ─────────────────────────────────────────────────────────

class DecisionBody(BaseModel):
    decision: str                  # accept | reject
    note: str = ""                 # what the reviewer tells the motorist (optional)


@router.get("/review")
async def review():
    """Every appeal for the officer: the ones filed on this laptop's Wi-Fi and the ones filed through the cloud (pulled in first).
    `cloud_error` says why the cloud part could not be read (the rest is still shown)."""
    cloud_error = ""
    if cloud.configured():
        try:
            await store.sync_cloud_appeals(await asyncio.to_thread(cloud.list_appeals))
        except cloud.CloudError as exc:
            cloud_error = str(exc)
    items = await store.appeals_for_review()
    counts = {s: sum(1 for i in items if i["status"] == s) for s in ("pending", "accepted", "rejected")}
    return {"appeals": items, "counts": counts, "cloud_error": cloud_error}


@router.post("/{appeal_id}/decision")
async def decide(appeal_id: str, body: DecisionBody):
    """Accept (the ticket is cancelled and stops counting as a demerit point) or reject (it stays). The motorist is told."""
    status = {"accept": "accepted", "reject": "rejected"}.get(body.decision.strip().lower())
    if status is None:
        raise HTTPException(status_code=400, detail="Decision must be accept or reject")
    note = body.note.strip()
    if len(note) > MAX_NOTE_CHARS:
        raise HTTPException(status_code=400, detail=f"The note can be up to {MAX_NOTE_CHARS} characters")
    appeal = await store.get_appeal(appeal_id)
    if not appeal:
        raise HTTPException(status_code=404, detail="Appeal not found")
    if appeal["status"] != "pending":
        raise HTTPException(status_code=409, detail="This appeal was already decided")
    decided_at = datetime.now(timezone.utc).isoformat()
    if appeal["source"] == "cloud":
        try:
            await asyncio.to_thread(cloud.decide_appeal, appeal["cloud_id"], status, note, decided_at)
        except cloud.CloudError as exc:
            raise HTTPException(status_code=502, detail=f"The cloud did not take the decision, so nothing was changed: {exc}")
    await store.decide_appeal(appeal_id, status, note, decided_at)
    appeal = await store.get_appeal(appeal_id)
    await store.notify_appeal_decision(appeal, await store.get_violation(appeal["violation_id"]), status, note)
    return next(item for item in await store.appeals_for_review() if item["id"] == appeal_id)
