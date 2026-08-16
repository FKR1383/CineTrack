from __future__ import annotations

import os
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

TEST_DB = Path(__file__).parent / "test_cinetrack.db"
UPLOADS = Path(__file__).parent / "test_uploads"
os.environ.update(
    {
        "DATABASE_URL": f"sqlite:///{TEST_DB}",
        "JWT_SECRET": "test-secret-that-is-longer-than-thirty-two-characters",
        "MEDIA_PROVIDER": "tmdb",
        "TMDB_API_KEY": "test-only-key",
        "UPLOAD_DIR": str(UPLOADS),
        "ENVIRONMENT": "test",
        "ADMIN_EMAIL": "admin@test.example",
        "ADMIN_USERNAME": "testadmin",
        "ADMIN_PASSWORD": "Admin123!Test",
        "RATE_LIMIT_PER_MINUTE": "10000",
    }
)

from app.database import Base, engine  # noqa: E402
from app.main import app  # noqa: E402
from app.services.providers.base import MediaNotFoundError, ProviderSearchPage  # noqa: E402


def _title(
    key: str,
    tmdb_id: int,
    media_type: str,
    title: str,
    *,
    director: str,
    genres: list[str],
    rating: float,
    votes: int,
    year: int,
    ended: bool = True,
    cast: list[str] | None = None,
    episodes: int | None = None,
) -> dict:
    return {
        "media_key": key,
        "provider": "tmdb",
        "provider_id": str(tmdb_id),
        "tmdb_id": tmdb_id,
        "imdb_id": None,
        "media_type": media_type,
        "title": title,
        "original_title": title,
        "poster_source_url": f"https://image.tmdb.org/t/p/w500/{tmdb_id}.jpg",
        "plot": f"Plot for {title}",
        "genres": genres,
        "release_year": year,
        "end_year": year + 5 if media_type == "series" and ended else None,
        "release_date": f"{year}-01-01",
        "runtime_minutes": 120 if media_type == "movie" else 50,
        "countries": ["United States"],
        "directors": [director],
        "cast": cast or ["Actor One", "Actor Two"],
        "provider_rating": rating,
        "provider_vote_count": votes,
        "release_status": "ended" if media_type == "series" and ended else ("ongoing" if media_type == "series" else "released"),
        "season_count": 2 if media_type == "series" else None,
        "episode_count": episodes if media_type == "series" else None,
        "raw_payload": {"test": True},
    }


CATALOG = {
    "tmdb-movie-603": _title(
        "tmdb-movie-603", 603, "movie", "The Matrix", director="Lana Wachowski",
        genres=["Action", "Science Fiction"], rating=8.2, votes=26000, year=1999,
        cast=["Keanu Reeves", "Carrie-Anne Moss"],
    ),
    "tmdb-movie-27205": _title(
        "tmdb-movie-27205", 27205, "movie", "Inception", director="Christopher Nolan",
        genres=["Action", "Science Fiction", "Adventure"], rating=8.4, votes=37000, year=2010,
        cast=["Leonardo DiCaprio", "Joseph Gordon-Levitt"],
    ),
    "tmdb-series-1396": _title(
        "tmdb-series-1396", 1396, "series", "Breaking Bad", director="Vince Gilligan",
        genres=["Drama", "Crime"], rating=8.9, votes=15000, year=2008, ended=True,
        cast=["Bryan Cranston", "Aaron Paul"], episodes=10,
    ),
    "tmdb-series-71912": _title(
        "tmdb-series-71912", 71912, "series", "The Witcher", director="Lauren Schmidt Hissrich",
        genres=["Drama", "Fantasy", "Action"], rating=8.0, votes=6000, year=2019, ended=False,
        cast=["Henry Cavill", "Anya Chalotra"], episodes=10,
    ),
}


class FakeTMDBProvider:
    name = "tmdb"

    def home_sections(self) -> dict[str, list[dict]]:
        rows = list(CATALOG.values())
        return {
            "popular_movies": [CATALOG["tmdb-movie-27205"], CATALOG["tmdb-movie-603"]],
            "popular_series": [CATALOG["tmdb-series-1396"], CATALOG["tmdb-series-71912"]],
            "new_releases": rows,
            "top_rated": sorted(rows, key=lambda x: x["provider_rating"], reverse=True),
            "recommendations": rows,
        }

    def get_title(self, media_key: str) -> dict:
        if media_key in CATALOG:
            return dict(CATALOG[media_key])
        raise MediaNotFoundError(media_key)

    def get_episodes(self, media_key: str) -> list[dict]:
        if media_key not in {"tmdb-series-1396", "tmdb-series-71912"}:
            return []
        base = 100000 if media_key.endswith("1396") else 200000
        return [
            {
                "episode_key": f"tmdb-episode-{base + index}",
                "provider": "tmdb",
                "provider_id": str(base + index),
                "tmdb_id": base + index,
                "imdb_id": None,
                "season_number": 1 if index <= 5 else 2,
                "episode_number": index if index <= 5 else index - 5,
                "title": f"Episode {index}",
                "release_date": f"2020-01-{index:02d}",
                "runtime_minutes": 50,
                "plot": f"Episode {index} plot",
            }
            for index in range(1, 11)
        ]

    def search(self, *, query, media_type, actor, director, genre, year, page, page_size):
        rows = list(CATALOG.values())
        if query:
            q = query.casefold()
            rows = [r for r in rows if q in r["title"].casefold()]
        if media_type:
            rows = [r for r in rows if r["media_type"] == media_type]
        if actor:
            a = actor.casefold()
            rows = [r for r in rows if a in " ".join(r["cast"]).casefold()]
        if director:
            d = director.casefold()
            rows = [r for r in rows if d in " ".join(r["directors"]).casefold()]
        if genre:
            g = genre.casefold()
            rows = [r for r in rows if g in " ".join(r["genres"]).casefold()]
        if year:
            rows = [r for r in rows if r["release_year"] == year]
        total = len(rows)
        start = (page - 1) * page_size
        items = [dict(r) for r in rows[start : start + page_size]]
        total_pages = (total + page_size - 1) // page_size if total else 0
        return ProviderSearchPage(items, page, page_size, total, total_pages)


@pytest.fixture(autouse=True)
def fake_tmdb(monkeypatch):
    from app.services import media as media_service

    provider = FakeTMDBProvider()
    monkeypatch.setattr(media_service, "get_media_provider", lambda: provider)
    yield provider


@pytest.fixture(autouse=True)
def clean_database():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


@pytest.fixture
def client() -> TestClient:
    with TestClient(app) as value:
        yield value


@pytest.fixture
def user_tokens(client: TestClient) -> dict:
    response = client.post(
        "/api/v1/auth/register-json",
        json={
            "first_name": "Sara",
            "last_name": "Ahmadi",
            "username": "sara",
            "email": "sara@example.com",
            "password": "Secure123",
            "bio": "Movie fan",
        },
    )
    assert response.status_code == 201, response.text
    return response.json()


@pytest.fixture
def auth_headers(user_tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {user_tokens['access_token']}"}


@pytest.fixture
def admin_headers(client: TestClient) -> dict[str, str]:
    response = client.post(
        "/api/v1/auth/login",
        json={"email": "admin@test.example", "password": "Admin123!Test", "remember_me": True},
    )
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}
