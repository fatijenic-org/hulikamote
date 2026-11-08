"""
cloud.py - the Supabase side of "online": a confirmed ticket is copied to the cloud so the phone app can read it from
anywhere, and the phone's push tokens are read back so the laptop can push to them.

Settings (kept in backend/.env, entered in the dashboard): HK_SUPABASE_URL and HK_SUPABASE_SERVICE_KEY (the secret
"service_role" key; it never leaves this laptop). The tables and rules are in supabase/schema.sql.
Only the standard library is used.
"""
import json
import os
import urllib.error
import urllib.parse
import urllib.request
import uuid
from collections import namedtuple

import emailer
import evidence_files
from demerit_points import normalize_plate

TIMEOUT_S = 20
BUCKET = "evidence"
PLATE_EMAIL_DOMAIN = "plates.hulikamote.app"   # the phone app signs in as <plate>@this (AppConfig.plateEmailDomain there)
MAX_PHOTO_BYTES = 25 * 1024 * 1024          # per ticket; the rest stay on the laptop

Published = namedtuple("Published", "status detail tokens user_id subject body frames")   # status: sent | failed | local


class CloudError(Exception):
    """Supabase could not be reached or refused; the message is safe to show."""


def settings() -> tuple[str, str]:
    emailer.load_env()
    return os.environ.get("HK_SUPABASE_URL", "").strip().rstrip("/"), os.environ.get("HK_SUPABASE_SERVICE_KEY", "").strip()


def configured() -> bool:
    return all(settings())


def _request(method: str, path: str, *, body=None, raw: bytes | None = None, headers: dict | None = None):
    url, key = settings()
    if not (url and key):
        raise CloudError("Supabase is not set up (project URL and service key).")
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url + path, data=data, method=method)
    req.add_header("apikey", key)
    req.add_header("Authorization", f"Bearer {key}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    for name, value in (headers or {}).items():
        req.add_header(name, value)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as response:
            text = response.read().decode()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:240]
        raise CloudError(f"Supabase answered {exc.code}: {detail}") from exc
    except (urllib.error.URLError, OSError) as exc:
        raise CloudError(f"Cannot reach Supabase: {exc}") from exc
    return json.loads(text) if text.strip() else None


SETUP_GAPS = {
    "tables": "the tables are missing or old",
    "signup_trigger": "the sign-up trigger is missing",
    "functions": "the helper functions are missing",
    "bucket": "the private 'evidence' photo bucket is missing",
    "plate_locked": "motorists could still edit their plate",
}


def email_for(plate: str) -> str:
    return f"{normalize_plate(plate).lower()}@{PLATE_EMAIL_DOMAIN}"


def check() -> str:
    """Raises CloudError (with what to fix) unless the project answers and everything in supabase/schema.sql is in place.
    Returns a sentence for the dashboard; it carries a warning when new motorists could not sign up yet."""
    try:
        result = _request("POST", "/rest/v1/rpc/hulikamote_setup_check", body={})
    except CloudError as exc:
        if any(sign in str(exc) for sign in ("PGRST202", "PGRST205", "404", "does not exist", "Could not find")):
            raise CloudError("Connected, but the HULI-KAMOTE setup is missing or old. Run supabase/schema.sql in the Supabase SQL editor.") from exc
        raise
    missing = [text for key, text in SETUP_GAPS.items() if not (result or {}).get(key)]
    if missing:
        raise CloudError("Connected, but " + "; ".join(missing) + ". Run supabase/schema.sql again in the Supabase SQL editor.")
    detail = "Connected, and the setup is complete."
    try:
        settings_row = _request("GET", "/auth/v1/settings")
    except CloudError:
        settings_row = None
    if isinstance(settings_row, dict) and settings_row.get("mailer_autoconfirm") is False:
        detail += " Warning: turn 'Confirm email' OFF (Authentication > Providers > Email), or new motorists cannot sign up."
    return detail


def _first(rows):
    return rows[0] if rows else None


def _plate_row(plate_key: str) -> dict | None:
    return _first(_request("GET", f"/rest/v1/plates?plate_key=eq.{urllib.parse.quote(plate_key)}&select=user_id,plate_key&limit=1"))


def find_profile(plate_key: str) -> dict | None:
    """The account that owns this plate (any of its plates), or None."""
    row = _plate_row(plate_key)
    if not row:
        return None
    return _first(_request("GET", f"/rest/v1/profiles?user_id=eq.{urllib.parse.quote(row['user_id'])}&select=user_id,name,email&limit=1"))


def ensure_account(account: dict) -> str:
    """Make sure a phone account exists for this motorist: {name, plate, password, email, plates}. Returns 'created' or 'exists'.
    A new account is made already confirmed, so no e-mail round trip is needed. Extra plates are added to the account."""
    key = normalize_plate(account["plate"])
    owner = find_profile(key)
    status = "exists"
    if owner is None:
        _request("POST", "/auth/v1/admin/users", body={
            "email": email_for(account["plate"]), "password": account["password"], "email_confirm": True,
            "user_metadata": {"name": account["name"], "plate": account["plate"], "contact_email": account.get("email", "")},
        })
        owner = find_profile(key)
        if owner is None:
            raise CloudError("The account was created but has no profile. Run supabase/schema.sql again (the sign-up trigger is missing).")
        status = "created"
    for plate in account.get("plates", []):
        extra = normalize_plate(plate)
        if extra and extra != key and _plate_row(extra) is None:
            _request("POST", "/rest/v1/plates", headers={"Prefer": "return=minimal"},
                     body={"plate_key": extra, "plate": plate.strip().upper(), "user_id": owner["user_id"]})
    return status


def sync_accounts(accounts: list[dict]) -> list[dict]:
    """ensure_account for each; one that fails does not stop the rest. [{plate, status, detail}]"""
    results = []
    for account in accounts:
        try:
            results.append({"plate": account["plate"], "status": ensure_account(account), "detail": ""})
        except CloudError as exc:
            results.append({"plate": account["plate"], "status": "failed", "detail": str(exc)})
    return results


def update_account(plate: str, *, name: str | None = None, email: str | None = None, password: str | None = None) -> None:
    """Change the cloud account of this plate (name, contact e-mail, password). Does nothing if there is none."""
    profile = find_profile(normalize_plate(plate))
    if profile is None:
        return
    uid = urllib.parse.quote(profile["user_id"])
    row = {k: v for k, v in (("name", name), ("email", email)) if v is not None}
    if row:
        _request("PATCH", f"/rest/v1/profiles?user_id=eq.{uid}", headers={"Prefer": "return=minimal"}, body=row)
    change = {}
    if password:
        change["password"] = password
    if name is not None or email is not None:
        change["user_metadata"] = {k: v for k, v in (("name", name), ("contact_email", email)) if v is not None}
    if change:
        _request("PUT", f"/auth/v1/admin/users/{uid}", body=change)


def add_plates(owner_plate: str, plates: list[str]) -> None:
    """Give the cloud account that owns `owner_plate` more plates (one that belongs to another account is left alone)."""
    owner = _plate_row(normalize_plate(owner_plate))
    if owner is None:
        return
    for plate in plates:
        key = normalize_plate(plate)
        if key and _plate_row(key) is None:
            _request("POST", "/rest/v1/plates", headers={"Prefer": "return=minimal"},
                     body={"plate_key": key, "plate": plate.strip().upper(), "user_id": owner["user_id"]})


def remove_plate(plate: str) -> None:
    """Take a plate off its cloud account (never the plate the account signs in with: the caller checks)."""
    _request("DELETE", f"/rest/v1/plates?plate_key=eq.{urllib.parse.quote(normalize_plate(plate))}")


def delete_account(plate: str) -> bool:
    """Remove the cloud account of this plate with everything it owns. False if there was none."""
    profile = find_profile(normalize_plate(plate))
    if profile is None:
        return False
    _request("DELETE", f"/auth/v1/admin/users/{urllib.parse.quote(profile['user_id'])}")
    return True


def device_tokens(user_id: str) -> list[str]:
    rows = _request("GET", f"/rest/v1/device_tokens?user_id=eq.{urllib.parse.quote(user_id)}&select=token") or []
    return [r["token"] for r in rows]


def all_device_tokens() -> list[str]:
    """Every phone registered in the cloud (for the test push)."""
    return [r["token"] for r in _request("GET", "/rest/v1/device_tokens?select=token") or []]


def publish(violation: dict, frames: list[str]) -> Published:
    """Copy a confirmed ticket and its notice to the phone account that owns the plate. Never raises."""
    key = normalize_plate(violation.get("plate_text"))
    nothing = ("local", "", [], None, "", "", [])
    if not key:
        return Published("local", "No readable plate, so no phone account to send to.", *nothing[2:])
    try:
        profile = find_profile(key)
        if not profile:
            return Published("local", "No phone account for this plate yet.", *nothing[2:])
        uid, ticket_id = profile["user_id"], violation["id"]

        paths = []
        for name, data in evidence_files.read_within(frames, MAX_PHOTO_BYTES):
            path = f"{uid}/{ticket_id}/{name}"
            _request("POST", f"/storage/v1/object/{BUCKET}/{urllib.parse.quote(path)}", raw=data,
                     headers={"Content-Type": "image/jpeg", "x-upsert": "true"})
            paths.append(path)

        msg = emailer.build_message({"name": profile["name"]}, violation)
        subject, text = msg["Subject"], msg.get_body(preferencelist=("plain",)).get_content()
        _request("POST", "/rest/v1/tickets?on_conflict=id", headers={"Prefer": "resolution=merge-duplicates,return=minimal"}, body={
            "id": ticket_id, "user_id": uid, "plate_key": key, "cls": violation["cls"],
            "confidence": violation.get("confidence", 1.0), "occurred_at": violation["timestamp"], "frames": paths,
        })
        _request("POST", "/rest/v1/notices", headers={"Prefer": "return=minimal"},
                 body={"id": str(uuid.uuid4()), "user_id": uid, "ticket_id": ticket_id, "subject": subject, "body": text, "frames": paths})
        return Published("sent", "", device_tokens(uid), uid, subject, text, paths)
    except CloudError as exc:
        print(f"[CLOUD] could not publish: {exc}")
        return Published("failed", str(exc), [], None, "", "", [])
