from datetime import datetime

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str


class PlayerUpsertRequest(BaseModel):
    external_id: str = Field(min_length=1, max_length=128)
    display_name: str = Field(min_length=1, max_length=64)


class PlayerResponse(BaseModel):
    id: int
    external_id: str
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
