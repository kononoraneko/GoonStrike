import base64
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone
from typing import Annotated

from fastapi import Depends, Header, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .models import Account

JWT_ALG = "HS256"
PASSWORD_ITERATIONS = 210_000


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, PASSWORD_ITERATIONS)
    return "pbkdf2_sha256$%d$%s$%s" % (
        PASSWORD_ITERATIONS,
        base64.urlsafe_b64encode(salt).decode("ascii"),
        base64.urlsafe_b64encode(digest).decode("ascii"),
    )


def verify_password(password: str, encoded_hash: str) -> bool:
    try:
        scheme, iterations_raw, salt_raw, digest_raw = encoded_hash.split("$", 3)
        if scheme != "pbkdf2_sha256":
            return False
        iterations = int(iterations_raw)
        salt = base64.urlsafe_b64decode(salt_raw.encode("ascii"))
        expected = base64.urlsafe_b64decode(digest_raw.encode("ascii"))
    except (ValueError, TypeError):
        return False
    actual = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, iterations)
    return hmac.compare_digest(actual, expected)


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_access_token(account: Account) -> str:
    exp = utcnow() + timedelta(minutes=settings.access_token_minutes)
    payload = {
        "sub": str(account.id),
        "email": account.email,
        "typ": "access",
        "exp": int(exp.timestamp()),
    }
    return _encode_jwt(payload)


def decode_access_token(token: str) -> dict:
    payload = _decode_jwt(token)
    if payload.get("typ") != "access":
        raise HTTPException(status_code=401, detail="invalid token type")
    return payload


def get_current_account(
    db: Annotated[Session, Depends(get_db)],
    authorization: Annotated[str | None, Header()] = None,
) -> Account:
    token = _bearer_token(authorization)
    payload = decode_access_token(token)
    account_id = int(payload.get("sub", 0))
    account = db.get(Account, account_id)
    if account is None or not account.is_active:
        raise HTTPException(status_code=401, detail="account not found")
    return account


def get_optional_account(
    db: Annotated[Session, Depends(get_db)],
    authorization: Annotated[str | None, Header()] = None,
) -> Account | None:
    if authorization is None or not authorization.strip():
        return None
    try:
        token = _bearer_token(authorization)
        payload = decode_access_token(token)
        account_id = int(payload.get("sub", 0))
    except HTTPException:
        return None
    return db.scalar(select(Account).where(Account.id == account_id, Account.is_active.is_(True)))


def _bearer_token(authorization: str | None) -> str:
    if authorization is None:
        raise HTTPException(status_code=401, detail="missing authorization")
    parts = authorization.strip().split(" ", 1)
    if len(parts) != 2 or parts[0].lower() != "bearer" or parts[1].strip() == "":
        raise HTTPException(status_code=401, detail="invalid authorization")
    return parts[1].strip()


def _encode_jwt(payload: dict) -> str:
    header = {"alg": JWT_ALG, "typ": "JWT"}
    header_b64 = _b64_json(header)
    payload_b64 = _b64_json(payload)
    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")
    signature = hmac.new(settings.auth_secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    return f"{header_b64}.{payload_b64}.{_b64_bytes(signature)}"


def _decode_jwt(token: str) -> dict:
    parts = token.split(".")
    if len(parts) != 3:
        raise HTTPException(status_code=401, detail="invalid token")
    signing_input = f"{parts[0]}.{parts[1]}".encode("ascii")
    expected = hmac.new(settings.auth_secret.encode("utf-8"), signing_input, hashlib.sha256).digest()
    actual = _b64_decode(parts[2])
    if not hmac.compare_digest(actual, expected):
        raise HTTPException(status_code=401, detail="invalid token signature")
    payload = json.loads(_b64_decode(parts[1]).decode("utf-8"))
    if int(payload.get("exp", 0)) < int(utcnow().timestamp()):
        raise HTTPException(status_code=401, detail="token expired")
    return payload


def _b64_json(value: dict) -> str:
    return _b64_bytes(json.dumps(value, separators=(",", ":")).encode("utf-8"))


def _b64_bytes(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).decode("ascii").rstrip("=")


def _b64_decode(value: str) -> bytes:
    padding = "=" * (-len(value) % 4)
    return base64.urlsafe_b64decode((value + padding).encode("ascii"))
