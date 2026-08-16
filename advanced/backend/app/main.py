from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text

from app.api.v1.router import api_router
from app.config import get_settings
from app.core.errors import install_exception_handlers
from app.core.middleware import RateLimitMiddleware, RequestContextMiddleware
from app.database import SessionLocal, create_all
from app.services.auth import ensure_admin_user
from app.services.media import seed_provider_catalog

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)
settings = get_settings()


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Production initialization runs through Alembic + app.seed under systemd.
    # Development/test mode remains self-initializing for convenience.
    if not settings.is_production:
        create_all()
        with SessionLocal() as db:
            ensure_admin_user(db)
            try:
                count = seed_provider_catalog(db)
                if count:
                    logger.info("Seeded %s media records from TMDB", count)
            except Exception:
                logger.exception(
                    "TMDB catalog seeding failed; cached rows can still serve requests"
                )
    yield


app = FastAPI(
    title=settings.app_name,
    version="2.0.0",
    description=(
        "CineTrack advanced-model API. The Flutter client talks only to this backend. "
        "Movie/TV discovery, details, cast/crew, seasons and episodes are fetched from TMDB, "
        "normalized and cached server-side. The API also provides PostgreSQL-backed users, "
        "JWT sessions, watch state/progress, ratings, spoiler-aware comments, favorites, "
        "personal lists, statistics, reports and role-based administration."
    ),
    contact={"name": "CineTrack Project Team"},
    license_info={"name": "Educational non-commercial project"},
    lifespan=lifespan,
)

app.add_middleware(RateLimitMiddleware)
app.add_middleware(RequestContextMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-ID"],
)
install_exception_handlers(app)
app.include_router(api_router, prefix=settings.api_v1_prefix)
app.mount("/uploads", StaticFiles(directory=settings.upload_dir), name="uploads")


@app.get("/health", tags=["Operations"])
def health() -> dict:
    return {
        "status": "ok",
        "service": settings.app_name,
        "environment": settings.environment,
    }


@app.get("/ready", tags=["Operations"])
def ready() -> dict:
    with SessionLocal() as db:
        db.execute(text("SELECT 1"))
    return {
        "status": "ready",
        "database": "ok",
        "media_provider": settings.media_provider.lower(),
        "provider_configured": settings.tmdb_configured,
    }
