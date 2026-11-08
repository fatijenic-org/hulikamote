"""emailer.py - what the motorist reads, which way a notice goes (online or offline), and sending without a real server."""
import smtplib

import pytest

import emailer
from tests.helpers import FakeSMTP

OWNER = {"name": "Juan Dela Cruz", "email": "juan@example.test"}
TICKET = {"id": "ab12cd34-0000-4000-8000-000000000000", "cls": "no_helmet", "plate_text": "ABC 1234",
          "timestamp": "2026-10-28T08:15:00+00:00"}


def configure(monkeypatch, **env):
    for key, value in env.items():
        monkeypatch.setenv(f"HK_{key}", value)


def test_the_message_says_what_was_recorded_and_how_to_appeal(monkeypatch):
    configure(monkeypatch, SMTP_FROM="sender@example.test")
    msg = emailer.build_message(OWNER, TICKET)
    body = msg.get_content()
    assert msg["To"] == "juan@example.test" and msg["From"] == "HULI-KAMOTE <sender@example.test>"
    assert msg["Subject"] == "Traffic violation recorded: No Helmet (ABC 1234)"
    for expected in ("Juan Dela Cruz", "ABC 1234", "No Helmet", "AB12CD34", "file an appeal"):
        assert expected in body
    assert "no legal weight" in body                       # the thesis says nothing it logs is official


def test_a_motorist_without_an_address_still_gets_a_message_for_the_mailbox():
    assert emailer.build_message({"name": "Pedro"}, TICKET)["To"] == ""


# ─── online or offline ───────────────────────────────────────────────────────

def test_with_nothing_set_up_it_is_offline():
    assert emailer.mode() == "offline"


def test_a_mail_server_makes_it_online_and_an_explicit_choice_wins(monkeypatch):
    configure(monkeypatch, SMTP_HOST="smtp.example.test")
    assert emailer.mode() == "online"
    configure(monkeypatch, NOTIFY_MODE="offline")
    assert emailer.mode() == "offline"
    configure(monkeypatch, NOTIFY_MODE="online", SMTP_HOST="")
    assert emailer.mode() == "online"


def test_settings_are_read_from_the_env_file(monkeypatch):
    monkeypatch.delenv("HK_SMTP_USER")
    emailer.ENV_FILE.write_text("HK_SMTP_USER=from-file@example.test\n")
    assert emailer.settings()["user"] == "from-file@example.test"
    assert emailer.settings()["sender"] == "from-file@example.test"        # the login name is the sender unless told otherwise


# ─── sending ─────────────────────────────────────────────────────────────────

def test_with_a_mail_server_it_connects_secures_logs_in_and_sends(monkeypatch):
    configure(monkeypatch, SMTP_HOST="smtp.example.test", SMTP_PORT="2525", SMTP_USER="me@example.test", SMTP_PASSWORD="app-password")
    monkeypatch.setattr(smtplib, "SMTP", FakeSMTP)
    assert emailer.send(emailer.build_message(OWNER, TICKET)) == emailer.Result("sent", "")
    assert FakeSMTP.calls == [("connect", "smtp.example.test", 2525, emailer.TIMEOUT_S), ("starttls",),
                              ("login", "me@example.test", "app-password"), ("send", "juan@example.test")]


def test_ssl_security_uses_a_secure_connection_from_the_start(monkeypatch):
    class FakeSSL(FakeSMTP):
        pass
    configure(monkeypatch, SMTP_HOST="smtp.example.test", SMTP_SECURITY="ssl", SMTP_USER="me@example.test", SMTP_PASSWORD="x")
    monkeypatch.setattr(smtplib, "SMTP_SSL", FakeSSL)
    assert emailer.send(emailer.build_message(OWNER, TICKET)).status == "sent"
    assert ("starttls",) not in FakeSMTP.calls


def test_a_wrong_password_is_explained_without_repeating_it(monkeypatch):
    class Refusing(FakeSMTP):
        def login(self, user, password):
            raise smtplib.SMTPAuthenticationError(535, b"bad password")
    configure(monkeypatch, SMTP_HOST="smtp.example.test", SMTP_USER="me@example.test", SMTP_PASSWORD="hunter2")
    monkeypatch.setattr(smtplib, "SMTP", Refusing)
    result = emailer.send(emailer.build_message(OWNER, TICKET))
    assert result.status == "failed" and "refused the login" in result.detail and "hunter2" not in result.detail


def test_a_server_that_cannot_be_reached_gives_failed_with_the_reason(monkeypatch):
    def unreachable(*_, **__):
        raise OSError("network is down")
    configure(monkeypatch, SMTP_HOST="smtp.example.test")
    monkeypatch.setattr(smtplib, "SMTP", unreachable)
    assert emailer.send(emailer.build_message(OWNER, TICKET)) == emailer.Result("failed", "network is down")


@pytest.mark.parametrize("host,to,reason", [("", "juan@example.test", "No mail server"), ("smtp.example.test", "", "no e-mail address")])
def test_nothing_is_sent_without_a_server_or_an_address(monkeypatch, host, to, reason):
    configure(monkeypatch, SMTP_HOST=host)
    result = emailer.send(emailer.build_message({"name": "Juan", "email": to}, TICKET))
    assert result.status == "failed" and reason in result.detail
