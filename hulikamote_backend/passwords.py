"""
passwords.py - keep a password as a salted hash. The three mock motorists keep their plain-text demo passwords
and can still log in (verify_password accepts both).
"""
import hashlib
import hmac
import os

PREFIX = "pbkdf2$"
ROUNDS = 120_000


def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, ROUNDS)
    return f"{PREFIX}{salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    if stored.startswith(PREFIX):
        try:
            salt_hex, digest_hex = stored[len(PREFIX):].split("$")
            expected = bytes.fromhex(digest_hex)
            actual = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt_hex), ROUNDS)
        except ValueError:
            return False
        return hmac.compare_digest(actual, expected)
    return hmac.compare_digest(password.encode(), stored.encode())       # a mock account
