"""passwords.py - hashed passwords for new accounts, plain text still accepted for the mock accounts."""
from passwords import hash_password, verify_password


def test_a_hashed_password_checks_out_and_is_not_stored_readable():
    stored = hash_password("s3cret-pass")
    assert "s3cret-pass" not in stored and stored.startswith("pbkdf2$")
    assert verify_password("s3cret-pass", stored)
    assert not verify_password("s3cret-pasS", stored)


def test_the_same_password_hashes_differently_each_time():
    assert hash_password("same") != hash_password("same")


def test_mock_accounts_with_plain_text_passwords_still_log_in():
    assert verify_password("password123", "password123")
    assert not verify_password("password124", "password123")


def test_a_damaged_hash_never_matches():
    assert not verify_password("x", "pbkdf2$not-hex$also-not-hex")
    assert not verify_password("x", "pbkdf2$")
