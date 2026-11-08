import asyncio
import re
from email.message import EmailMessage
from email.utils import formataddr

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

import cloud
import emailer
import env_file
import store
from lan_address import lan_ips

router = APIRouter(prefix="/notify", tags=["notify"])

EMAIL_SHAPE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
GMAIL_SETTINGS = {"HK_SMTP_HOST": "smtp.gmail.com", "HK_SMTP_PORT": "587", "HK_SMTP_SECURITY": "starttls"}


class SettingsBody(BaseModel):
    mode: str                       # online | offline
    gmail: str = ""                 # empty = keep the saved one
    app_password: str = ""          # empty = keep the saved one
    supabase_url: str = ""          # the phone app's cloud; empty = keep the saved one
    supabase_service_key: str = ""  # secret; empty = keep the saved one


class TestBody(BaseModel):
    to: str = ""                    # where to send the test; empty = the sender itself


def _view(request: Request, notices: list[dict]) -> dict:
    """What the dashboard shows. The password never leaves the backend: only whether one is saved."""
    cfg = emailer.settings()
    port = request.url.port or 8000
    return {
        "mode": emailer.mode(),
        "gmail": cfg["user"],
        "password_set": bool(cfg["password"]),
        "cloud_url": cloud.settings()[0],
        "cloud_key_set": bool(cloud.settings()[1]),
        "mailbox_urls": [f"http://{ip}:{port}/mailbox" for ip in lan_ips()],
        "notices": [{"id": n["id"], "user_name": n["user_name"] or "", "to_email": n["to_email"], "subject": n["subject"],
                     "status": n["status"], "detail": n["detail"], "created_at": n["created_at"], "frames": n["frames"]} for n in notices],
    }


@router.get("/settings")
async def get_settings(request: Request):
    return _view(request, await store.list_notices(limit=5))


@router.put("/settings")
async def put_settings(body: SettingsBody, request: Request):
    mode = body.mode.strip().lower()
    gmail = body.gmail.strip()
    password = "".join(body.app_password.split())            # Google shows it in groups of four letters
    if mode not in emailer.MODES:
        raise HTTPException(status_code=400, detail="Mode must be online or offline")
    if gmail and not EMAIL_SHAPE.match(gmail):
        raise HTTPException(status_code=400, detail="That does not look like an e-mail address")
    url = body.supabase_url.strip().rstrip("/")
    service_key = "".join(body.supabase_service_key.split())
    if url and not re.match(r"^https://[A-Za-z0-9.-]+(:\d+)?$", url):
        raise HTTPException(status_code=400, detail="The Supabase URL looks like https://your-project.supabase.co")
    saved = emailer.settings()
    saved_url, saved_key = cloud.settings()
    has_mail = (gmail or saved["user"]) and (password or saved["password"])
    has_cloud = (url or saved_url) and (service_key or saved_key)
    if mode == "online" and not (has_mail or has_cloud):
        raise HTTPException(status_code=400, detail="Online needs a Gmail address with its app password, or a Supabase project")

    values = {"HK_NOTIFY_MODE": mode}
    if gmail:
        values.update(GMAIL_SETTINGS, HK_SMTP_USER=gmail, HK_SMTP_FROM=gmail)
    if password:
        values["HK_SMTP_PASSWORD"] = password
    if url:
        values["HK_SUPABASE_URL"] = url
    if service_key:
        values["HK_SUPABASE_SERVICE_KEY"] = service_key
    try:
        env_file.update_env(emailer.ENV_FILE, values)
    except (ValueError, OSError) as exc:
        raise HTTPException(status_code=500, detail=f"Could not save the settings: {exc}")
    return _view(request, await store.list_notices(limit=5))


@router.post("/test")
async def send_test(body: TestBody):
    """Send one real e-mail with the saved settings, so a wrong password shows up now and not during the demo."""
    cfg = emailer.settings()
    if not (cfg["host"] and cfg["user"] and cfg["password"]):
        raise HTTPException(status_code=400, detail="Save the Gmail address and app password first")
    to = body.to.strip() or cfg["user"]
    if not EMAIL_SHAPE.match(to):
        raise HTTPException(status_code=400, detail="That does not look like an e-mail address")
    msg = EmailMessage()
    msg["From"], msg["To"], msg["Subject"] = formataddr((emailer.SENDER_NAME, cfg["sender"])), to, "HULI-KAMOTE test e-mail"
    msg.set_content("If you can read this, HULI-KAMOTE can send e-mail from this laptop.\n")
    result = await asyncio.to_thread(emailer.send, msg)
    return {"status": result.status, "detail": result.detail, "to": to}


@router.post("/cloud-test")
async def cloud_test():
    """Check the saved Supabase project answers and has the tables, so a wrong key shows up now, not at the demo."""
    try:
        return {"ok": True, "detail": await asyncio.to_thread(cloud.check)}
    except cloud.CloudError as exc:
        return {"ok": False, "detail": str(exc)}


@router.post("/cloud-demo-accounts")
async def cloud_demo_accounts():
    """Create the demo motorists (Juan, Maria, Pedro) in the phone cloud, with all the plates they own on the laptop, so the
    online demo works straight away. An account that exists is only given the plates it is missing."""
    if not cloud.configured():
        raise HTTPException(status_code=400, detail="Save the Supabase project address and service key first")
    registry = {m["id"]: m for m in await store.list_registry()}
    accounts = []
    for demo in store.MOCK_USERS:
        motorist = registry.get(demo["id"])
        if not motorist or not motorist["plates"]:
            continue
        login_plate = store.DEMO_PLATES.get(demo["id"]) or motorist["plates"][0]
        accounts.append({"name": motorist["name"], "plate": login_plate, "plates": motorist["plates"],
                         "password": demo["password"], "email": motorist["email"]})
    return {"results": await asyncio.to_thread(cloud.sync_accounts, accounts)}


@router.get("/push-check")
async def push_check():
    return store.push_status()


@router.post("/push-test")
async def push_test():
    return await store.send_test_push()


@router.get("/notices")
async def notices(user_id: str | None = None, limit: int = 50, after: str | None = None):
    """The notices of one motorist (the phone app) or everyone's. `after` = only the ones newer than that time."""
    return {"notices": await store.list_notices(user_id, max(1, min(limit, 200)), after)}
