import hashlib
import hmac
import secrets
from datetime import UTC, datetime, timedelta

from fastapi import HTTPException, Request
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from .config import settings
from .models import ServerAuthNonce, ServerCredential
from .schemas import ServerChallengeResponse


def hash_server_secret(secret: str) -> str:
    return hashlib.sha256(secret.encode("utf-8")).hexdigest()


def verify_server_secret(secret: str, secret_hash: str) -> bool:
    return hmac.compare_digest(hash_server_secret(secret), secret_hash)


def ensure_bootstrap_credential(db: Session) -> None:
    if (
        settings.registry_bootstrap_server_id.strip() == ""
        or settings.registry_bootstrap_key_id.strip() == ""
        or settings.registry_bootstrap_secret.strip() == ""
    ):
        return
    server_id = settings.registry_bootstrap_server_id.strip()
    key_id = settings.registry_bootstrap_key_id.strip()
    secret_hash = hash_server_secret(settings.registry_bootstrap_secret.strip())
    existing = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == server_id,
            ServerCredential.key_id == key_id,
        )
    )
    if existing is None:
        db.add(
            ServerCredential(
                server_id=server_id,
                key_id=key_id,
                secret_hash=secret_hash,
                is_active=True,
            )
        )
        db.commit()
        return
    existing.secret_hash = secret_hash
    existing.is_active = True
    db.commit()


def issue_server_challenge(db: Session, server_id: str, key_id: str) -> ServerChallengeResponse:
    _cleanup_expired_nonces(db)
    credential = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == server_id,
            ServerCredential.key_id == key_id,
            ServerCredential.is_active.is_(True),
        )
    )
    if credential is None:
        raise HTTPException(status_code=403, detail="server credential not found or inactive")

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


async def verify_signed_registry_request(
    request: Request,
    db: Session,
    expected_server_id: str | None = None,
) -> str:
    if not settings.registry_auth_required:
        return expected_server_id or ""

    server_id = _required_header(request, "X-GS-Server-Id")
    key_id = _required_header(request, "X-GS-Key-Id")
    nonce = _required_header(request, "X-GS-Nonce")
    challenge = _required_header(request, "X-GS-Challenge")
    signature = _required_header(request, "X-GS-Signature")
    body = await request.body()
    payload_hash = hashlib.sha256(body).hexdigest()

    if expected_server_id is not None and server_id != expected_server_id:
        raise HTTPException(status_code=401, detail="server id mismatch")

    _cleanup_expired_nonces(db)
    auth_nonce = db.scalar(
        select(ServerAuthNonce).where(
            ServerAuthNonce.server_id == server_id,
            ServerAuthNonce.key_id == key_id,
            ServerAuthNonce.nonce == nonce,
            ServerAuthNonce.challenge == challenge,
        )
    )
    if auth_nonce is None:
        raise HTTPException(status_code=401, detail="invalid challenge")
    if auth_nonce.used_at is not None:
        raise HTTPException(status_code=401, detail="challenge already used")
    if auth_nonce.expires_at < datetime.now(UTC):
        raise HTTPException(status_code=401, detail="challenge expired")

    credential = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == server_id,
            ServerCredential.key_id == key_id,
            ServerCredential.is_active.is_(True),
        )
    )
    if credential is None:
        raise HTTPException(status_code=403, detail="server credential not found or inactive")

    canonical = _canonical_string(
        method=request.method.upper(),
        path=request.url.path,
        server_id=server_id,
        key_id=key_id,
        nonce=nonce,
        challenge=challenge,
        payload_hash=payload_hash,
    )
    expected_signature = _sign_canonical(canonical, credential.secret_hash)
    if not hmac.compare_digest(signature, expected_signature):
        raise HTTPException(status_code=401, detail="invalid signature")

    auth_nonce.used_at = datetime.now(UTC)
    db.commit()
    return server_id


def _required_header(request: Request, header_name: str) -> str:
    value = request.headers.get(header_name, "").strip()
    if value == "":
        raise HTTPException(status_code=401, detail=f"missing {header_name.lower()}")
    return value


def _canonical_string(
    *,
    method: str,
    path: str,
    server_id: str,
    key_id: str,
    nonce: str,
    challenge: str,
    payload_hash: str,
) -> str:
    return "\n".join([method, path, server_id, key_id, nonce, challenge, payload_hash])


def _sign_canonical(canonical: str, secret_hash: str) -> str:
    # The server stores only hashed secrets and signs canonical payload using this derived key.
    return hashlib.sha256((canonical + "\n" + secret_hash).encode("utf-8")).hexdigest()


def _cleanup_expired_nonces(db: Session) -> None:
    cutoff = datetime.now(UTC) - timedelta(seconds=settings.registry_nonce_ttl_sec)
    db.execute(
        delete(ServerAuthNonce).where(
            ServerAuthNonce.expires_at < cutoff,
        )
    )
    db.commit()
