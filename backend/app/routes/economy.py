import random

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from ..auth import get_current_account, get_optional_account
from ..config import settings
from ..db import get_db
from ..models import (
    Account,
    CaseDefinition,
    CaseDrop,
    CaseOpening,
    CatalogItem,
    EquippedCosmetic,
    InventoryItem,
    Player,
    PlayerStats,
    WalletBalance,
)
from ..schemas import (
    CatalogResponse,
    DevGrantCurrencyRequest,
    DevGrantCurrencyResponse,
    EquipCosmeticRequest,
    EquippedCosmeticResponse,
    InventoryItemResponse,
    OpenCaseRequest,
    OpenCaseResponse,
    ProfileResponse,
)

router = APIRouter(tags=["economy"])

DEFAULT_CATALOG_ITEMS = [
    {
        "item_key": "character:lain",
        "item_type": "character_model",
        "display_name": "Lain",
        "rarity": "common",
        "is_default": True,
    },
    {
        "item_key": "character:leama",
        "item_type": "character_model",
        "display_name": "Leama",
        "rarity": "common",
        "is_default": True,
    },
    {
        "item_key": "weapon_skin:ar-15:default",
        "item_type": "weapon_skin",
        "display_name": "AR-15 Default",
        "rarity": "common",
        "is_default": True,
    },
    {
        "item_key": "weapon_skin:ar-15:gold",
        "item_type": "weapon_skin",
        "display_name": "AR-15 Gold",
        "rarity": "rare",
        "price_currency": "soft",
        "price_amount": 1200,
    },
    {
        "item_key": "weapon_skin:barret:default",
        "item_type": "weapon_skin",
        "display_name": "Barret Default",
        "rarity": "common",
        "is_default": True,
    },
    {
        "item_key": "weapon_skin:barret:gold",
        "item_type": "weapon_skin",
        "display_name": "Barret Gold",
        "rarity": "rare",
        "price_currency": "soft",
        "price_amount": 1200,
    },
]

DEFAULT_CASES = [
    {
        "case_key": "starter_case",
        "display_name": "Starter Case",
        "price_currency": "soft",
        "price_amount": 500,
        "drops": [
            {"item_key": "weapon_skin:ar-15:gold", "weight": 3, "duplicate_soft_refund": 150},
            {"item_key": "weapon_skin:barret:gold", "weight": 2, "duplicate_soft_refund": 150},
            {"item_key": "character:leama", "weight": 1, "duplicate_soft_refund": 100},
        ],
    },
]


def seed_default_economy_catalog(db: Session) -> None:
    for item_data in DEFAULT_CATALOG_ITEMS:
        item = db.scalar(select(CatalogItem).where(CatalogItem.item_key == item_data["item_key"]))
        if item is None:
            db.add(CatalogItem(**item_data))

    for case_data in DEFAULT_CASES:
        case = db.scalar(select(CaseDefinition).where(CaseDefinition.case_key == case_data["case_key"]))
        if case is None:
            case = CaseDefinition(
                case_key=case_data["case_key"],
                display_name=case_data["display_name"],
                price_currency=case_data["price_currency"],
                price_amount=case_data["price_amount"],
            )
            db.add(case)
            db.flush()
        for drop_data in case_data["drops"]:
            existing = db.scalar(
                select(CaseDrop).where(
                    CaseDrop.case_id == case.id,
                    CaseDrop.item_key == drop_data["item_key"],
                )
            )
            if existing is None:
                db.add(CaseDrop(case_id=case.id, **drop_data))
    db.commit()


@router.get("/profile/me", response_model=ProfileResponse)
def get_my_profile(account: Account = Depends(get_current_account), db: Session = Depends(get_db)) -> ProfileResponse:
    player = _get_or_create_account_player(db, account)
    _grant_default_items(db, player)
    db.commit()
    db.refresh(player)
    return _profile_response(player, db)


@router.get("/profile/{external_id}", response_model=ProfileResponse)
def get_profile(external_id: str, db: Session = Depends(get_db)) -> ProfileResponse:
    player = _get_or_create_player(db, external_id, external_id)
    _grant_default_items(db, player)
    db.commit()
    db.refresh(player)
    return _profile_response(player, db)


@router.get("/catalog", response_model=CatalogResponse)
def get_catalog(db: Session = Depends(get_db)) -> CatalogResponse:
    items = db.scalars(select(CatalogItem).order_by(CatalogItem.item_type, CatalogItem.item_key)).all()
    cases = db.scalars(
        select(CaseDefinition).options(selectinload(CaseDefinition.drops)).order_by(CaseDefinition.case_key)
    ).all()
    return CatalogResponse(items=list(items), cases=list(cases))


@router.get("/inventory/me", response_model=list[InventoryItemResponse])
def get_my_inventory(account: Account = Depends(get_current_account), db: Session = Depends(get_db)) -> list[InventoryItem]:
    player = _get_or_create_account_player(db, account)
    _grant_default_items(db, player)
    db.commit()
    return list(db.scalars(select(InventoryItem).where(InventoryItem.player_id == player.id).order_by(InventoryItem.item_key)).all())


@router.get("/inventory/{external_id}", response_model=list[InventoryItemResponse])
def get_inventory(external_id: str, db: Session = Depends(get_db)) -> list[InventoryItem]:
    player = _get_or_create_player(db, external_id, external_id)
    _grant_default_items(db, player)
    db.commit()
    return list(db.scalars(select(InventoryItem).where(InventoryItem.player_id == player.id).order_by(InventoryItem.item_key)).all())


@router.post("/inventory/equip", response_model=EquippedCosmeticResponse)
def equip_cosmetic(
    payload: EquipCosmeticRequest,
    db: Session = Depends(get_db),
    account: Account | None = Depends(get_optional_account),
) -> EquippedCosmetic:
    player = _get_or_create_account_player(db, account) if account is not None else _get_or_create_player(db, payload.external_id, payload.external_id)
    _grant_default_items(db, player)
    catalog_item = db.scalar(select(CatalogItem).where(CatalogItem.item_key == payload.item_key))
    if catalog_item is None:
        raise HTTPException(status_code=404, detail="catalog item not found")
    if not _owns_item(db, player.id, payload.item_key):
        raise HTTPException(status_code=403, detail="item is not owned")
    if not _item_matches_slot(payload.item_key, payload.slot_key):
        raise HTTPException(status_code=400, detail="item does not match equip slot")

    equipped = db.scalar(
        select(EquippedCosmetic).where(
            EquippedCosmetic.player_id == player.id,
            EquippedCosmetic.slot_key == payload.slot_key,
        )
    )
    if equipped is None:
        equipped = EquippedCosmetic(player_id=player.id, slot_key=payload.slot_key, item_key=payload.item_key)
        db.add(equipped)
    else:
        equipped.item_key = payload.item_key
    db.commit()
    db.refresh(equipped)
    return equipped


@router.post("/cases/open", response_model=OpenCaseResponse)
def open_case(
    payload: OpenCaseRequest,
    db: Session = Depends(get_db),
    account: Account | None = Depends(get_optional_account),
) -> OpenCaseResponse:
    player = _get_or_create_account_player(db, account) if account is not None else _get_or_create_player(db, payload.external_id, payload.external_id)
    case = db.scalar(
        select(CaseDefinition)
        .options(selectinload(CaseDefinition.drops))
        .where(CaseDefinition.case_key == payload.case_key)
    )
    if case is None or not case.is_enabled:
        raise HTTPException(status_code=404, detail="case not found")
    if len(case.drops) == 0:
        raise HTTPException(status_code=409, detail="case has no drops")

    balance = _get_wallet_balance(db, player.id, case.price_currency)
    if balance.amount < case.price_amount:
        raise HTTPException(status_code=400, detail="not enough currency")

    drop = _choose_drop(list(case.drops))
    was_duplicate = _owns_item(db, player.id, drop.item_key)
    balance.amount -= case.price_amount
    inventory_item = _grant_item(db, player.id, drop.item_key, "case")
    duplicate_refund = drop.duplicate_soft_refund if was_duplicate else 0
    if duplicate_refund > 0:
        soft_balance = _get_wallet_balance(db, player.id, "soft")
        soft_balance.amount += duplicate_refund

    db.add(
        CaseOpening(
            player_id=player.id,
            case_key=case.case_key,
            granted_item_key=drop.item_key,
            currency_key=case.price_currency,
            currency_spent=case.price_amount,
            duplicate_refund=duplicate_refund,
        )
    )
    db.commit()
    db.refresh(inventory_item)
    wallet = list(db.scalars(select(WalletBalance).where(WalletBalance.player_id == player.id).order_by(WalletBalance.currency_key)).all())
    return OpenCaseResponse(
        case_key=case.case_key,
        granted_item_key=drop.item_key,
        was_duplicate=was_duplicate,
        duplicate_refund=duplicate_refund,
        wallet=wallet,
        inventory_item=inventory_item,
    )


@router.post("/wallet/grant-dev", response_model=DevGrantCurrencyResponse)
def grant_dev_currency(
    payload: DevGrantCurrencyRequest,
    db: Session = Depends(get_db),
    account: Account | None = Depends(get_optional_account),
) -> DevGrantCurrencyResponse:
    if not settings.enable_dev_grants:
        raise HTTPException(status_code=404, detail="dev grants are disabled")
    player = _get_or_create_account_player(db, account) if account is not None else _get_or_create_player(db, payload.external_id, payload.external_id)
    balance = _get_wallet_balance(db, player.id, payload.currency_key)
    balance.amount += payload.amount
    db.commit()
    db.refresh(balance)
    return DevGrantCurrencyResponse(balance=balance)


def _get_or_create_player(db: Session, external_id: str, display_name: str) -> Player:
    player = db.scalar(select(Player).where(Player.external_id == external_id))
    if player is None:
        player = Player(external_id=external_id, display_name=display_name)
        db.add(player)
        db.flush()
        db.add(PlayerStats(player_id=player.id))
    elif player.stats is None:
        db.add(PlayerStats(player_id=player.id))
    return player


def _get_or_create_account_player(db: Session, account: Account) -> Player:
    player = db.scalar(select(Player).where(Player.account_id == account.id))
    if player is None:
        external_id = "account:%d" % account.id
        player = db.scalar(select(Player).where(Player.external_id == external_id))
    if player is None:
        player = Player(
            external_id="account:%d" % account.id,
            account_id=account.id,
            display_name=account.display_name,
        )
        db.add(player)
        db.flush()
        db.add(PlayerStats(player_id=player.id))
    else:
        player.account_id = account.id
        player.display_name = account.display_name
        if player.stats is None:
            db.add(PlayerStats(player_id=player.id))
    return player


def _profile_response(player: Player, db: Session) -> ProfileResponse:
    stats = player.stats
    if stats is None:
        stats = PlayerStats(player_id=player.id)
        db.add(stats)
        db.flush()
    wallet = list(db.scalars(select(WalletBalance).where(WalletBalance.player_id == player.id).order_by(WalletBalance.currency_key)).all())
    inventory = list(db.scalars(select(InventoryItem).where(InventoryItem.player_id == player.id).order_by(InventoryItem.item_key)).all())
    equipped = list(db.scalars(select(EquippedCosmetic).where(EquippedCosmetic.player_id == player.id).order_by(EquippedCosmetic.slot_key)).all())
    return ProfileResponse(player=player, stats=stats, wallet=wallet, inventory=inventory, equipped=equipped)


def _grant_default_items(db: Session, player: Player) -> None:
    defaults = db.scalars(select(CatalogItem).where(CatalogItem.is_default.is_(True))).all()
    for item in defaults:
        _grant_item(db, player.id, item.item_key, "default")
    if not _get_equipped(db, player.id, "character"):
        _equip_if_owned(db, player.id, "character", "character:lain")
    if not _get_equipped(db, player.id, "weapon:ar-15"):
        _equip_if_owned(db, player.id, "weapon:ar-15", "weapon_skin:ar-15:default")
    if not _get_equipped(db, player.id, "weapon:barret"):
        _equip_if_owned(db, player.id, "weapon:barret", "weapon_skin:barret:default")


def _grant_item(db: Session, player_id: int, item_key: str, source: str) -> InventoryItem:
    item = db.scalar(select(InventoryItem).where(InventoryItem.player_id == player_id, InventoryItem.item_key == item_key))
    if item is None:
        item = InventoryItem(player_id=player_id, item_key=item_key, quantity=1, source=source)
        db.add(item)
        db.flush()
    elif source == "case":
        item.quantity += 1
    return item


def _get_wallet_balance(db: Session, player_id: int, currency_key: str) -> WalletBalance:
    balance = db.scalar(select(WalletBalance).where(WalletBalance.player_id == player_id, WalletBalance.currency_key == currency_key))
    if balance is None:
        balance = WalletBalance(player_id=player_id, currency_key=currency_key, amount=0)
        db.add(balance)
        db.flush()
    return balance


def _owns_item(db: Session, player_id: int, item_key: str) -> bool:
    return db.scalar(select(InventoryItem).where(InventoryItem.player_id == player_id, InventoryItem.item_key == item_key)) is not None


def _get_equipped(db: Session, player_id: int, slot_key: str) -> EquippedCosmetic | None:
    return db.scalar(select(EquippedCosmetic).where(EquippedCosmetic.player_id == player_id, EquippedCosmetic.slot_key == slot_key))


def _equip_if_owned(db: Session, player_id: int, slot_key: str, item_key: str) -> None:
    if not _owns_item(db, player_id, item_key):
        return
    db.add(EquippedCosmetic(player_id=player_id, slot_key=slot_key, item_key=item_key))


def _item_matches_slot(item_key: str, slot_key: str) -> bool:
    if slot_key == "character":
        return item_key.startswith("character:")
    if slot_key.startswith("weapon:"):
        parts = item_key.split(":")
        return len(parts) >= 3 and parts[0] == "weapon_skin" and parts[1] == slot_key.split(":", 1)[1]
    return False


def _choose_drop(drops: list[CaseDrop]) -> CaseDrop:
    total_weight = sum(max(drop.weight, 0) for drop in drops)
    if total_weight <= 0:
        raise HTTPException(status_code=409, detail="case has no weighted drops")
    roll = random.randint(1, total_weight)
    cursor = 0
    for drop in drops:
        cursor += max(drop.weight, 0)
        if roll <= cursor:
            return drop
    return drops[-1]
