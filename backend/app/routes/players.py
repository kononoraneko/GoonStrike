from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import Player, PlayerStats
from ..schemas import PlayerResponse, PlayerStatsResponse, PlayerUpsertRequest

router = APIRouter(prefix="/players", tags=["players"])


@router.post("/upsert", response_model=PlayerResponse)
def upsert_player(payload: PlayerUpsertRequest, db: Session = Depends(get_db)) -> Player:
    player = db.scalar(select(Player).where(Player.external_id == payload.external_id))
    if player is None:
        player = Player(external_id=payload.external_id, display_name=payload.display_name)
        db.add(player)
        db.flush()
        db.add(PlayerStats(player_id=player.id))
    else:
        player.display_name = payload.display_name
    db.commit()
    db.refresh(player)
    return player


@router.get("/{external_id}/stats", response_model=PlayerStatsResponse)
def get_player_stats(external_id: str, db: Session = Depends(get_db)) -> PlayerStats:
    player = db.scalar(select(Player).where(Player.external_id == external_id))
    if player is None or player.stats is None:
        raise HTTPException(status_code=404, detail="player not found")
    return player.stats
