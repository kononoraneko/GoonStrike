from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..db import get_db
from ..models import MatchResult, Player, PlayerStats
from ..schemas import MatchSubmitRequest, MatchSubmitResponse

router = APIRouter(prefix="/matches", tags=["matches"])


@router.post("", response_model=MatchSubmitResponse)
def submit_match(payload: MatchSubmitRequest, db: Session = Depends(get_db)) -> MatchSubmitResponse:
    stored = 0
    for entry in payload.players:
        player = db.scalar(select(Player).where(Player.external_id == entry.external_id))
        if player is None:
            player = Player(external_id=entry.external_id, display_name=entry.display_name)
            db.add(player)
            db.flush()
            stats = PlayerStats(player_id=player.id)
            db.add(stats)
        else:
            player.display_name = entry.display_name
            stats = player.stats
            if stats is None:
                stats = PlayerStats(player_id=player.id)
                db.add(stats)

        existing = db.scalar(
            select(MatchResult).where(
                MatchResult.match_id == payload.match_id,
                MatchResult.player_id == player.id,
            )
        )
        if existing is not None:
            continue

        result = MatchResult(
            match_id=payload.match_id,
            player_id=player.id,
            mode_id=payload.mode_id,
            map_id=payload.map_id,
            kills=entry.kills,
            deaths=entry.deaths,
            assists=entry.assists,
            won=entry.won,
        )
        db.add(result)

        stats.matches_played += 1
        stats.kills += entry.kills
        stats.deaths += entry.deaths
        stats.assists += entry.assists
        stats.wins += 1 if entry.won else 0
        stored += 1

    db.commit()
    return MatchSubmitResponse(match_id=payload.match_id, stored_results=stored)
