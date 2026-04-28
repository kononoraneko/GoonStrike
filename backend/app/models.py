from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .db import Base


class Player(Base):
    __tablename__ = "players"

    id: Mapped[int] = mapped_column(primary_key=True)
    external_id: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    account_id: Mapped[int | None] = mapped_column(ForeignKey("accounts.id", ondelete="SET NULL"), nullable=True, index=True)
    display_name: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    account: Mapped["Account | None"] = relationship(back_populates="players")
    stats: Mapped["PlayerStats"] = relationship(back_populates="player", cascade="all, delete-orphan")
    wallet: Mapped[list["WalletBalance"]] = relationship(back_populates="player", cascade="all, delete-orphan")
    inventory: Mapped[list["InventoryItem"]] = relationship(back_populates="player", cascade="all, delete-orphan")
    equipped_cosmetics: Mapped[list["EquippedCosmetic"]] = relationship(back_populates="player", cascade="all, delete-orphan")


class Account(Base):
    __tablename__ = "accounts"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(64))
    password_hash: Mapped[str] = mapped_column(String(256))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    players: Mapped[list[Player]] = relationship(back_populates="account")
    sessions: Mapped[list["AuthSession"]] = relationship(back_populates="account", cascade="all, delete-orphan")


class AuthSession(Base):
    __tablename__ = "auth_sessions"

    id: Mapped[int] = mapped_column(primary_key=True)
    account_id: Mapped[int] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"), index=True)
    refresh_token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    device_label: Mapped[str] = mapped_column(String(128), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    account: Mapped[Account] = relationship(back_populates="sessions")


class PlayerStats(Base):
    __tablename__ = "player_stats"

    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), primary_key=True)
    matches_played: Mapped[int] = mapped_column(Integer, default=0)
    kills: Mapped[int] = mapped_column(Integer, default=0)
    deaths: Mapped[int] = mapped_column(Integer, default=0)
    assists: Mapped[int] = mapped_column(Integer, default=0)
    wins: Mapped[int] = mapped_column(Integer, default=0)

    player: Mapped[Player] = relationship(back_populates="stats")


class MatchResult(Base):
    __tablename__ = "match_results"
    __table_args__ = (
        UniqueConstraint("match_id", "player_id", name="uq_match_results_match_player"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    match_id: Mapped[str] = mapped_column(String(128), index=True)
    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    mode_id: Mapped[str] = mapped_column(String(64))
    map_id: Mapped[str] = mapped_column(String(128))
    kills: Mapped[int] = mapped_column(Integer, default=0)
    deaths: Mapped[int] = mapped_column(Integer, default=0)
    assists: Mapped[int] = mapped_column(Integer, default=0)
    won: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class TrustedServer(Base):
    __tablename__ = "trusted_servers"

    id: Mapped[int] = mapped_column(primary_key=True)
    server_id: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(96))
    host: Mapped[str] = mapped_column(String(255))
    port: Mapped[int] = mapped_column(Integer)
    map_id: Mapped[str] = mapped_column(String(128), default="")
    mode_id: Mapped[str] = mapped_column(String(64), default="")
    current_players: Mapped[int] = mapped_column(Integer, default=0)
    max_players: Mapped[int] = mapped_column(Integer, default=0)
    is_trusted: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_online: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    last_heartbeat_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class ServerCredential(Base):
    __tablename__ = "server_credentials"
    __table_args__ = (
        UniqueConstraint("server_id", "key_id", name="uq_server_credentials_server_key"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    server_id: Mapped[str] = mapped_column(String(128), index=True)
    key_id: Mapped[str] = mapped_column(String(128), index=True)
    secret_hash: Mapped[str] = mapped_column(String(256))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class ServerEnrollmentToken(Base):
    __tablename__ = "server_enrollment_tokens"

    id: Mapped[int] = mapped_column(primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    server_id_constraint: Mapped[str | None] = mapped_column(String(128), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ServerAuthNonce(Base):
    __tablename__ = "server_auth_nonces"
    __table_args__ = (
        UniqueConstraint("nonce", name="uq_server_auth_nonces_nonce"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    server_id: Mapped[str] = mapped_column(String(128), index=True)
    nonce: Mapped[str] = mapped_column(String(128), index=True)
    challenge: Mapped[str] = mapped_column(String(128), index=True)
    key_id: Mapped[str] = mapped_column(String(128), index=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class WalletBalance(Base):
    __tablename__ = "wallet_balances"
    __table_args__ = (
        UniqueConstraint("player_id", "currency_key", name="uq_wallet_player_currency"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    currency_key: Mapped[str] = mapped_column(String(32), index=True)
    amount: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    player: Mapped[Player] = relationship(back_populates="wallet")


class CatalogItem(Base):
    __tablename__ = "catalog_items"

    id: Mapped[int] = mapped_column(primary_key=True)
    item_key: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    item_type: Mapped[str] = mapped_column(String(32), index=True)
    display_name: Mapped[str] = mapped_column(String(96))
    rarity: Mapped[str] = mapped_column(String(32), default="common")
    price_currency: Mapped[str | None] = mapped_column(String(32), nullable=True)
    price_amount: Mapped[int] = mapped_column(Integer, default=0)
    is_unlockable: Mapped[bool] = mapped_column(Boolean, default=True)
    is_default: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class InventoryItem(Base):
    __tablename__ = "inventory_items"
    __table_args__ = (
        UniqueConstraint("player_id", "item_key", name="uq_inventory_player_item"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    item_key: Mapped[str] = mapped_column(String(128), index=True)
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    source: Mapped[str] = mapped_column(String(64), default="grant")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    player: Mapped[Player] = relationship(back_populates="inventory")


class EquippedCosmetic(Base):
    __tablename__ = "equipped_cosmetics"
    __table_args__ = (
        UniqueConstraint("player_id", "slot_key", name="uq_equipped_player_slot"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    slot_key: Mapped[str] = mapped_column(String(64), index=True)
    item_key: Mapped[str] = mapped_column(String(128), index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    player: Mapped[Player] = relationship(back_populates="equipped_cosmetics")


class CaseDefinition(Base):
    __tablename__ = "case_definitions"

    id: Mapped[int] = mapped_column(primary_key=True)
    case_key: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(96))
    price_currency: Mapped[str] = mapped_column(String(32), default="soft")
    price_amount: Mapped[int] = mapped_column(Integer, default=0)
    is_enabled: Mapped[bool] = mapped_column(Boolean, default=True)

    drops: Mapped[list["CaseDrop"]] = relationship(back_populates="case", cascade="all, delete-orphan")


class CaseDrop(Base):
    __tablename__ = "case_drops"
    __table_args__ = (
        UniqueConstraint("case_id", "item_key", name="uq_case_drop_item"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    case_id: Mapped[int] = mapped_column(ForeignKey("case_definitions.id", ondelete="CASCADE"), index=True)
    item_key: Mapped[str] = mapped_column(String(128), index=True)
    weight: Mapped[int] = mapped_column(Integer, default=1)
    duplicate_soft_refund: Mapped[int] = mapped_column(Integer, default=0)

    case: Mapped[CaseDefinition] = relationship(back_populates="drops")


class CaseOpening(Base):
    __tablename__ = "case_openings"

    id: Mapped[int] = mapped_column(primary_key=True)
    player_id: Mapped[int] = mapped_column(ForeignKey("players.id", ondelete="CASCADE"), index=True)
    case_key: Mapped[str] = mapped_column(String(128), index=True)
    granted_item_key: Mapped[str] = mapped_column(String(128), index=True)
    currency_key: Mapped[str] = mapped_column(String(32))
    currency_spent: Mapped[int] = mapped_column(Integer, default=0)
    duplicate_refund: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
