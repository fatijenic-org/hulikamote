"""
emailer.py - the notice a motorist gets when a violation is recorded against their plate.

Two ways to deliver it (the Motorists tab switches between them):
  online   send it by e-mail through a mail server (Gmail)
  offline  send nothing out: the notice waits in the laptop's mailbox, which a phone on the same Wi-Fi or hotspot
           opens in its browser (routers/mailbox.py)
Either way the notice is also written to the mailbox, so the dashboard can show what was sent.

Settings are environment variables, kept in hulikamote_backend/.env (git ignores it), never in the code:
  HK_NOTIFY_MODE     online | offline. Not set: online if a mail server or Supabase is set, otherwise offline
  HK_SUPABASE_URL / HK_SUPABASE_SERVICE_KEY   the phone app's cloud (see cloud.py)
  HK_SMTP_HOST       mail server, e.g. smtp.gmail.com;  HK_SMTP_PORT 587 by default
  HK_SMTP_SECURITY   starttls (default), ssl or none
  HK_SMTP_USER       login name;  HK_SMTP_PASSWORD its password (for Gmail: an "app password")
  HK_SMTP_FROM       sender address, the login name by default
"""
import os
import smtplib
from collections import namedtuple
from datetime import datetime
from email.message import EmailMessage
from email.utils import formataddr
from pathlib import Path

import evidence_files

BACKEND_DIR = Path(__file__).resolve().parent
ENV_FILE = BACKEND_DIR / ".env"
ENV_KEYS = ("HK_NOTIFY_MODE", "HK_SMTP_HOST", "HK_SMTP_PORT", "HK_SMTP_SECURITY", "HK_SMTP_USER", "HK_SMTP_PASSWORD", "HK_SMTP_FROM",
            "HK_SUPABASE_URL", "HK_SUPABASE_SERVICE_KEY")
MODES = ("online", "offline")
TIMEOUT_S = 10
MAX_ATTACHMENT_BYTES = 15 * 1024 * 1024        # Gmail refuses mail over 25 MB; stay well under
SENDER_NAME = "HULI-KAMOTE"            # what the inbox shows as the sender, next to the address

Result = namedtuple("Result", "status detail")        # status: sent | failed | local


def load_env() -> None:
    """Read .env into the environment. Variables that are already set win."""
    try:
        import dotenv
        dotenv.load_dotenv(ENV_FILE)
    except ImportError:
        pass


def settings() -> dict:
    load_env()
    user = os.environ.get("HK_SMTP_USER", "")
    return {
        "host": os.environ.get("HK_SMTP_HOST", ""),
        "port": int(os.environ.get("HK_SMTP_PORT") or "587"),
        "security": (os.environ.get("HK_SMTP_SECURITY") or "starttls").lower(),
        "user": user,
        "password": os.environ.get("HK_SMTP_PASSWORD", ""),
        "sender": os.environ.get("HK_SMTP_FROM", "") or user or "hulikamote@localhost",
    }


def mode() -> str:
    """'online' or 'offline'. An explicit HK_NOTIFY_MODE wins; otherwise a mail server means online."""
    load_env()
    chosen = (os.environ.get("HK_NOTIFY_MODE") or "").lower()
    if chosen in MODES:
        return chosen
    return "online" if os.environ.get("HK_SMTP_HOST") or os.environ.get("HK_SUPABASE_URL") else "offline"


def _when(iso: str) -> str:
    try:
        return datetime.fromisoformat(iso).astimezone().strftime("%B %d, %Y, %I:%M %p")
    except ValueError:
        return iso


def build_message(owner: dict, violation: dict, frames: list[str] = ()) -> EmailMessage:
    """Plain words: what was recorded, when, which case, how to appeal. Says it is a prototype notice.
    `frames` are the ticket's photos (file names); as many as fit are attached."""
    label = violation["cls"].replace("_", " ").title()
    plate = violation.get("plate_text") or "unknown plate"
    case_no = violation["id"][:8].upper()
    photos = evidence_files.read_within(list(frames), MAX_ATTACHMENT_BYTES)
    photo_line = ""
    if frames:
        more = f" (all {len(frames)} are in the app)" if len(photos) < len(frames) else ""
        photo_line = f"  Photos:        {len(photos)} attached{more}\n"
    msg = EmailMessage()
    msg["From"], msg["To"] = formataddr((SENDER_NAME, settings()["sender"])), owner.get("email", "")
    msg["Subject"] = f"Traffic violation recorded: {label} ({plate})"
    msg.set_content(
        f"Hello {owner['name']},\n\n"
        f"A traffic violation was recorded for plate {plate}.\n\n"
        f"  Violation:     {label}\n"
        f"  Date and time: {_when(violation['timestamp'])}\n"
        f"  Case number:   {case_no}\n"
        f"{photo_line}\n"
        "If you think this is a mistake, open the HULI-KAMOTE app and file an appeal for this case number.\n\n"
        "This message comes from HULI-KAMOTE, a research prototype. It is not an official notice and has no legal weight.\n"
    )
    for name, data in photos:
        msg.add_attachment(data, maintype="image", subtype="jpeg", filename=name)
    return msg


def send(msg: EmailMessage) -> Result:
    """Send through the configured mail server. Never raises: a mail problem must not stop a review decision."""
    cfg = settings()
    if not cfg["host"] or not msg["To"]:
        return Result("failed", "No mail server is set up." if not cfg["host"] else "This motorist has no e-mail address.")
    try:
        client_class = smtplib.SMTP_SSL if cfg["security"] == "ssl" else smtplib.SMTP
        with client_class(cfg["host"], cfg["port"], timeout=TIMEOUT_S) as server:
            if cfg["security"] == "starttls":
                server.starttls()
            if cfg["user"]:
                server.login(cfg["user"], cfg["password"])
            server.send_message(msg)
        print(f"[EMAIL] sent to {msg['To']} | {msg['Subject']}")
        return Result("sent", "")
    except smtplib.SMTPAuthenticationError:
        detail = "The mail server refused the login. Check the address and the app password."
    except Exception as exc:                            # no network, server refused ...
        detail = str(exc) or exc.__class__.__name__
    print(f"[EMAIL] could not send to {msg['To']}: {detail}")
    return Result("failed", detail)
