from datetime import UTC, datetime, timedelta

import secrets

import httpx
from fastapi import APIRouter, Depends, Header, HTTPException, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..db import get_db
from ..models import ServerCredential, ServerEnrollmentToken, TrustedServer
from ..schemas import (
    OrchestratorSpawnRequest,
    OrchestratorSpawnResponse,
    RegistryEnrollRequest,
    ServerCredentialListResponse,
    ServerCredentialProvisionResponse,
    ServerCredentialResponse,
    ServerCredentialUpsertRequest,
    ServerChallengeRequest,
    ServerChallengeResponse,
    ServerEnrollmentMintRequest,
    ServerEnrollmentMintResponse,
    ServerHeartbeatRequest,
    ServerListResponse,
    ServerProvisioningRequest,
    ServerRegisterRequest,
)
from ..server_auth import hash_server_secret, issue_server_challenge, verify_signed_registry_request

router = APIRouter(prefix="/servers", tags=["servers"])

HEARTBEAT_TTL_SECONDS = 60


def _persist_new_enrollment_token(db: Session, server_id_constraint: str | None, ttl_seconds: int) -> tuple[str, datetime]:
    token_plain = secrets.token_urlsafe(32)
    token_hash = hash_server_secret(token_plain)
    expires_at = datetime.now(UTC) + timedelta(seconds=ttl_seconds)
    db.add(
        ServerEnrollmentToken(
            token_hash=token_hash,
            expires_at=expires_at,
            server_id_constraint=server_id_constraint,
        )
    )
    db.commit()
    return token_plain, expires_at


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


@router.post("/registry/enroll", response_model=ServerCredentialProvisionResponse)
def registry_enroll(payload: RegistryEnrollRequest, db: Session = Depends(get_db)) -> ServerCredentialProvisionResponse:
    """Dedicated server exchanges a one-time enrollment token for registry signing credentials."""
    token_plain = payload.enrollment_token.strip()
    server_id = payload.server_id.strip()
    if token_plain == "" or server_id == "":
        raise HTTPException(status_code=400, detail="enrollment_token and server_id are required")
    token_hash = hash_server_secret(token_plain)
    row = db.scalar(
        select(ServerEnrollmentToken)
        .where(ServerEnrollmentToken.token_hash == token_hash)
        .with_for_update()
    )
    if row is None:
        raise HTTPException(status_code=401, detail="invalid enrollment token")
    if row.used_at is not None:
        raise HTTPException(status_code=401, detail="enrollment token already used")
    if row.expires_at < datetime.now(UTC):
        raise HTTPException(status_code=401, detail="enrollment token expired")
    if row.server_id_constraint is not None and row.server_id_constraint != server_id:
        raise HTTPException(
            status_code=400,
            detail="server_id does not match enrollment constraint",
        )

    key_id = f"enroll-{secrets.token_hex(8)}"
    secret = secrets.token_urlsafe(32)
    credential = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == server_id,
            ServerCredential.key_id == key_id,
        )
    )
    secret_hash = hash_server_secret(secret)
    if credential is None:
        credential = ServerCredential(
            server_id=server_id,
            key_id=key_id,
            secret_hash=secret_hash,
            is_active=True,
        )
        db.add(credential)
    else:
        credential.secret_hash = secret_hash
        credential.is_active = True

    row.used_at = datetime.now(UTC)
    db.commit()
    return ServerCredentialProvisionResponse(
        server_id=server_id,
        key_id=key_id,
        secret=secret,
        is_active=True,
    )


@router.post("/admin/enrollment-tokens", response_model=ServerEnrollmentMintResponse)
def mint_enrollment_token(
    payload: ServerEnrollmentMintRequest,
    db: Session = Depends(get_db),
    x_gs_admin_token: str | None = Header(default=None),
) -> ServerEnrollmentMintResponse:
    _require_admin_token(x_gs_admin_token)
    ttl = payload.ttl_seconds
    if ttl is None:
        ttl = settings.registry_enrollment_default_ttl_sec
    ttl = max(60, min(ttl, settings.registry_enrollment_max_ttl_sec))

    constraint = payload.server_id.strip() if payload.server_id else None
    if constraint == "":
        constraint = None

    token_plain, expires_at = _persist_new_enrollment_token(db, constraint, ttl)
    return ServerEnrollmentMintResponse(
        enrollment_token=token_plain,
        expires_at=expires_at,
        server_id_constraint=constraint,
    )


@router.post("/admin/provision", response_model=ServerCredentialProvisionResponse)
def provision_server_credentials(
    payload: ServerProvisioningRequest,
    db: Session = Depends(get_db),
    x_gs_admin_token: str | None = Header(default=None),
) -> ServerCredentialProvisionResponse:
    """Generate a new server_id/key_id/secret triple and store the secret hash (returns secret once)."""
    _require_admin_token(x_gs_admin_token)
    server_id = (payload.server_id or "").strip()
    if server_id == "":
        server_id = f"server-{secrets.token_hex(6)}"
    key_id = (payload.key_id or "").strip()
    if key_id == "":
        key_id = f"key-{secrets.token_hex(8)}"
    secret = secrets.token_urlsafe(32)

    credential = db.scalar(
        select(ServerCredential).where(
            ServerCredential.server_id == server_id,
            ServerCredential.key_id == key_id,
        )
    )
    secret_hash = hash_server_secret(secret)
    if credential is None:
        credential = ServerCredential(
            server_id=server_id,
            key_id=key_id,
            secret_hash=secret_hash,
            is_active=True,
        )
        db.add(credential)
    else:
        credential.secret_hash = secret_hash
        credential.is_active = True
    db.commit()
    return ServerCredentialProvisionResponse(
        server_id=credential.server_id,
        key_id=credential.key_id,
        secret=secret,
        is_active=credential.is_active,
    )


@router.post("/admin/orchestrator/spawn", response_model=OrchestratorSpawnResponse)
def orchestrator_spawn_instance(
    payload: OrchestratorSpawnRequest,
    db: Session = Depends(get_db),
    x_gs_admin_token: str | None = Header(default=None),
) -> OrchestratorSpawnResponse:
    """Mint an enrollment token and ask the node agent on the VDS to start a dedicated Docker container."""
    _require_admin_token(x_gs_admin_token)

    _orchestrator_base_url()
    _orchestrator_headers()

    public_backend = (payload.backend_url or "").strip()
    if public_backend == "":
        public_backend = settings.public_backend_url.strip()
    if public_backend == "":
        raise HTTPException(
            status_code=400,
            detail="Set backend_url on this request or configure GOONSTRIKE_PUBLIC_BACKEND_URL so containers can reach the API.",
        )

    server_id = (payload.server_id or "").strip()
    if server_id == "":
        server_id = f"vds-{payload.port}-{secrets.token_hex(4)}"

    ttl = payload.enrollment_ttl_seconds
    if ttl is None:
        ttl = settings.registry_enrollment_default_ttl_sec
    ttl = max(60, min(ttl, settings.registry_enrollment_max_ttl_sec))

    token_plain, expires_at = _persist_new_enrollment_token(db, server_id, ttl)

    image = (payload.docker_image or "").strip()
    if image == "":
        image = settings.orchestrator_default_image.strip()

    agent_body = {
        "server_id": server_id,
        "port": payload.port,
        "backend_url": public_backend.rstrip("/"),
        "enrollment_token": token_plain,
        "map_id": payload.map_id,
        "mode_id": payload.mode_id,
        "docker_image": image,
        "public_host": (payload.public_host or "").strip() or None,
    }

    orch_out = _orchestrator_request("POST", "/v1/instances", json_payload=agent_body, timeout_sec=120.0)
    return OrchestratorSpawnResponse(
        server_id=server_id,
        enrollment_expires_at=expires_at,
        orchestrator=orch_out,
    )


def _orchestrator_headers() -> dict[str, str]:
    secret = settings.orchestrator_secret.strip()
    if secret == "":
        raise HTTPException(status_code=503, detail="GOONSTRIKE_ORCHESTRATOR_SECRET is not configured")
    return {"X-GS-Agent-Token": secret}


def _orchestrator_base_url() -> str:
    base = settings.orchestrator_url.strip()
    if base == "":
        raise HTTPException(status_code=503, detail="GOONSTRIKE_ORCHESTRATOR_URL is not configured")
    return base.rstrip("/")


def _orchestrator_request(method: str, path: str, *, json_payload: dict | None = None, timeout_sec: float = 60.0) -> dict:
    url = _orchestrator_base_url() + path
    try:
        resp = httpx.request(
            method=method,
            url=url,
            headers=_orchestrator_headers(),
            json=json_payload,
            timeout=timeout_sec,
        )
    except httpx.RequestError as exc:
        raise HTTPException(status_code=502, detail=f"orchestrator unreachable: {exc}") from exc

    try:
        data = resp.json()
    except ValueError:
        data = {"raw": resp.text}

    if resp.status_code >= 400:
        raise HTTPException(
            status_code=502,
            detail={
                "agent_status": resp.status_code,
                "agent_detail": data if isinstance(data, dict) else {"raw": resp.text},
            },
        )
    return data if isinstance(data, dict) else {"result": data}


@router.get("/admin/orchestrator/instances")
def orchestrator_list_instances(
    x_gs_admin_token: str | None = Header(default=None),
) -> dict:
    """Proxy: list dedicated containers the node agent sees on this host."""
    _require_admin_token(x_gs_admin_token)
    return _orchestrator_request("GET", "/v1/instances", timeout_sec=30.0)


@router.get("/admin/orchestrator/instances/{port}")
def orchestrator_get_instance(
    port: int,
    x_gs_admin_token: str | None = Header(default=None),
) -> dict:
    _require_admin_token(x_gs_admin_token)
    if port < 1024 or port > 65534:
        raise HTTPException(status_code=400, detail="port out of range")
    return _orchestrator_request("GET", f"/v1/instances/{port}", timeout_sec=30.0)


@router.get("/admin/orchestrator/instances/{port}/logs")
def orchestrator_get_instance_logs(
    port: int,
    tail: int = 200,
    x_gs_admin_token: str | None = Header(default=None),
) -> dict:
    _require_admin_token(x_gs_admin_token)
    if port < 1024 or port > 65534:
        raise HTTPException(status_code=400, detail="port out of range")
    safe_tail = max(1, min(tail, 2000))
    return _orchestrator_request("GET", f"/v1/instances/{port}/logs?tail={safe_tail}", timeout_sec=60.0)


@router.delete("/admin/orchestrator/instances/{port}")
def orchestrator_delete_instance(
    port: int,
    x_gs_admin_token: str | None = Header(default=None),
) -> dict:
    """Proxy: docker rm -f goonstrike-dedicated-{port} via the node agent."""
    _require_admin_token(x_gs_admin_token)
    if port < 1024 or port > 65534:
        raise HTTPException(status_code=400, detail="port out of range")
    return _orchestrator_request("DELETE", f"/v1/instances/{port}", timeout_sec=60.0)


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
