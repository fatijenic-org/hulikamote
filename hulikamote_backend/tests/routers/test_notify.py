"""routers/notify.py + mailbox.py - switching between online (Gmail) and offline (phone on the same Wi-Fi), and what each does."""
import itertools
import smtplib

import pytest

import emailer
import store
from routers import notify
from tests.helpers import FakeSMTP

_videos = itertools.count(1)


async def approved_ticket(ac, plate):
    v = await store.add_violation("no_helmet", 0.9, "unregistered", plate_text=plate, notify=False, session_id=f"nv{next(_videos)}")
    return (await ac.patch(f"/violations/{v['id']}", json={"status": "approved"})).json()


async def owner_with(ac, user_id, plate, email=""):
    await ac.put(f"/registry/plates/{plate}", json={"user_id": user_id})
    await ac.put(f"/registry/motorists/{user_id}/email", json={"email": email})


@pytest.mark.anyio
async def test_nothing_set_up_means_offline_with_this_laptops_address(ac, monkeypatch):
    monkeypatch.setattr(notify, "lan_ips", lambda: ["192.168.68.112"])
    body = (await ac.get("/notify/settings")).json()
    assert body["mode"] == "offline" and body["gmail"] == "" and body["password_set"] is False
    assert body["mailbox_urls"] == ["http://192.168.68.112:8000/mailbox"]


@pytest.mark.anyio
async def test_online_needs_the_address_and_the_app_password(ac):
    response = await ac.put("/notify/settings", json={"mode": "online", "gmail": "me@gmail.com"})
    assert response.status_code == 400 and "app password" in response.json()["detail"]
    assert not emailer.ENV_FILE.exists()                                          # a refused change writes nothing


@pytest.mark.anyio
async def test_saving_gmail_writes_the_env_file_keeps_other_lines_and_never_returns_the_password(ac):
    emailer.ENV_FILE.write_text("GITHUB_TOKEN=keep-me\n")
    response = await ac.put("/notify/settings", json={"mode": "online", "gmail": "me@gmail.com", "app_password": "abcd efgh ijkl mnop"})
    body = response.json()
    assert response.status_code == 200 and body["mode"] == "online" and body["gmail"] == "me@gmail.com" and body["password_set"] is True
    assert "abcd" not in response.text                                            # the password stays on the laptop
    env = emailer.ENV_FILE.read_text()
    for line in ("GITHUB_TOKEN=keep-me", "HK_NOTIFY_MODE=online", "HK_SMTP_HOST=smtp.gmail.com", "HK_SMTP_PORT=587",
                 "HK_SMTP_USER=me@gmail.com", "HK_SMTP_FROM=me@gmail.com", "HK_SMTP_PASSWORD=abcdefghijklmnop"):
        assert line in env.splitlines()                                            # spaces of the app password are dropped


@pytest.mark.anyio
async def test_switching_to_offline_and_back_keeps_the_saved_login(ac):
    await ac.put("/notify/settings", json={"mode": "online", "gmail": "me@gmail.com", "app_password": "abcdefghijklmnop"})
    offline = (await ac.put("/notify/settings", json={"mode": "offline"})).json()
    assert offline["mode"] == "offline" and offline["gmail"] == "me@gmail.com" and offline["password_set"] is True
    back = await ac.put("/notify/settings", json={"mode": "online"})                # no need to type the password again
    assert back.status_code == 200 and back.json()["mode"] == "online"


@pytest.mark.anyio
@pytest.mark.parametrize("payload", [{"mode": "sideways"}, {"mode": "offline", "gmail": "not an address"}])
async def test_bad_settings_are_refused(ac, payload):
    assert (await ac.put("/notify/settings", json=payload)).status_code == 400


@pytest.mark.anyio
async def test_the_test_button_needs_saved_settings_then_sends_one_real_email(ac, monkeypatch):
    assert (await ac.post("/notify/test", json={})).status_code == 400
    await ac.put("/notify/settings", json={"mode": "online", "gmail": "me@gmail.com", "app_password": "abcdefghijklmnop"})
    monkeypatch.setattr(smtplib, "SMTP", FakeSMTP)
    body = (await ac.post("/notify/test", json={})).json()
    assert body == {"status": "sent", "detail": "", "to": "me@gmail.com"}
    assert FakeSMTP.calls[-1] == ("send", "me@gmail.com")


@pytest.mark.anyio
async def test_the_test_e_mail_comes_from_the_sender_account_to_the_address_you_choose(ac, monkeypatch):
    seen = []

    class Recording(FakeSMTP):
        def send_message(self, msg):
            seen.append((msg["From"], msg["To"]))
    await ac.put("/notify/settings", json={"mode": "online", "gmail": "hulikamote.demo@gmail.com", "app_password": "abcdefghijklmnop"})
    monkeypatch.setattr(smtplib, "SMTP", Recording)
    body = (await ac.post("/notify/test", json={"to": "me@example.test"})).json()
    assert body["to"] == "me@example.test" and body["status"] == "sent"
    assert seen == [("HULI-KAMOTE <hulikamote.demo@gmail.com>", "me@example.test")]


@pytest.mark.anyio
async def test_the_test_button_explains_a_wrong_password(ac, monkeypatch):
    class Refusing(FakeSMTP):
        def login(self, user, password):
            raise smtplib.SMTPAuthenticationError(535, b"no")
    await ac.put("/notify/settings", json={"mode": "online", "gmail": "me@gmail.com", "app_password": "wrongwrongwrong1"})
    monkeypatch.setattr(smtplib, "SMTP", Refusing)
    body = (await ac.post("/notify/test", json={})).json()
    assert body["status"] == "failed" and "refused the login" in body["detail"]


@pytest.mark.anyio
async def test_the_supabase_project_is_saved_without_ever_returning_the_key(ac):
    response = await ac.put("/notify/settings", json={"mode": "online", "supabase_url": "https://abc.supabase.co/", "supabase_service_key": "sb secret.key"})
    body = response.json()
    assert response.status_code == 200 and body["mode"] == "online"
    assert body["cloud_url"] == "https://abc.supabase.co" and body["cloud_key_set"] is True
    assert "secret" not in response.text
    env = emailer.ENV_FILE.read_text().splitlines()
    assert "HK_SUPABASE_URL=https://abc.supabase.co" in env and "HK_SUPABASE_SERVICE_KEY=sbsecret.key" in env     # spaces dropped


@pytest.mark.anyio
async def test_online_is_allowed_with_only_the_cloud_set_up(ac):
    await ac.put("/notify/settings", json={"mode": "offline", "supabase_url": "https://abc.supabase.co", "supabase_service_key": "k"})
    assert (await ac.put("/notify/settings", json={"mode": "online"})).status_code == 200      # saved cloud is enough


@pytest.mark.anyio
@pytest.mark.parametrize("url", ["http://abc.supabase.co", "abc.supabase.co", "https://abc.supabase.co/rest/v1", "https://exa mple.co"])
async def test_a_bad_supabase_address_is_refused(ac, url):
    response = await ac.put("/notify/settings", json={"mode": "offline", "supabase_url": url, "supabase_service_key": "k"})
    assert response.status_code == 400 and "supabase.co" in response.json()["detail"]


@pytest.mark.anyio
async def test_the_cloud_test_button_says_what_to_fix(ac, monkeypatch):
    import cloud
    monkeypatch.setattr(cloud, "check", lambda: "Connected.")
    assert (await ac.post("/notify/cloud-test")).json() == {"ok": True, "detail": "Connected."}

    def broken():
        raise cloud.CloudError("Connected, but the tables are missing. Run supabase/schema.sql in the Supabase SQL editor.")
    monkeypatch.setattr(cloud, "check", broken)
    body = (await ac.post("/notify/cloud-test")).json()
    assert body["ok"] is False and "schema.sql" in body["detail"]


# ─── what each mode does with a confirmed ticket ─────────────────────────────

@pytest.mark.anyio
async def test_offline_leaves_the_notice_in_the_mailbox_even_without_an_email_address(ac, monkeypatch):
    sent = []
    monkeypatch.setattr(emailer, "send", lambda msg: sent.append(msg))
    await ac.put("/notify/settings", json={"mode": "offline"})
    await owner_with(ac, "user_003", "OFF 111", email="")
    await approved_ticket(ac, "OFF 111")

    notices = (await ac.get("/notify/notices", params={"user_id": "user_003"})).json()["notices"]
    assert sent == [] and [(n["status"], n["subject"]) for n in notices] == [("local", "Traffic violation recorded: No Helmet (OFF 111)")]


@pytest.mark.anyio
async def test_online_emails_the_motorist_and_keeps_a_record(ac, monkeypatch):
    sent = []
    monkeypatch.setattr(emailer, "send", lambda msg: sent.append(msg["To"]) or emailer.Result("sent", ""))
    await ac.put("/notify/settings", json={"mode": "online", "gmail": "me@gmail.com", "app_password": "abcdefghijklmnop"})
    await owner_with(ac, "user_001", "ONL 222", email="juan@example.test")
    await approved_ticket(ac, "ONL 222")

    assert sent == ["juan@example.test"]
    latest = (await ac.get("/notify/settings")).json()["notices"][0]
    assert (latest["status"], latest["to_email"], latest["user_name"]) == ("sent", "juan@example.test", "Juan Dela Cruz")


@pytest.mark.anyio
async def test_a_failed_email_is_recorded_with_its_reason_and_the_review_still_works(ac, monkeypatch):
    monkeypatch.setattr(emailer, "send", lambda msg: emailer.Result("failed", "network is down"))
    await ac.put("/notify/settings", json={"mode": "online", "gmail": "me@gmail.com", "app_password": "abcdefghijklmnop"})
    await owner_with(ac, "user_002", "BAD 333", email="maria@example.test")
    ticket = await approved_ticket(ac, "BAD 333")
    assert ticket["status"] == "approved"
    latest = (await ac.get("/notify/settings")).json()["notices"][0]
    assert (latest["status"], latest["detail"]) == ("failed", "network is down")


@pytest.mark.anyio
async def test_the_phone_app_asks_only_for_notices_newer_than_the_last_one_it_saw(ac):
    await ac.put("/notify/settings", json={"mode": "offline"})
    await owner_with(ac, "user_002", "NEW 666")
    await approved_ticket(ac, "NEW 666")
    first = (await ac.get("/notify/notices", params={"user_id": "user_002"})).json()["notices"]
    newest = first[0]["created_at"]
    assert (await ac.get("/notify/notices", params={"user_id": "user_002", "after": newest})).json()["notices"] == []
    await approved_ticket(ac, "NEW 666")
    fresh = (await ac.get("/notify/notices", params={"user_id": "user_002", "after": newest})).json()["notices"]
    assert len(fresh) == 1 and fresh[0]["created_at"] > newest


@pytest.mark.anyio
async def test_the_notice_carries_every_photo_of_the_ticket_to_the_phone_page_and_the_api(ac, monkeypatch, tmp_path):
    import evidence_files
    monkeypatch.setattr(evidence_files, "EVIDENCE_DIR", tmp_path)
    for name in ("f1.jpg", "f2.jpg", "f3.jpg"):
        (tmp_path / name).write_bytes(b"jpeg")
    await ac.put("/notify/settings", json={"mode": "offline"})
    await owner_with(ac, "user_003", "FRM 901")
    v = await store.add_violation("no_helmet", 0.9, "unregistered", plate_text="FRM 901", notify=False, session_id="frames1",
                                  evidence_paths=["f1.jpg", "f2.jpg", "f3.jpg", "missing.jpg"])
    await ac.patch(f"/violations/{v['id']}", json={"status": "approved"})

    notice = (await ac.get("/notify/notices", params={"user_id": "user_003", "limit": 1})).json()["notices"][0]
    assert notice["frames"] == ["f1.jpg", "f2.jpg", "f3.jpg"]                       # only photos that exist
    page = (await ac.get("/mailbox/user_003")).text
    assert page.count("/snapshots/evidence/f1.jpg") == 2 and "f3.jpg" in page       # a link and a picture for each


@pytest.mark.anyio
async def test_the_online_email_gets_the_photos_as_attachments(ac, monkeypatch, tmp_path):
    import evidence_files
    monkeypatch.setattr(evidence_files, "EVIDENCE_DIR", tmp_path)
    (tmp_path / "e1.jpg").write_bytes(b"jpeg1")
    (tmp_path / "e2.jpg").write_bytes(b"jpeg2")
    sent = []
    monkeypatch.setattr(emailer, "send", lambda msg: sent.append([p.get_filename() for p in msg.iter_attachments()]) or emailer.Result("sent", ""))
    await ac.put("/notify/settings", json={"mode": "online", "gmail": "me@gmail.com", "app_password": "abcdefghijklmnop"})
    await owner_with(ac, "user_001", "ATT 902", email="juan@example.test")
    v = await store.add_violation("no_helmet", 0.9, "unregistered", plate_text="ATT 902", notify=False, session_id="frames2",
                                  evidence_paths=["e1.jpg", "e2.jpg"])
    await ac.patch(f"/violations/{v['id']}", json={"status": "approved"})
    assert sent == [["e1.jpg", "e2.jpg"]]


# ─── the phone's page ────────────────────────────────────────────────────────

@pytest.mark.anyio
async def test_the_phone_page_lists_motorists_and_shows_their_notices(ac):
    await ac.put("/notify/settings", json={"mode": "offline"})
    await owner_with(ac, "user_003", "PHN 444")
    await approved_ticket(ac, "PHN 444")

    chooser = await ac.get("/mailbox")
    assert chooser.status_code == 200 and "Pedro Reyes" in chooser.text and "/mailbox/user_003" in chooser.text
    inbox = (await ac.get("/mailbox/user_003")).text
    assert "PHN 444" in inbox and "file an appeal" in inbox and 'http-equiv="refresh"' in inbox      # it updates itself


@pytest.mark.anyio
async def test_the_phone_page_cannot_be_used_to_inject_markup(ac):
    await ac.put("/notify/settings", json={"mode": "offline"})
    await owner_with(ac, "user_001", "A<B")
    await approved_ticket(ac, "A<B")
    inbox = (await ac.get("/mailbox/user_001")).text
    assert "A&lt;B" in inbox and "A<B" not in inbox


@pytest.mark.anyio
async def test_an_unknown_motorist_gets_a_plain_not_found_page(ac):
    assert "No such motorist" in (await ac.get("/mailbox/nobody")).text


# ─── the phone cloud and push, from the dashboard ────────────────────────────

@pytest.mark.anyio
async def test_demo_accounts_are_not_created_until_the_cloud_is_set_up(ac):
    response = await ac.post("/notify/cloud-demo-accounts")
    assert response.status_code == 400 and "service key" in response.json()["detail"]


@pytest.mark.anyio
async def test_demo_accounts_are_made_from_the_demo_motorists_and_every_plate_they_own(ac, monkeypatch):
    import cloud
    asked = []
    monkeypatch.setenv("HK_SUPABASE_URL", "https://abc.supabase.co")
    monkeypatch.setenv("HK_SUPABASE_SERVICE_KEY", "secret")
    monkeypatch.setattr(cloud, "sync_accounts", lambda accounts: asked.extend(accounts) or [{"plate": a["plate"], "status": "created", "detail": ""} for a in accounts])
    for plate in ("ABC 1234", "LP14LJA"):
        await ac.put(f"/registry/plates/{plate}", json={"user_id": "user_001"})
    await ac.put("/registry/plates/DEF 5678", json={"user_id": "user_002"})
    await ac.put("/registry/motorists/user_001/email", json={"email": "juan@example.test"})

    body = (await ac.post("/notify/cloud-demo-accounts")).json()
    by_name = {a["name"]: a for a in asked}
    assert {"Juan Dela Cruz", "Maria Santos"} <= set(by_name)                      # only motorists that own a plate get an account
    juan = by_name["Juan Dela Cruz"]
    assert juan["plate"] == "ABC 1234" and juan["password"] == "password123" and juan["email"] == "juan@example.test"
    assert set(juan["plates"]) >= {"ABC 1234", "LP14LJA"}
    assert len(body["results"]) == len(asked) and all(r["status"] == "created" for r in body["results"])


@pytest.mark.anyio
async def test_the_push_check_and_test_are_available_to_the_dashboard(ac, monkeypatch):
    import store
    monkeypatch.setattr(store, "push_status", lambda: {"ready": False, "detail": "No Firebase key"})
    assert (await ac.get("/notify/push-check")).json() == {"ready": False, "detail": "No Firebase key"}
    result = (await ac.post("/notify/push-test")).json()
    assert result["ready"] is False and result["sent"] == 0 and result["detail"] == "No Firebase key"
