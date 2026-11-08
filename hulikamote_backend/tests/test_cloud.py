"""cloud.py + its use in store: a confirmed ticket reaches the phone cloud, and the phone's push tokens are used. No network."""
import itertools
import json
import re
import urllib.parse
from pathlib import Path

import pytest

import cloud
import emailer
import evidence_files
import store

TICKET = {"id": "tick-1", "cls": "no_helmet", "plate_text": "ABC 1234", "confidence": 0.9, "timestamp": "2026-10-31T08:00:00+00:00"}


class FakeSupabase:
    """Stands in for cloud._request: records every call and answers like Supabase would."""

    def __init__(self, profile=None, tokens=("tok1", "tok2"), fail_on=None, setup=None, auth_settings=None):
        self.profile, self.tokens, self.fail_on, self.calls = profile, tokens, fail_on, []
        self.setup, self.auth_settings = setup, auth_settings

    def __call__(self, method, path, *, body=None, raw=None, headers=None):
        self.calls.append((method, path, body, raw, headers))
        if self.fail_on and self.fail_on in path:
            raise cloud.CloudError(f"Supabase answered 500: {path}")
        if path.startswith("/rest/v1/rpc/hulikamote_setup_check"):
            return self.setup
        if path.startswith("/auth/v1/settings"):
            return self.auth_settings
        if path.startswith("/rest/v1/plates"):
            return [{"user_id": self.profile["user_id"], "plate_key": "ABC1234"}] if self.profile else []
        if path.startswith("/rest/v1/profiles"):
            return [self.profile] if self.profile else []
        if path.startswith("/rest/v1/device_tokens"):
            return [{"token": t} for t in self.tokens]
        return None

    def paths(self):
        return [p.split("?")[0] for _, p, *_ in self.calls]


@pytest.fixture
def photos(tmp_path, monkeypatch):
    monkeypatch.setattr(evidence_files, "EVIDENCE_DIR", tmp_path)
    for name in ("f1.jpg", "f2.jpg"):
        (tmp_path / name).write_bytes(b"jpeg-" + name.encode())
    return ["f1.jpg", "f2.jpg"]


def test_a_ticket_is_copied_with_its_photos_to_the_account_that_owns_the_plate(photos, monkeypatch):
    fake = FakeSupabase(profile={"user_id": "u-1", "name": "Ana Cruz", "email": "ana@example.test"})
    monkeypatch.setattr(cloud, "_request", fake)
    result = cloud.publish(TICKET, photos)

    assert (result.status, result.user_id, result.tokens) == ("sent", "u-1", ["tok1", "tok2"])
    assert "plate_key=eq.ABC1234" in fake.calls[0][1]                                   # looked up by the plate, spaces ignored
    uploads = [c for c in fake.calls if c[1].startswith("/storage/")]
    assert [c[1] for c in uploads] == ["/storage/v1/object/evidence/u-1/tick-1/f1.jpg", "/storage/v1/object/evidence/u-1/tick-1/f2.jpg"]
    assert uploads[0][3] == b"jpeg-f1.jpg" and uploads[0][4]["Content-Type"] == "image/jpeg"
    ticket = next(c for c in fake.calls if c[1].startswith("/rest/v1/tickets"))
    assert ticket[2] == {"id": "tick-1", "user_id": "u-1", "plate_key": "ABC1234", "cls": "no_helmet", "confidence": 0.9,
                         "occurred_at": TICKET["timestamp"], "frames": ["u-1/tick-1/f1.jpg", "u-1/tick-1/f2.jpg"]}
    notice = next(c for c in fake.calls if c[1].startswith("/rest/v1/notices"))
    assert notice[2]["user_id"] == "u-1" and notice[2]["ticket_id"] == "tick-1" and "Ana Cruz" in notice[2]["body"]
    assert notice[2]["subject"] == "Traffic violation recorded: No Helmet (ABC 1234)"
    assert result.frames == ["u-1/tick-1/f1.jpg", "u-1/tick-1/f2.jpg"]


def test_a_plate_nobody_signed_up_with_sends_nothing(photos, monkeypatch):
    fake = FakeSupabase(profile=None)
    monkeypatch.setattr(cloud, "_request", fake)
    result = cloud.publish(TICKET, photos)
    assert result.status == "local" and "No phone account" in result.detail and result.tokens == []
    assert fake.paths() == ["/rest/v1/plates"]                                        # nothing was uploaded or written


def test_an_unread_plate_has_no_account_to_send_to(photos, monkeypatch):
    fake = FakeSupabase(profile={"user_id": "u-1", "name": "x"})
    monkeypatch.setattr(cloud, "_request", fake)
    assert cloud.publish({**TICKET, "plate_text": "unidentified"}, photos).status == "local"
    assert fake.calls == []


def test_a_cloud_failure_is_reported_and_never_raised(photos, monkeypatch):
    monkeypatch.setattr(cloud, "_request", FakeSupabase(profile={"user_id": "u-1", "name": "x"}, fail_on="/storage/"))
    result = cloud.publish(TICKET, photos)
    assert result.status == "failed" and "500" in result.detail and result.tokens == []


ALL_GOOD = {"tables": True, "signup_trigger": True, "functions": True, "bucket": True, "plate_locked": True}


def test_the_connection_check_passes_when_everything_is_in_place(monkeypatch):
    monkeypatch.setattr(cloud, "_request", FakeSupabase(setup=ALL_GOOD, auth_settings={"mailer_autoconfirm": True}))
    assert cloud.check() == "Connected, and the setup is complete."


def test_the_connection_check_warns_when_new_motorists_could_not_sign_up(monkeypatch):
    monkeypatch.setattr(cloud, "_request", FakeSupabase(setup=ALL_GOOD, auth_settings={"mailer_autoconfirm": False}))
    assert "Confirm email" in cloud.check()
    monkeypatch.setattr(cloud, "_request", FakeSupabase(setup=ALL_GOOD, auth_settings={"external": {}}))     # the setting is not reported: no claim
    assert cloud.check() == "Connected, and the setup is complete."


@pytest.mark.parametrize("gap,words", [
    ("tables", "tables"), ("signup_trigger", "sign-up trigger"), ("functions", "helper functions"),
    ("bucket", "photo bucket"), ("plate_locked", "edit their plate"),
])
def test_the_connection_check_names_what_is_missing(monkeypatch, gap, words):
    monkeypatch.setattr(cloud, "_request", FakeSupabase(setup={**ALL_GOOD, gap: False}))
    with pytest.raises(cloud.CloudError, match=words) as error:
        cloud.check()
    assert "schema.sql" in str(error.value)


def test_a_project_without_our_setup_function_is_told_to_run_the_sql(monkeypatch):
    def old_project(method, path, **_):
        raise cloud.CloudError("Supabase answered 404: PGRST202 Could not find the function public.hulikamote_setup_check")
    monkeypatch.setattr(cloud, "_request", old_project)
    with pytest.raises(cloud.CloudError, match="missing or old"):
        cloud.check()


def test_a_wrong_key_or_address_is_passed_on_as_it_is(monkeypatch):
    def refused(method, path, **_):
        raise cloud.CloudError("Supabase answered 401: Invalid API key")
    monkeypatch.setattr(cloud, "_request", refused)
    with pytest.raises(cloud.CloudError, match="Invalid API key"):
        cloud.check()


def test_without_settings_it_is_not_configured_and_refuses_to_call(monkeypatch):
    assert cloud.configured() is False
    monkeypatch.undo()
    with pytest.raises(cloud.CloudError, match="not set up"):
        cloud._request("GET", "/rest/v1/profiles")


def test_the_project_is_configured_from_the_env_file(monkeypatch):
    monkeypatch.delenv("HK_SUPABASE_URL")
    monkeypatch.delenv("HK_SUPABASE_SERVICE_KEY")
    emailer.ENV_FILE.write_text("HK_SUPABASE_URL=https://abc.supabase.co/\nHK_SUPABASE_SERVICE_KEY=secret\n")
    assert cloud.settings() == ("https://abc.supabase.co", "secret") and cloud.configured()


# ─── in the store: what happens when a ticket is confirmed ───────────────────

_n = itertools.count(1)


async def ticket_in_db(plate):
    v = await store.add_violation("no_helmet", 0.9, "unregistered", plate_text=plate, notify=False, session_id=f"cl{next(_n)}")
    return v["id"]


@pytest.mark.anyio
async def test_online_a_confirmed_ticket_goes_to_the_cloud_and_its_phones_get_the_push(ac, monkeypatch):
    published, pushed = [], []

    def fake_publish(v, frames):
        published.append((v["id"], v["plate_text"]))
        return cloud.Published("sent", "", ["phone-token"], "u-9", "Subject", "Body", ["u-9/t/f.jpg"])

    async def fake_push(v, extra_tokens=()):
        pushed.append(list(extra_tokens))

    monkeypatch.setenv("HK_NOTIFY_MODE", "online")
    monkeypatch.setenv("HK_SUPABASE_URL", "https://abc.supabase.co")
    monkeypatch.setenv("HK_SUPABASE_SERVICE_KEY", "secret")
    monkeypatch.setattr(cloud, "publish", fake_publish)
    monkeypatch.setattr(store, "_send_push_notification", fake_push)

    ticket_id = await ticket_in_db("CLD 111")
    assert (await ac.patch(f"/violations/{ticket_id}", json={"status": "approved"})).status_code == 200

    assert published == [(ticket_id, "CLD 111")]
    assert pushed == [["phone-token"]]                                                # the phone's token reaches the push
    latest = (await ac.get("/notify/notices", params={"limit": 1})).json()["notices"][0]
    assert (latest["status"], latest["to_email"], latest["subject"]) == ("sent", "phone app", "Subject")


@pytest.mark.anyio
async def test_offline_nothing_goes_to_the_cloud(ac, monkeypatch):
    calls = []
    monkeypatch.setenv("HK_NOTIFY_MODE", "offline")
    monkeypatch.setenv("HK_SUPABASE_URL", "https://abc.supabase.co")
    monkeypatch.setenv("HK_SUPABASE_SERVICE_KEY", "secret")
    monkeypatch.setattr(cloud, "publish", lambda v, f: calls.append(v) or cloud.Published("sent", "", [], "u", "", "", []))
    ticket_id = await ticket_in_db("CLD 222")
    await ac.patch(f"/violations/{ticket_id}", json={"status": "approved"})
    assert calls == []


@pytest.mark.anyio
async def test_a_failed_cloud_send_is_recorded_with_its_reason_and_the_review_still_works(ac, monkeypatch):
    monkeypatch.setenv("HK_NOTIFY_MODE", "online")
    monkeypatch.setenv("HK_SUPABASE_URL", "https://abc.supabase.co")
    monkeypatch.setenv("HK_SUPABASE_SERVICE_KEY", "secret")
    monkeypatch.setattr(cloud, "publish", lambda v, f: cloud.Published("failed", "Cannot reach Supabase: down", [], None, "", "", []))
    ticket_id = await ticket_in_db("CLD 333")
    response = await ac.patch(f"/violations/{ticket_id}", json={"status": "approved"})
    assert response.status_code == 200 and response.json()["status"] == "approved"
    latest = (await ac.get("/notify/notices", params={"limit": 1})).json()["notices"][0]
    assert (latest["status"], latest["detail"]) == ("failed", "Cannot reach Supabase: down")


@pytest.mark.anyio
async def test_a_plate_without_a_phone_account_leaves_no_cloud_line(ac, monkeypatch):
    monkeypatch.setenv("HK_NOTIFY_MODE", "online")
    monkeypatch.setenv("HK_SUPABASE_URL", "https://abc.supabase.co")
    monkeypatch.setenv("HK_SUPABASE_SERVICE_KEY", "secret")
    before = len((await ac.get("/notify/notices", params={"limit": 200})).json()["notices"])
    monkeypatch.setattr(cloud, "publish", lambda v, f: cloud.Published("local", "No phone account for this plate yet.", [], None, "", "", []))
    ticket_id = await ticket_in_db("CLD 444")
    await ac.patch(f"/violations/{ticket_id}", json={"status": "approved"})
    assert len((await ac.get("/notify/notices", params={"limit": 200})).json()["notices"]) == before
