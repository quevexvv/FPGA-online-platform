from hashlib import sha256
from hmac import new as hmac_new
from secrets import token_urlsafe

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

password_hasher = PasswordHasher()
_dummy_hash = password_hasher.hash(token_urlsafe(32))


def hash_password(password: str) -> str:
    return password_hasher.hash(password)


def verify_password(password: str, encoded: str | None) -> bool:
    try:
        valid = password_hasher.verify(encoded or _dummy_hash, password)
        return valid and encoded is not None
    except (VerificationError, InvalidHashError):
        return False


def new_token() -> str:
    return token_urlsafe(32)


def token_digest(token: str) -> str:
    return sha256(token.encode()).hexdigest()


def csrf_token(session_token: str) -> str:
    return hmac_new(session_token.encode(), b"fpga-csrf", sha256).hexdigest()
