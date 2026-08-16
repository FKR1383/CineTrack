from __future__ import annotations

import httpx

from app.services.providers.tmdb import TMDBProvider


def test_real_tmdb_adapter_builds_v3_requests_and_normalizes(monkeypatch):
    calls: list[tuple[str, dict[str, str]]] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append((request.url.path, dict(request.url.params)))
        path = request.url.path
        if path == "/3/genre/movie/list":
            return httpx.Response(200, json={"genres": [{"id": 878, "name": "Science Fiction"}]})
        if path == "/3/genre/tv/list":
            return httpx.Response(200, json={"genres": [{"id": 18, "name": "Drama"}]})
        if path == "/3/search/movie":
            return httpx.Response(
                200,
                json={
                    "page": 1,
                    "total_pages": 1,
                    "total_results": 1,
                    "results": [
                        {
                            "id": 157336,
                            "title": "Interstellar",
                            "original_title": "Interstellar",
                            "overview": "Explorers travel through a wormhole.",
                            "poster_path": "/poster.jpg",
                            "genre_ids": [878],
                            "release_date": "2014-11-05",
                            "vote_average": 8.5,
                            "vote_count": 36000,
                            "popularity": 100.0,
                        }
                    ],
                },
            )
        if path == "/3/movie/157336":
            return httpx.Response(
                200,
                json={
                    "id": 157336,
                    "title": "Interstellar",
                    "original_title": "Interstellar",
                    "overview": "Explorers travel through a wormhole.",
                    "poster_path": "/poster.jpg",
                    "genres": [{"id": 878, "name": "Science Fiction"}],
                    "release_date": "2014-11-05",
                    "runtime": 169,
                    "production_countries": [{"iso_3166_1": "US", "name": "United States of America"}],
                    "vote_average": 8.5,
                    "vote_count": 36000,
                    "status": "Released",
                    "popularity": 100.0,
                    "external_ids": {"imdb_id": "tt0816692"},
                    "credits": {
                        "cast": [{"name": "Matthew McConaughey"}],
                        "crew": [{"name": "Christopher Nolan", "job": "Director"}],
                    },
                },
            )
        raise AssertionError(f"unexpected TMDB request: {request.url}")

    provider = TMDBProvider()
    provider.client.close()
    provider.client = httpx.Client(
        base_url="https://api.themoviedb.org/3",
        transport=httpx.MockTransport(handler),
        headers={"Accept": "application/json"},
    )
    # Avoid API-key fallback in this adapter-only test; authentication itself is
    # covered by config and runtime acceptance script, not by a fake secret.
    monkeypatch.setattr(provider, "_request", provider._request)

    result = provider.search(
        query="Interstellar",
        media_type="movie",
        actor=None,
        director=None,
        genre=None,
        year=2014,
        page=1,
        page_size=20,
    )
    assert result.total == 1
    assert result.items[0]["media_key"] == "tmdb-movie-157336"
    assert result.items[0]["poster_source_url"].endswith("/w500/poster.jpg")

    detail = provider.get_title("tmdb-movie-157336")
    assert detail["tmdb_id"] == 157336
    assert detail["imdb_id"] == "tt0816692"
    assert detail["directors"] == ["Christopher Nolan"]
    assert detail["cast"] == ["Matthew McConaughey"]
    assert detail["runtime_minutes"] == 169

    assert any(path == "/3/search/movie" for path, _ in calls)
    assert any(path == "/3/movie/157336" for path, _ in calls)
