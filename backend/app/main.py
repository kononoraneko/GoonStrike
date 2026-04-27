from fastapi import FastAPI

from .config import settings
from .db import Base, engine
from . import models  # noqa: F401 - imported so SQLAlchemy registers models
from .routes import health, matches, players


def create_app() -> FastAPI:
    app = FastAPI(title=settings.app_name)
    app.include_router(health.router)
    app.include_router(players.router)
    app.include_router(matches.router)
    return app


app = create_app()


@app.on_event("startup")
def create_tables() -> None:
    # Good enough for local/dev. Replace with Alembic before production migrations.
    Base.metadata.create_all(bind=engine)
