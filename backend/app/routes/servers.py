from datetime import UTC, datetime, timedelta

import secrets

from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..models import ServerCredential, TrustedServer
from ..schemas import (
    ServerCredentialListResponse,
    ServerCredentialResponse,
    ServerCredentialUpsertRequest,
    ServerChallengeRequest,
    ServerChallengeResponse,
    ServerHeartbeatRequest,
    ServerListResponse,
    ServerRegisterRequest,
)
from ..server_auth import hash_server_secret, issue_server_challenge, verify_signed_registry_request

router = APIRouter(prefix="/servers", tags=["servers"])

HEARTBEAT_TTL_SECONDS = 60


@router.get("", response_model=ServerListResponse)
def list_servers(db: Session = Depends(get_db)) -> ServerListResponse:
    cutoff = datetime.now(UTC) - timedelta(seconds=HEARTBEAT_TTL_SECONDS)
    rows = db.scalars(
        select(TrustedServer)
        .where(
            TrustedServer.is_trusted.is_(True),
            TrustedServer.is_online.is_(True),
            TrustedServer.last_heartbeat_at >= cutoff,
        )
        .order_by(TrustedServer.display_name.asc())
    ).all()
    return ServerListResponse(servers=list(rows))


@router.post("/challenge", response_model=ServerChallengeResponse)
def create_server_challenge(payload: ServerChallengeRequest, db: Session = Depends(get_db)) -> ServerChallengeResponse:
    return issue_server_challenge(db, payload.server_id, payload.key_id)


@router.post("/admin/credentials", response_model=ServerCredentialResponse)
def upsert_server_credential(
    payload: ServerCredentialUpsertRequest,
    db: Session = Depends(get_db),
    x_gs_admin_token: str | None = Header(default=None),
) -> ServerCredentialResponse:
    _require_admin_token(x_gs_admin_token)

    credential = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == payload.server_id,
            ServerCredential.key_id == payload.key_id,
        )
    )
    if credential is None:
        credential = ServerCredential(
            server_id=payload.server_id,
            key_id=payload.key_id,
            secret_hash=hash_server_secret(payload.secret),
            is_active=payload.is_active,
        )
        db.add(credential)
    else:
        credential.secret_hash = hash_server_secret(payload.secret)
        credential.is_active = payload.is_active
    db.commit()
    return ServerCredentialResponse(
        server_id=credential.server_id,
        key_id=credential.key_id,
        is_active=credential.is_active,
    )


@router.get("/admin/credentials", response_model=ServerCredentialListResponse)
def list_server_credentials(
    db: Session = Depends(get_db),
    x_gs_admin_token: str | None = Header(default=None),
) -> ServerCredentialListResponse:
    _require_admin_token(x_gs_admin_token)
    rows = db.scalars(
        select(ServerCredential).order_by(
            ServerCredential.server_id.asc(),
            ServerCredential.key_id.asc(),
        )
    ).all()
    return ServerCredentialListResponse(
        credentials=[
            ServerCredentialResponse(
                server_id=row.server_id,
                key_id=row.key_id,
                is_active=row.is_active,
            )
            for row in rows
        ]
    )


@router.post("/register", response_model=ServerListResponse)
async def register_server(
    payload: ServerRegisterRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> ServerListResponse:
    authed_server_id = await verify_signed_registry_request(request, db, expected_server_id=payload.server_id)
    now = datetime.now(UTC)
    server = db.scalar(select(TrustedServer).where(TrustedServer.server_id == authed_server_id))
    if server is None:
        server = TrustedServer(server_id=authed_server_id)
        db.add(server)

    server.display_name = payload.display_name
    server.host = payload.host
    server.port = payload.port
    server.map_id = payload.map_id
    server.mode_id = payload.mode_id
    server.current_players = payload.current_players
    server.max_players = payload.max_players
    server.is_trusted = True
    server.is_online = True
    server.last_heartbeat_at = now
    db.commit()
    return list_servers(db)


@router.post("/{server_id}/heartbeat", response_model=ServerListResponse)
async def heartbeat_server(
    server_id: str,
    payload: ServerHeartbeatRequest,
    request: Request,
    db: Session = Depends(get_db),
) -> ServerListResponse:
    await verify_signed_registry_request(request, db, expected_server_id=server_id)
    server = db.scalar(select(TrustedServer).where(TrustedServer.server_id == server_id))
    if server is not None:
        server.map_id = payload.map_id
        server.mode_id = payload.mode_id
        server.current_players = payload.current_players
        server.max_players = payload.max_players
        server.is_online = payload.is_online
        server.last_heartbeat_at = datetime.now(UTC)
        db.commit()
    return list_servers(db)


@router.post("/{server_id}/offline", response_model=ServerListResponse)
async def mark_server_offline(server_id: str, request: Request, db: Session = Depends(get_db)) -> ServerListResponse:
    await verify_signed_registry_request(request, db, expected_server_id=server_id)
    server = db.scalar(select(TrustedServer).where(TrustedServer.server_id == server_id))
    if server is not None:
        server.is_online = False
        server.last_heartbeat_at = datetime.now(UTC)
        db.commit()
    return list_servers(db)


def _require_admin_token(x_gs_admin_token: str | None) -> None:
    expected = settings.registry_admin_token.strip()
    if expected == "":
        raise HTTPException(status_code=403, detail="registry admin token is not configured")
    provided = (x_gs_admin_token or "").strip()
    if provided == "" or not secrets.compare_digest(provided, expected):
        raise HTTPException(status_code=401, detail="invalid registry admin token")
