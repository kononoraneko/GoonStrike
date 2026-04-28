from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from .config import settings
from .db import Base, engine
from . import models  # noqa: F401 - imported so SQLAlchemy registers models
from .routes import health, servers
from .server_auth import ensure_bootstrap_credential


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name)
    allowed_origins = [x.strip() for x in settings.admin_panel_allowed_origins.split(",") if x.strip() != ""]
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=False,
        allow_methods=["GET", "POST", "DELETE", "OPTIONS"],
        allow_headers=["*"],
    )
    app.include_router(health.router)
    app.include_router(servers.router)
    return app


app = create_app()


@app.on_event("startup")
def create_tables() -> None:
    # Good enough for local/dev. Replace with Alembic before production migrations.
    Base.metadata.create_all(bind=engine)
    _apply_dev_schema_patches()
    from .db import SessionLocal

    with SessionLocal() as db:
        ensure_bootstrap_credential(db)


def _apply_dev_schema_patches() -> None:
    # create_all does not alter existing dev tables. Keep this tiny patch until Alembic exists.
    with engine.begin() as conn:
        conn.execute(text("ALTER TABLE players ADD COLUMN IF NOT EXISTS account_id INTEGER"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_players_account_id ON players (account_id)"))
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS server_credentials (
                    id SERIAL PRIMARY KEY,
                    server_id VARCHAR(128) NOT NULL,
                    key_id VARCHAR(128) NOT NULL,
                    secret_hash VARCHAR(256) NOT NULL,
                    is_active BOOLEAN NOT NULL DEFAULT TRUE,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    CONSTRAINT uq_server_credentials_server_key UNIQUE (server_id, key_id)
                )
                """
            )
        )
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS server_auth_nonces (
                    id SERIAL PRIMARY KEY,
                    server_id VARCHAR(128) NOT NULL,
                    nonce VARCHAR(128) NOT NULL,
                    challenge VARCHAR(128) NOT NULL,
                    key_id VARCHAR(128) NOT NULL,
                    expires_at TIMESTAMPTZ NOT NULL,
                    used_at TIMESTAMPTZ NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    CONSTRAINT uq_server_auth_nonces_nonce UNIQUE (nonce)
                )
                """
            )
        )
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_credentials_server_id ON server_credentials (server_id)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_credentials_key_id ON server_credentials (key_id)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_auth_nonces_server_id ON server_auth_nonces (server_id)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_auth_nonces_key_id ON server_auth_nonces (key_id)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_auth_nonces_nonce ON server_auth_nonces (nonce)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_auth_nonces_challenge ON server_auth_nonces (challenge)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_auth_nonces_expires_at ON server_auth_nonces (expires_at)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_auth_nonces_used_at ON server_auth_nonces (used_at)"))
        conn.execute(
            text(
                """
                CREATE TABLE IF NOT EXISTS server_enrollment_tokens (
                    id SERIAL PRIMARY KEY,
                    token_hash VARCHAR(128) NOT NULL,
                    expires_at TIMESTAMPTZ NOT NULL,
                    used_at TIMESTAMPTZ NULL,
                    server_id_constraint VARCHAR(128) NULL,
                    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    CONSTRAINT uq_server_enrollment_tokens_token_hash UNIQUE (token_hash)
                )
                """
            )
        )
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_enrollment_tokens_expires_at ON server_enrollment_tokens (expires_at)"))
        conn.execute(text("CREATE INDEX IF NOT EXISTS ix_server_enrollment_tokens_used_at ON server_enrollment_tokens (used_at)"))
        conn.execute(
            text("CREATE INDEX IF NOT EXISTS ix_server_enrollment_tokens_server_id_constraint ON server_enrollment_tokens (server_id_constraint)")
        )
