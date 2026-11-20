"""
pair.py - what the phone app learns when it finds this laptop on the network ("Connect" in the app).

Only public values go out: the laptop's address, and (when the cloud is set up) the project address with its public "anon"
key. The anon key is the one the phone app is built to carry anyway; every secret (service key, access token) stays here.
"""
import base64
import json

from fastapi import APIRouter, HTTPException, Request

import cloud
import cloud_setup
import emailer
from lan_address import lan_ips

router = APIRouter(prefix="/pair", tags=["pair"])

APP_ID = "huli-kamote"


@router.get("/config")
async def pair_config(request: Request):
    port = request.url.port or 8000
    url, anon = cloud.settings()[0], cloud_setup.saved_anon_key()
    ready = bool(cloud.configured() and anon and emailer.mode() == "online")
    return {
        "app": APP_ID,
        "version": 1,
        "port": port,
        "lan_addresses": [f"{ip}:{port}" for ip in lan_ips()],
        "cloud_ready": ready,
        "cloud_url": url if ready else "",
        "cloud_anon_key": anon if ready else "",
    }


@router.get("/code")
async def pair_code():
    """One line the dashboard shows and the phone app can paste ("Paste setup code"): the cloud project address and its public
    "anon" key, for a phone that cannot find the laptop on its network. Public values only; no secret is in it."""
    url, anon = cloud.settings()[0], cloud_setup.saved_anon_key()
    if not (cloud.configured() and anon):
        raise HTTPException(status_code=409, detail="Set up the cloud first (Motorists > Online > Set up cloud).")
    payload = json.dumps({"u": url, "k": anon}, separators=(",", ":"))
    return {"code": "hk1:" + base64.urlsafe_b64encode(payload.encode()).decode().rstrip("=")}
