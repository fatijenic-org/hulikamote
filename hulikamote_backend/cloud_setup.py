"""
cloud_setup.py - the "Set up cloud" button: one click makes a fresh Supabase project ready for HULI-KAMOTE.

The person gives the project address and a Supabase access token (supabase.com/dashboard/account/tokens) once. With it the
laptop, through the Supabase Management API:
  1. reads the project's keys (the public "anon" key for the phone, the secret "service_role" key for this laptop),
  2. runs supabase/schema.sql (tables, rules, sign-up trigger, private photo bucket),
  3. turns "Confirm email" off (phones sign up with a plate, so there is no inbox to confirm),
  4. checks the result and makes the demo accounts.
The access token is used only for this and is forgotten afterwards, unless the person ticks "remember" (then it waits in
backend/.env, which git ignores). It never goes to the phone. Only the standard library is used.
"""
import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path

import cloud
import emailer
import env_file

API = "https://api.supabase.com"
TIMEOUT_S = 90                               # running the schema can take a while on a new project
SCHEMA_FILE = Path(__file__).resolve().parent.parent / "supabase" / "schema.sql"
PROJECT_URL = re.compile(r"^https://([a-z0-9]{10,40})\.supabase\.co$")
TOKEN_KEY = "HK_SUPABASE_ACCESS_TOKEN"
ANON_KEY = "HK_SUPABASE_ANON_KEY"
TOKENS_PAGE = "supabase.com/dashboard/account/tokens"


class SetupError(Exception):
    """One step failed; the message says what to do and is safe to show (it never holds a token)."""


def saved_token() -> str:
    emailer.load_env()
    return os.environ.get(TOKEN_KEY, "").strip()


def saved_anon_key() -> str:
    emailer.load_env()
    return os.environ.get(ANON_KEY, "").strip()


def project_ref(url: str) -> str:
    match = PROJECT_URL.match((url or "").strip().rstrip("/"))
    if not match:
        raise SetupError("The project address looks like https://abcdefghij.supabase.co (Supabase: Project Settings > API).")
    return match.group(1)


def _manage(method: str, path: str, token: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(API + path, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("User-Agent", "huli-kamote-setup")            # the API's firewall refuses the default Python agent
    request.add_header("Accept", "application/json")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
            text = response.read().decode()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:300]
        if exc.code == 401:
            raise SetupError(f"Supabase refused the access token. Make a new one at {TOKENS_PAGE} and paste it again.") from exc
        if exc.code == 403:
            raise SetupError("This access token may not change that project. Use a token with full access, from the account that owns the project.") from exc
        if exc.code == 404:
            raise SetupError("Supabase does not know this project for this token. The token must come from the account that owns it.") from exc
        raise SetupError(f"Supabase answered {exc.code}: {detail}") from exc
    except (urllib.error.URLError, OSError) as exc:
        raise SetupError(f"Cannot reach Supabase: {exc}. Is this laptop online?") from exc
    return json.loads(text) if text.strip() else None


def pick_keys(rows) -> tuple[str, str]:
    """(anon, service_role) from the api-keys answer. The old JWT keys are used: the phone sends the anon key as a bearer token."""
    anon = service = ""
    for row in rows or []:
        name, key = str(row.get("name", "")).lower(), str(row.get("api_key") or "")
        if name == "anon" and not anon:
            anon = key
        elif name == "service_role" and not service:
            service = key
    if not (anon.startswith("eyJ") and service.startswith("eyJ")):
        raise SetupError("This project has no classic anon / service_role keys. In Supabase: Project Settings > API Keys > "
                         "'Legacy API keys' > turn them on, then press Set up cloud again.")
    return anon, service


def fetch_keys(ref: str, token: str) -> tuple[str, str]:
    return pick_keys(_manage("GET", f"/v1/projects/{ref}/api-keys?reveal=true", token))


def run_schema(ref: str, token: str) -> None:
    try:
        sql = SCHEMA_FILE.read_text(encoding="utf-8")
    except OSError as exc:
        raise SetupError(f"Cannot read {SCHEMA_FILE.name}: {exc}") from exc
    _manage("POST", f"/v1/projects/{ref}/database/query", token, {"query": sql})


def confirm_email_off(ref: str, token: str) -> None:
    _manage("PATCH", f"/v1/projects/{ref}/config/auth", token, {"mailer_autoconfirm": True})


def run(url: str, access_token: str, remember: bool, demo_accounts: list[dict]) -> dict:
    """Do every step. {"ok", "steps": [{"text", "ok", "detail"}]}. Stops at the first step that cannot go on."""
    steps: list[dict] = []

    def step(text: str, action, *, fatal: bool = True):
        try:
            detail = action()
            steps.append({"text": text, "ok": True, "detail": detail if isinstance(detail, str) else "", "warn": not fatal})
            return True
        except (SetupError, cloud.CloudError, OSError, ValueError) as exc:
            steps.append({"text": text, "ok": False, "detail": str(exc), "warn": not fatal})
            return not fatal

    token = (access_token or "").strip() or saved_token()
    state: dict = {}

    def address():
        state["url"] = url.strip().rstrip("/")
        state["ref"] = project_ref(state["url"])

    def need_token():
        if not token:
            raise SetupError(f"Paste the access token (make one at {TOKENS_PAGE}).")

    def keys():
        anon, service = fetch_keys(state["ref"], token)
        env_file.update_env(emailer.ENV_FILE, {"HK_SUPABASE_URL": state["url"], "HK_SUPABASE_SERVICE_KEY": service,
                                               ANON_KEY: anon, "HK_NOTIFY_MODE": "online"})

    def accounts():
        results = cloud.sync_accounts(demo_accounts)
        failed = [r for r in results if r["status"] == "failed"]
        if failed:
            raise cloud.CloudError(f"{failed[0]['plate']}: {failed[0]['detail']}")
        made = sum(r["status"] == "created" for r in results)
        return f"{made} made, {len(results) - made} already there"

    ok = (step("Project address", address)
          and step("Access token", need_token)
          and step("Keys read and saved", keys)
          and step("Database ready (tables, rules, photo bucket)", lambda: run_schema(state["ref"], token))
          and step("Confirm email is off", lambda: confirm_email_off(state["ref"], token), fatal=False)
          and step("Cloud answers and is complete", cloud.check))
    if ok:
        step("Demo accounts", accounts, fatal=False)
        try:
            env_file.update_env(emailer.ENV_FILE, {TOKEN_KEY: token if remember else ""})
        except (ValueError, OSError):
            pass
    return {"ok": all(s["ok"] for s in steps), "steps": steps}
