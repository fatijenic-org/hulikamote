from fastapi import APIRouter
from pydantic import BaseModel, Field
from store import add_fcm_token, remove_fcm_token

router = APIRouter(prefix="/notifications", tags=["notifications"])


class TokenPayload(BaseModel):
    token: str = Field(..., description="Firebase Cloud Messaging token")
    user_id: str = Field(..., description="The logged-in user's ID")


@router.post("/register-token", status_code=200)
async def register_token(payload: TokenPayload):
    await add_fcm_token(payload.token, payload.user_id)
    return {"status": "success", "message": f"Token registered for {payload.user_id}"}


class ForgetPayload(BaseModel):
    token: str = Field(..., description="Firebase Cloud Messaging token of the phone that signed out")


@router.post("/forget-token", status_code=200)
async def forget_token(payload: ForgetPayload):
    await remove_fcm_token(payload.token)
    return {"status": "ok"}
