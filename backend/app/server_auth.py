from __future__ import annotations

from datetime import UTC, datetime, timedelta
import hashlib
import secrets

from fastapi import HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from .config import settings
from .models import ServerAuthNonce, ServerCredential
from .schemas import ServerChallengeResponse


def hash_server_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def issue_server_challenge(db: Session, server_id: str, key_id: str) -> ServerChallengeResponse:
    server_id = server_id.strip()
    key_id = key_id.strip()
    if server_id == "" or key_id == "":
        raise HTTPException(status_code=400, detail="server_id and key_id are required")

    credential = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == server_id,
            ServerCredential.key_id == key_id,
            ServerCredential.is_active.is_(True),
        )
    )
    if credential is None:
        raise HTTPException(status_code=401, detail="unknown or inactive server credentials")

    nonce = secrets.token_urlsafe(24)
    challenge = secrets.token_urlsafe(24)
    expires_at = datetime.now(UTC) + timedelta(seconds=settings.registry_challenge_ttl_sec)
    db.add(
        ServerAuthNonce(
            server_id=server_id,
            nonce=nonce,
            challenge=challenge,
            key_id=key_id,
            expires_at=expires_at,
            used_at=None,
        )
    )
    db.commit()
    return ServerChallengeResponse(
        server_id=server_id,
        key_id=key_id,
        nonce=nonce,
        challenge=challenge,
        expires_at=expires_at,
    )


async def verify_signed_registry_request(request: Request, db: Session, expected_server_id: str | None = None) -> str:
    if not settings.registry_auth_required:
        return (expected_server_id or "").strip()

    server_id = (request.headers.get("X-GS-Server-Id") or "").strip()
    key_id = (request.headers.get("X-GS-Key-Id") or "").strip()
    nonce = (request.headers.get("X-GS-Nonce") or "").strip()
    challenge = (request.headers.get("X-GS-Challenge") or "").strip()
    signature = (request.headers.get("X-GS-Signature") or "").strip()

    if "" in (server_id, key_id, nonce, challenge, signature):
        raise HTTPException(status_code=401, detail="missing registry signature headers")
    if expected_server_id is not None and expected_server_id.strip() != server_id:
        raise HTTPException(status_code=401, detail="server_id mismatch")

    nonce_row = db.scalar(
        select(ServerAuthNonce).where(
            ServerAuthNonce.server_id == server_id,
            ServerAuthNonce.key_id == key_id,
            ServerAuthNonce.nonce == nonce,
            ServerAuthNonce.challenge == challenge,
        )
    )
    if nonce_row is None:
        raise HTTPException(status_code=401, detail="invalid challenge")
    if nonce_row.used_at is not None:
        raise HTTPException(status_code=409, detail="challenge already used")
    if nonce_row.expires_at < datetime.now(UTC):
        raise HTTPException(status_code=401, detail="challenge expired")

    credential = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == server_id,
            ServerCredential.key_id == key_id,
            ServerCredential.is_active.is_(True),
        )
    )
    if credential is None:
        raise HTTPException(status_code=401, detail="unknown or inactive server credentials")

    raw_body = await request.body()
    payload_hash = hashlib.sha256(raw_body).hexdigest()
    canonical = "\n".join(
        [
            request.method.upper(),
            request.url.path,
            server_id,
            key_id,
            nonce,
            challenge,
            payload_hash,
        ]
    )
    expected_signature = hashlib.sha256(f"{canonical}\n{credential.secret_hash}".encode("utf-8")).hexdigest()
    if not secrets.compare_digest(signature, expected_signature):
        raise HTTPException(status_code=401, detail="invalid registry signature")

    nonce_row.used_at = datetime.now(UTC)
    db.commit()
    return server_id


def ensure_bootstrap_credential(db: Session) -> None:
    server_id = settings.registry_bootstrap_server_id.strip()
    key_id = settings.registry_bootstrap_key_id.strip()
    secret = settings.registry_bootstrap_secret.strip()
    if "" in (server_id, key_id, secret):
        return

    row = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == server_id,
            ServerCredential.key_id == key_id,
        )
    )
    secret_hash = hash_server_secret(secret)
    if row is None:
        db.add(
            ServerCredential(
                server_id=server_id,
                key_id=key_id,
                secret_hash=secret_hash,
                is_active=True,
            )
        )
    else:
        row.secret_hash = secret_hash
        row.is_active = True
    db.commit()
