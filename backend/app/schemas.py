from datetime import datetime

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str


class ServerRegisterRequest(BaseModel):
    server_id: str = Field(min_length=1, max_length=128)
    display_name: str = Field(min_length=1, max_length=96)
    host: str = Field(min_length=1, max_length=255)
    port: int = Field(gt=0, le=65535)
    map_id: str = Field(default="", max_length=128)
    mode_id: str = Field(default="", max_length=64)
    current_players: int = Field(default=0, ge=0)
    max_players: int = Field(default=0, ge=0)
    is_trusted: bool = True


class ServerHeartbeatRequest(BaseModel):
    map_id: str = Field(default="", max_length=128)
    mode_id: str = Field(default="", max_length=64)
    current_players: int = Field(default=0, ge=0)
    max_players: int = Field(default=0, ge=0)
    is_online: bool = True


class ServerListItem(BaseModel):
    server_id: str
    display_name: str
    host: str
    port: int
    map_id: str
    mode_id: str
    current_players: int
    max_players: int
    is_trusted: bool
    is_online: bool
    last_heartbeat_at: datetime

    model_config = {"from_attributes": True}


class ServerListResponse(BaseModel):
    servers: list[ServerListItem]


class ServerChallengeRequest(BaseModel):
    server_id: str = Field(min_length=1, max_length=128)
    key_id: str = Field(min_length=1, max_length=128)


class ServerChallengeResponse(BaseModel):
    server_id: str
    key_id: str
    nonce: str
    challenge: str
    expires_at: datetime


class ServerCredentialUpsertRequest(BaseModel):
    server_id: str = Field(min_length=1, max_length=128)
    key_id: str = Field(min_length=1, max_length=128)
    secret: str = Field(min_length=8, max_length=256)
    is_active: bool = True


class ServerCredentialResponse(BaseModel):
    server_id: str
    key_id: str
    is_active: bool


class ServerCredentialListResponse(BaseModel):
    credentials: list[ServerCredentialResponse]


class PlayerUpsertRequest(BaseModel):
    external_id: str = Field(min_length=1, max_length=128)
    display_name: str = Field(min_length=1, max_length=64)


class PlayerResponse(BaseModel):
    id: int
    external_id: str
    account_id: int | None = None
    display_name: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class PlayerStatsResponse(BaseModel):
    player_id: int
    matches_played: int
    kills: int
    deaths: int
    assists: int
    wins: int

    model_config = {"from_attributes": True}


class MatchPlayerResult(BaseModel):
    external_id: str = Field(min_length=1, max_length=128)
    display_name: str = Field(min_length=1, max_length=64)
    kills: int = 0
    deaths: int = 0
    assists: int = 0
    won: bool = False


class MatchSubmitRequest(BaseModel):
    match_id: str = Field(min_length=1, max_length=128)
    mode_id: str = Field(min_length=1, max_length=64)
    map_id: str = Field(min_length=1, max_length=128)
    players: list[MatchPlayerResult]


class MatchSubmitResponse(BaseModel):
    match_id: str
    stored_results: int


class WalletBalanceResponse(BaseModel):
    currency_key: str
    amount: int

    model_config = {"from_attributes": True}


class CatalogItemResponse(BaseModel):
    item_key: str
    item_type: str
    display_name: str
    rarity: str
    price_currency: str | None = None
    price_amount: int = 0
    is_unlockable: bool = True
    is_default: bool = False

    model_config = {"from_attributes": True}


class InventoryItemResponse(BaseModel):
    item_key: str
    quantity: int
    source: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class EquippedCosmeticResponse(BaseModel):
    slot_key: str
    item_key: str

    model_config = {"from_attributes": True}


class CaseDropResponse(BaseModel):
    item_key: str
    weight: int
    duplicate_soft_refund: int

    model_config = {"from_attributes": True}


class CaseDefinitionResponse(BaseModel):
    case_key: str
    display_name: str
    price_currency: str
    price_amount: int
    is_enabled: bool
    drops: list[CaseDropResponse] = []

    model_config = {"from_attributes": True}


class ProfileResponse(BaseModel):
    player: PlayerResponse
    stats: PlayerStatsResponse
    wallet: list[WalletBalanceResponse]
    inventory: list[InventoryItemResponse]
    equipped: list[EquippedCosmeticResponse]


class CatalogResponse(BaseModel):
    items: list[CatalogItemResponse]
    cases: list[CaseDefinitionResponse]


class EquipCosmeticRequest(BaseModel):
    external_id: str = Field(min_length=1, max_length=128)
    slot_key: str = Field(min_length=1, max_length=64)
    item_key: str = Field(min_length=1, max_length=128)


class OpenCaseRequest(BaseModel):
    external_id: str = Field(min_length=1, max_length=128)
    case_key: str = Field(min_length=1, max_length=128)


class OpenCaseResponse(BaseModel):
    case_key: str
    granted_item_key: str
    was_duplicate: bool
    duplicate_refund: int
    wallet: list[WalletBalanceResponse]
    inventory_item: InventoryItemResponse


class DevGrantCurrencyRequest(BaseModel):
    external_id: str = Field(min_length=1, max_length=128)
    currency_key: str = Field(min_length=1, max_length=32)
    amount: int = Field(gt=0, le=1_000_000)


class DevGrantCurrencyResponse(BaseModel):
    balance: WalletBalanceResponse


class AccountResponse(BaseModel):
    id: int
    email: str
    display_name: str
    created_at: datetime

    model_config = {"from_attributes": True}


class AuthRegisterRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=8, max_length=128)
    display_name: str = Field(min_length=1, max_length=64)
    device_label: str = Field(default="", max_length=128)


class AuthLoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=255)
    password: str = Field(min_length=8, max_length=128)
    device_label: str = Field(default="", max_length=128)


class AuthRefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class AuthLogoutRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class AuthTokenResponse(BaseModel):
    account: AccountResponse
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class AuthMeResponse(BaseModel):
    account: AccountResponse
