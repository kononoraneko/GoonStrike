from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..auth import (
    create_access_token,
    get_current_account,
    hash_password,
    hash_token,
    new_refresh_token,
    utcnow,
    verify_password,
)
from ..config import settings
from ..db import get_db
from ..models import Account, AuthSession
from ..schemas import (
    AccountResponse,
    AuthLoginRequest,
    AuthLogoutRequest,
    AuthMeResponse,
    AuthRefreshRequest,
    AuthRegisterRequest,
    AuthTokenResponse,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=AuthTokenResponse)
def register(payload: AuthRegisterRequest, db: Session = Depends(get_db)) -> AuthTokenResponse:
    email = _normalize_email(payload.email)
    existing = db.scalar(select(Account).where(Account.email == email))
    if existing is not None:
        raise HTTPException(status_code=409, detail="email already registered")

    account = Account(
        email=email,
        display_name=payload.display_name.strip(),
        password_hash=hash_password(payload.password),
    )
    db.add(account)
    db.flush()
    response = _issue_tokens(db, account, payload.device_label)
    db.commit()
    return response


@router.post("/login", response_model=AuthTokenResponse)
def login(payload: AuthLoginRequest, db: Session = Depends(get_db)) -> AuthTokenResponse:
    account = db.scalar(select(Account).where(Account.email == _normalize_email(payload.email)))
    if account is None or not account.is_active or not verify_password(payload.password, account.password_hash):
        raise HTTPException(status_code=401, detail="invalid credentials")

    if _has_active_session(db, account.id):
        _revoke_all_sessions(db, account.id)
        db.commit()
        raise HTTPException(status_code=409, detail="session_conflict")

    response = _issue_tokens(db, account, payload.device_label)
    db.commit()
    return response


@router.post("/refresh", response_model=AuthTokenResponse)
def refresh(payload: AuthRefreshRequest, db: Session = Depends(get_db)) -> AuthTokenResponse:
    session = _get_active_session_for_refresh(db, payload.refresh_token)
    account = session.account
    if account is None or not account.is_active:
        raise HTTPException(status_code=401, detail="account not found")
    session.last_seen_at = utcnow()
    response = _token_response(account, payload.refresh_token)
    db.commit()
    return response


@router.post("/logout")
def logout(payload: AuthLogoutRequest, db: Session = Depends(get_db)) -> dict:
    token_hash = hash_token(payload.refresh_token)
    session = db.scalar(select(AuthSession).where(AuthSession.refresh_token_hash == token_hash))
    if session is not None and session.revoked_at is None:
        session.revoked_at = utcnow()
        db.commit()
    return {"status": "ok"}


@router.get("/me", response_model=AuthMeResponse)
def me(account: Account = Depends(get_current_account)) -> AuthMeResponse:
    return AuthMeResponse(account=account)


def _issue_tokens(db: Session, account: Account, device_label: str) -> AuthTokenResponse:
    refresh_token = new_refresh_token()
    expires_at = utcnow() + timedelta(days=settings.refresh_token_days)
    session = AuthSession(
        account_id=account.id,
        refresh_token_hash=hash_token(refresh_token),
        device_label=device_label.strip()[:128],
        expires_at=expires_at,
    )
    db.add(session)
    return _token_response(account, refresh_token)


def _token_response(account: Account, refresh_token: str) -> AuthTokenResponse:
    return AuthTokenResponse(
        account=AccountResponse.model_validate(account),
        access_token=create_access_token(account),
        refresh_token=refresh_token,
        expires_in=settings.access_token_minutes * 60,
    )


def _has_active_session(db: Session, account_id: int) -> bool:
    now = utcnow()
    session = db.scalar(
        select(AuthSession).where(
            AuthSession.account_id == account_id,
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > now,
        )
    )
    return session is not None


def _revoke_all_sessions(db: Session, account_id: int) -> None:
    now = utcnow()
    sessions = db.scalars(
        select(AuthSession).where(
            AuthSession.account_id == account_id,
            AuthSession.revoked_at.is_(None),
        )
    ).all()
    for session in sessions:
        session.revoked_at = now


def _get_active_session_for_refresh(db: Session, refresh_token: str) -> AuthSession:
    session = db.scalar(
        select(AuthSession).where(AuthSession.refresh_token_hash == hash_token(refresh_token))
    )
    if session is None or session.revoked_at is not None or session.expires_at <= utcnow():
        raise HTTPException(status_code=401, detail="invalid refresh token")
    return session


def _normalize_email(email: str) -> str:
    return email.strip().lower()
