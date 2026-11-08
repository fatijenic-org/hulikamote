"""cloud.py accounts + push: demo accounts in the phone cloud, the setup self-check wording, the Firebase check and the push text.
A small stand-in for Supabase; no network."""
import json
import re
import urllib.parse
from pathlib import Path

import pytest

import cloud
import store

APP_CONFIG = Path(__file__).resolve().parents[2] / "hulikamote_app" / "lib" / "core" / "config" / "app_config.dart"


class FakeProject:
    """A tiny Supabase. Creating an account makes its profile and first plate (as the sign-up trigger does)."""

    def __init__(self):
        self.profiles, self.plates, self.calls, self.n = {}, {}, [], 0

    def __call__(self, method, path, *, body=None, raw=None, headers=None):
        self.calls.append((method, path, body))
        route, _, query = path.partition("?")
        q = {k: v[0] for k, v in urllib.parse.parse_qs(query).items()}
        if method == "POST" and route == "/auth/v1/admin/users":
            meta = body["user_metadata"]
            key = cloud.normalize_plate(meta["plate"])
            if key in self.plates:
                raise cloud.CloudError("Supabase answered 500: Database error creating new user")
            self.n += 1
            uid = f"u-{self.n}"
            self.profiles[uid] = {"user_id": uid, "name": meta["name"], "email": meta["contact_email"], "login": body["email"],
                                  "password": body["password"], "confirmed": body["email_confirm"]}
            self.plates[key] = uid
            return {"id": uid}
        if method == "GET" and route == "/rest/v1/plates":
            key = q["plate_key"].removeprefix("eq.")
            return [{"user_id": self.plates[key], "plate_key": key}] if key in self.plates else []
        if method == "GET" and route == "/rest/v1/profiles":
            profile = self.profiles.get(q["user_id"].removeprefix("eq."))
            return [{k: profile[k] for k in ("user_id", "name", "email")}] if profile else []
        if method == "POST" and route == "/rest/v1/plates":
            self.plates[body["plate_key"]] = body["user_id"]
            return None
        if method == "PATCH" and route == "/rest/v1/profiles":
            self.profiles[q["user_id"].removeprefix("eq.")].update(body)
            return None
        if method == "PUT" and route.startswith("/auth/v1/admin/users/"):
            profile = self.profiles[route.rsplit("/", 1)[1]]
            profile["password"] = body.get("password", profile["password"])
            profile["metadata"] = body.get("user_metadata")
            return {}
        if method == "DELETE" and route.startswith("/auth/v1/admin/users/"):
            uid = route.rsplit("/", 1)[1]
            self.profiles.pop(uid, None)
            self.plates = {k: v for k, v in self.plates.items() if v != uid}
            return None
        raise AssertionError(f"unexpected call {method} {path}")

    def creates(self):
        return [c for c in self.calls if c[0] == "POST" and c[1] == "/auth/v1/admin/users"]


@pytest.fixture
def project(monkeypatch):
    fake = FakeProject()
    monkeypatch.setattr(cloud, "_request", fake)
    return fake


JUAN = {"name": "Juan Dela Cruz", "plate": "ABC 1234", "plates": ["ABC 1234", "LP14LJA", "af65jkv"], "password": "password123", "email": "juan@example.test"}


def test_the_phone_app_and_the_laptop_agree_on_the_made_up_sign_in_address():
    shown = re.search(r"plateEmailDomain = '([^']+)'", APP_CONFIG.read_text(encoding="utf-8")).group(1)
    assert cloud.PLATE_EMAIL_DOMAIN == shown
    assert cloud.email_for("abc 1234") == f"abc1234@{shown}"


def test_a_demo_account_is_created_confirmed_with_all_its_plates(project):
    assert cloud.sync_accounts([JUAN]) == [{"plate": "ABC 1234", "status": "created", "detail": ""}]
    made = project.creates()[0][2]
    assert made["email"] == "abc1234@plates.hulikamote.app" and made["email_confirm"] is True and made["password"] == "password123"
    assert made["user_metadata"] == {"name": "Juan Dela Cruz", "plate": "ABC 1234", "contact_email": "juan@example.test"}
    assert set(project.plates) == {"ABC1234", "LP14LJA", "AF65JKV"} and len(set(project.plates.values())) == 1
    assert cloud.find_profile("AF65JKV")["name"] == "Juan Dela Cruz"                      # any of his plates finds him


def test_running_it_again_creates_nothing_twice_and_only_adds_missing_plates(project):
    cloud.sync_accounts([JUAN])
    again = cloud.sync_accounts([{**JUAN, "plates": [*JUAN["plates"], "NEW 9999"]}])
    assert again[0]["status"] == "exists" and len(project.creates()) == 1
    assert "NEW9999" in project.plates and len(project.profiles) == 1


def test_a_plate_that_belongs_to_another_account_is_left_alone(project):
    cloud.sync_accounts([{"name": "Maria", "plate": "DEF 5678", "plates": ["DEF 5678", "LP14LJA"], "password": "password123"}])
    cloud.sync_accounts([JUAN])
    mine = project.plates["LP14LJA"]
    assert cloud.find_profile("LP14LJA")["name"] == "Maria" and mine == project.plates["DEF5678"]


def test_one_failure_does_not_stop_the_other_accounts(project):
    cloud.sync_accounts([{"name": "Maria", "plate": "ABC 1234", "password": "password123"}])
    results = cloud.sync_accounts([JUAN, {"name": "Pedro", "plate": "GHI 9012", "password": "password123"}])
    assert [r["status"] for r in results] == ["exists", "created"]                         # ABC 1234 is Maria's, so Juan's plate exists
    broken = cloud.sync_accounts([{"name": "X", "plate": "ZZZ 1", "password": "p"}])
    assert broken[0]["status"] == "created"


def test_a_missing_sign_up_trigger_is_explained(monkeypatch):
    def no_trigger(method, path, **_):
        return {"id": "u-1"} if method == "POST" else []
    monkeypatch.setattr(cloud, "_request", no_trigger)
    result = cloud.sync_accounts([JUAN])[0]
    assert result["status"] == "failed" and "schema.sql" in result["detail"]


def test_a_cloud_error_while_creating_is_reported_for_that_account(monkeypatch):
    def down(method, path, **_):
        raise cloud.CloudError("Cannot reach Supabase: down")
    monkeypatch.setattr(cloud, "_request", down)
    assert cloud.sync_accounts([JUAN]) == [{"plate": "ABC 1234", "status": "failed", "detail": "Cannot reach Supabase: down"}]


def test_editing_an_account_changes_the_profile_and_the_login(project):
    cloud.sync_accounts([JUAN])
    cloud.update_account("abc-1234", name="Juan D.", email="new@example.test", password="newpass1")
    profile = next(iter(project.profiles.values()))
    assert (profile["name"], profile["email"], profile["password"]) == ("Juan D.", "new@example.test", "newpass1")
    assert profile["metadata"] == {"name": "Juan D.", "contact_email": "new@example.test"}


def test_editing_only_the_password_leaves_the_profile_alone(project):
    cloud.sync_accounts([JUAN])
    project.calls.clear()
    cloud.update_account("ABC 1234", password="newpass1")
    assert [c[0] for c in project.calls if c[0] != "GET"] == ["PUT"]


def test_editing_an_account_that_does_not_exist_does_nothing(project):
    cloud.update_account("NOBODY 1", name="x")
    assert all(c[0] == "GET" for c in project.calls)


def test_removing_an_account_removes_its_plates_too(project):
    cloud.sync_accounts([JUAN])
    assert cloud.delete_account("ABC 1234") is True and project.profiles == {} and project.plates == {}
    assert cloud.delete_account("ABC 1234") is False


# ─── push ────────────────────────────────────────────────────────────────────

def key_file(tmp_path, project_id):
    path = tmp_path / "key.json"
    path.write_text(json.dumps({"project_id": project_id}))
    return str(path)


def app_file(tmp_path, project_id):
    path = tmp_path / "google-services.json"
    path.write_text(json.dumps({"project_info": {"project_id": project_id}}))
    return str(path)


def test_push_is_ready_only_when_the_key_and_the_app_use_the_same_firebase_project(tmp_path, monkeypatch):
    monkeypatch.setattr(store, "_firebase_initialized", True)
    monkeypatch.setattr(store, "APP_GOOGLE_SERVICES", app_file(tmp_path, "demo-1"))
    monkeypatch.setattr(store, "FIREBASE_KEY_PATH", key_file(tmp_path, "demo-1"))
    assert store.push_status() == {"ready": True, "detail": "Push is ready (Firebase project demo-1)."}
    monkeypatch.setattr(store, "FIREBASE_KEY_PATH", key_file(tmp_path, "other-2"))
    status = store.push_status()
    assert status["ready"] is False and "other-2" in status["detail"] and "demo-1" in status["detail"]


def test_push_says_what_to_do_when_the_key_is_missing_or_unusable(tmp_path, monkeypatch):
    monkeypatch.setattr(store, "FIREBASE_KEY_PATH", str(tmp_path / "nope.json"))
    assert store.push_status()["ready"] is False and "No Firebase key" in store.push_status()["detail"]
    monkeypatch.setattr(store, "FIREBASE_KEY_PATH", key_file(tmp_path, "demo-1"))
    monkeypatch.setattr(store, "_firebase_initialized", False)
    assert "cannot be used" in store.push_status()["detail"]


def test_a_push_pops_up_on_the_phone_and_says_what_and_which_car():
    ticket = {"id": "t1", "user_id": "u1", "cls": "no_helmet", "plate_text": "ABC 1234", "confidence": 0.9, "timestamp": "2026-11-01T08:00:00+00:00"}
    message = store._push_for(ticket, ["tok"])
    assert message.notification.title == "New violation on your record" and message.notification.body == "No Helmet · ABC 1234"
    assert message.android.priority == "high" and message.android.notification.channel_id == store.PUSH_CHANNEL == "hulikamote_alerts"
    assert message.data["violation_id"] == "t1" and message.tokens == ["tok"]
    assert store._push_for({**ticket, "plate_text": "unidentified"}, ["t"]).notification.body == "No Helmet"


def test_the_channel_the_laptop_pushes_to_is_the_one_the_app_creates():
    service = (Path(__file__).resolve().parents[2] / "hulikamote_app" / "lib" / "core" / "services" / "push_notification_service.dart").read_text(encoding="utf-8")
    assert f"'{store.PUSH_CHANNEL}'" in service


@pytest.mark.anyio
async def test_the_test_push_goes_to_every_registered_phone_and_reports_the_count(ac, monkeypatch):
    sent = []

    class Response:
        success_count, failure_count = 2, 1

    monkeypatch.setattr(store, "_firebase_initialized", True)
    monkeypatch.setattr(store, "push_status", lambda: {"ready": True, "detail": "ok"})
    monkeypatch.setattr(store.messaging, "send_each_for_multicast", lambda m: sent.append(list(m.tokens)) or Response())
    monkeypatch.setattr(cloud, "configured", lambda: True)
    monkeypatch.setattr(cloud, "all_device_tokens", lambda: ["cloud-1", "laptop-1"])
    await store.add_fcm_token("laptop-1", "user_001")
    await store.add_fcm_token("laptop-2", "user_002")

    result = await store.send_test_push()
    assert sorted(sent[0]) == ["cloud-1", "laptop-1", "laptop-2"]                       # each phone once
    assert (result["phones"], result["sent"], result["failed"]) == (3, 2, 1) and result["detail"] == "Sent to 2 of 3 phones."


@pytest.mark.anyio
async def test_the_test_push_does_nothing_without_a_working_key(ac, monkeypatch):
    monkeypatch.setattr(store, "push_status", lambda: {"ready": False, "detail": "No Firebase key"})
    monkeypatch.setattr(store.messaging, "send_each_for_multicast", lambda m: pytest.fail("must not send"))
    assert (await store.send_test_push()) == {"ready": False, "detail": "No Firebase key", "phones": 0, "sent": 0, "failed": 0}
