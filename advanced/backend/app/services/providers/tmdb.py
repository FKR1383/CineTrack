from __future__ import annotations

import math
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date
from functools import cached_property
from typing import Any, Iterable

import httpx

from app.config import get_settings
from app.services.providers.base import (
    MediaNotFoundError,
    MediaProvider,
    MediaProviderConfigurationError,
    MediaProviderUnavailableError,
    ProviderSearchPage,
)


class TMDBProvider(MediaProvider):
    """Real TMDB v3 provider used exclusively by the CineTrack backend.

    The Flutter client never receives TMDB credentials and never needs to call
    api.themoviedb.org or image.tmdb.org directly. Provider payloads are
    normalized by the backend and poster URLs are proxied/cached separately.
    """

    name = "tmdb"

    def __init__(self) -> None:
        self.settings = get_settings()
        if not self.settings.tmdb_configured:
            raise MediaProviderConfigurationError(
                "TMDB is selected but neither TMDB_READ_ACCESS_TOKEN nor TMDB_API_KEY is configured."
            )
        headers = {
            "Accept": "application/json",
            "User-Agent": "CineTrack-Advanced/2.0 (educational non-commercial project)",
        }
        token = self.settings.tmdb_read_access_token
        if token and token.get_secret_value().strip():
            headers["Authorization"] = f"Bearer {token.get_secret_value().strip()}"
        self.client = httpx.Client(
            base_url=self.settings.tmdb_api_base_url.rstrip("/"),
            timeout=self.settings.tmdb_request_timeout_seconds,
            follow_redirects=True,
            headers=headers,
        )

    def _request(self, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        query = dict(params or {})
        if "language" not in query:
            query["language"] = self.settings.tmdb_language
        if "Authorization" not in self.client.headers:
            api_key = self.settings.tmdb_api_key
            if not api_key or not api_key.get_secret_value().strip():
                raise MediaProviderConfigurationError("TMDB credentials are missing.")
            query["api_key"] = api_key.get_secret_value().strip()
        try:
            response = self.client.get(path, params=query)
        except httpx.HTTPError as exc:
            raise MediaProviderUnavailableError(f"TMDB network request failed: {exc}") from exc

        if response.status_code == 404:
            raise MediaNotFoundError(f"TMDB resource not found: {path}")
        if response.status_code in {401, 403}:
            raise MediaProviderConfigurationError(
                "TMDB rejected the configured credentials. Rotate/recheck the API Read Access Token."
            )
        if response.status_code == 429:
            raise MediaProviderUnavailableError("TMDB rate limit reached. Please retry shortly.")
        if response.status_code >= 500:
            raise MediaProviderUnavailableError(
                f"TMDB upstream error {response.status_code}."
            )
        try:
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise MediaProviderUnavailableError(f"Invalid TMDB response: {exc}") from exc
        if isinstance(payload, dict) and payload.get("success") is False:
            raise MediaProviderUnavailableError(
                str(payload.get("status_message") or "TMDB returned an unsuccessful response")
            )
        if not isinstance(payload, dict):
            raise MediaProviderUnavailableError("TMDB returned an unexpected response shape.")
        return payload

    @staticmethod
    def _endpoint_type(media_type: str) -> str:
        return "tv" if media_type == "series" else "movie"

    @staticmethod
    def _public_type(tmdb_type: str) -> str:
        return "series" if tmdb_type == "tv" else "movie"

    @classmethod
    def media_key(cls, media_type: str, tmdb_id: int | str) -> str:
        public_type = "series" if media_type in {"series", "tv"} else "movie"
        return f"tmdb-{public_type}-{int(tmdb_id)}"

    @staticmethod
    def episode_key(tmdb_id: int | str) -> str:
        return f"tmdb-episode-{int(tmdb_id)}"

    @classmethod
    def parse_media_key(cls, media_key: str) -> tuple[str, int] | None:
        if media_key.startswith("tmdb-movie-"):
            raw = media_key.removeprefix("tmdb-movie-")
            return ("movie", int(raw)) if raw.isdigit() else None
        if media_key.startswith("tmdb-series-"):
            raw = media_key.removeprefix("tmdb-series-")
            return ("series", int(raw)) if raw.isdigit() else None
        return None

    def _image_source(self, poster_path: str | None) -> str | None:
        if not poster_path:
            return None
        return f"{self.settings.tmdb_image_base_url.rstrip('/')}/w500{poster_path}"

    @staticmethod
    def _safe_year(value: Any) -> int | None:
        if not value:
            return None
        try:
            return int(str(value)[:4])
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _iso_date(value: Any) -> str | None:
        if not value:
            return None
        try:
            return date.fromisoformat(str(value)[:10]).isoformat()
        except ValueError:
            return None

    @cached_property
    def genre_maps(self) -> dict[str, dict[int, str]]:
        """Load movie/TV genre maps once, in parallel, per backend process."""
        result: dict[str, dict[int, str]] = {"movie": {}, "series": {}}

        def fetch(public_type: str, endpoint: str) -> tuple[str, dict[str, Any]]:
            return public_type, self._request(
                f"/genre/{endpoint}/list",
                {"language": self.settings.tmdb_language},
            )

        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(fetch, "movie", "movie"),
                executor.submit(fetch, "series", "tv"),
            ]
            for future in as_completed(futures):
                public_type, data = future.result()
                result[public_type] = {
                    int(item["id"]): str(item["name"])
                    for item in data.get("genres", [])
                    if item.get("id") is not None and item.get("name")
                }
        return result

    def _genre_names(self, media_type: str, ids: Iterable[Any]) -> list[str]:
        mapping = self.genre_maps.get(media_type, {})
        names: list[str] = []
        for value in ids:
            try:
                genre_id = int(value)
            except (TypeError, ValueError):
                continue
            if mapping.get(genre_id):
                names.append(mapping[genre_id])
        return names

    def _genre_id(self, media_type: str, genre: str | None) -> int | None:
        if not genre:
            return None
        wanted = genre.casefold().strip()
        mapping = self.genre_maps.get(media_type, {})
        for genre_id, name in mapping.items():
            if name.casefold() == wanted:
                return genre_id
        for genre_id, name in mapping.items():
            if wanted in name.casefold() or name.casefold() in wanted:
                return genre_id
        return None

    def _map_search_item(
        self, item: dict[str, Any], media_type_hint: str | None = None
    ) -> dict[str, Any] | None:
        raw_type = str(item.get("media_type") or media_type_hint or "")
        if raw_type == "person":
            return None
        media_type = self._public_type(raw_type)
        if media_type not in {"movie", "series"} or item.get("id") is None:
            return None
        title = item.get("title") if media_type == "movie" else item.get("name")
        original = item.get("original_title") if media_type == "movie" else item.get("original_name")
        release_date = item.get("release_date") if media_type == "movie" else item.get("first_air_date")
        vote_count = int(item.get("vote_count") or 0)
        vote_average = float(item.get("vote_average") or 0) if vote_count else None
        tmdb_id = int(item["id"])
        return {
            "media_key": self.media_key(media_type, tmdb_id),
            "provider": "tmdb",
            "provider_id": str(tmdb_id),
            "tmdb_id": tmdb_id,
            "imdb_id": None,
            "media_type": media_type,
            "title": str(title or original or f"TMDB {tmdb_id}"),
            "original_title": str(original) if original else None,
            "poster_source_url": self._image_source(item.get("poster_path")),
            "plot": item.get("overview") or None,
            "genres": self._genre_names(media_type, item.get("genre_ids") or []),
            "release_year": self._safe_year(release_date),
            "end_year": None,
            "release_date": self._iso_date(release_date),
            "runtime_minutes": None,
            "countries": [],
            "directors": [],
            "cast": [],
            "provider_rating": vote_average,
            "provider_vote_count": vote_count,
            "release_status": None,
            "season_count": None,
            "episode_count": None,
            "popularity": float(item.get("popularity") or 0),
            "raw_payload": item,
        }

    def _map_movie_detail(self, data: dict[str, Any]) -> dict[str, Any]:
        credits = data.get("credits") or {}
        external = data.get("external_ids") or {}
        directors = [
            str(person.get("name"))
            for person in credits.get("crew", [])
            if person.get("name") and person.get("job") == "Director"
        ]
        cast = [
            str(person.get("name"))
            for person in credits.get("cast", [])[:24]
            if person.get("name")
        ]
        vote_count = int(data.get("vote_count") or 0)
        tmdb_id = int(data["id"])
        return {
            "media_key": self.media_key("movie", tmdb_id),
            "provider": "tmdb",
            "provider_id": str(tmdb_id),
            "tmdb_id": tmdb_id,
            "imdb_id": external.get("imdb_id") or data.get("imdb_id") or None,
            "media_type": "movie",
            "title": str(data.get("title") or data.get("original_title") or tmdb_id),
            "original_title": data.get("original_title") or None,
            "poster_source_url": self._image_source(data.get("poster_path")),
            "plot": data.get("overview") or None,
            "genres": [str(item.get("name")) for item in data.get("genres", []) if item.get("name")],
            "release_year": self._safe_year(data.get("release_date")),
            "end_year": None,
            "release_date": self._iso_date(data.get("release_date")),
            "runtime_minutes": int(data["runtime"]) if data.get("runtime") else None,
            "countries": [
                str(item.get("name") or item.get("iso_3166_1"))
                for item in data.get("production_countries", [])
                if item.get("name") or item.get("iso_3166_1")
            ],
            "directors": list(dict.fromkeys(directors)),
            "cast": list(dict.fromkeys(cast)),
            "provider_rating": float(data.get("vote_average") or 0) if vote_count else None,
            "provider_vote_count": vote_count,
            "release_status": "released" if data.get("status") == "Released" else str(data.get("status") or "").lower() or None,
            "season_count": None,
            "episode_count": None,
            "popularity": float(data.get("popularity") or 0),
            "raw_payload": data,
        }

    def _map_tv_detail(self, data: dict[str, Any]) -> dict[str, Any]:
        credits = data.get("aggregate_credits") or {}
        external = data.get("external_ids") or {}
        directors: list[str] = []
        for person in credits.get("crew", []):
            jobs = person.get("jobs") or []
            if any(str(job.get("job") or "").casefold() == "director" for job in jobs):
                if person.get("name"):
                    directors.append(str(person["name"]))
        if not directors:
            directors.extend(
                str(item.get("name"))
                for item in data.get("created_by", [])
                if item.get("name")
            )
        cast = [
            str(person.get("name"))
            for person in credits.get("cast", [])[:24]
            if person.get("name")
        ]
        runtimes = [int(v) for v in data.get("episode_run_time", []) if isinstance(v, int) and v > 0]
        if not runtimes:
            latest_runtime = (data.get("last_episode_to_air") or {}).get("runtime")
            if latest_runtime:
                runtimes = [int(latest_runtime)]
        vote_count = int(data.get("vote_count") or 0)
        status = str(data.get("status") or "")
        ended = status.casefold() in {"ended", "canceled", "cancelled"}
        tmdb_id = int(data["id"])
        return {
            "media_key": self.media_key("series", tmdb_id),
            "provider": "tmdb",
            "provider_id": str(tmdb_id),
            "tmdb_id": tmdb_id,
            "imdb_id": external.get("imdb_id") or None,
            "media_type": "series",
            "title": str(data.get("name") or data.get("original_name") or tmdb_id),
            "original_title": data.get("original_name") or None,
            "poster_source_url": self._image_source(data.get("poster_path")),
            "plot": data.get("overview") or None,
            "genres": [str(item.get("name")) for item in data.get("genres", []) if item.get("name")],
            "release_year": self._safe_year(data.get("first_air_date")),
            "end_year": self._safe_year(data.get("last_air_date")) if ended else None,
            "release_date": self._iso_date(data.get("first_air_date")),
            "runtime_minutes": runtimes[0] if runtimes else None,
            "countries": [
                str(item.get("name") or item.get("iso_3166_1"))
                for item in data.get("production_countries", [])
                if item.get("name") or item.get("iso_3166_1")
            ],
            "directors": list(dict.fromkeys(directors)),
            "cast": list(dict.fromkeys(cast)),
            "provider_rating": float(data.get("vote_average") or 0) if vote_count else None,
            "provider_vote_count": vote_count,
            "release_status": "ended" if ended else "ongoing",
            "season_count": int(data.get("number_of_seasons") or 0) or None,
            "episode_count": int(data.get("number_of_episodes") or 0) or None,
            "popularity": float(data.get("popularity") or 0),
            "raw_payload": data,
        }

    def _fetch_pages(
        self,
        path: str,
        *,
        params: dict[str, Any],
        required_items: int,
        max_pages: int = 10,
    ) -> tuple[list[dict[str, Any]], int]:
        items: list[dict[str, Any]] = []
        total = 0
        page = 1
        while len(items) < required_items and page <= max_pages:
            data = self._request(path, {**params, "page": page})
            if page == 1:
                total = int(data.get("total_results") or 0)
            batch = data.get("results") or []
            if not batch:
                break
            items.extend(item for item in batch if isinstance(item, dict))
            if page >= int(data.get("total_pages") or 1):
                break
            page += 1
        return items, total

    def _search_person_credits(
        self, name: str, *, director: bool
    ) -> list[dict[str, Any]]:
        people = self._request(
            "/search/person",
            {
                "query": name,
                "include_adult": str(self.settings.tmdb_include_adult).lower(),
                "page": 1,
            },
        ).get("results") or []
        results: list[dict[str, Any]] = []
        # A few candidates makes transliterations/duplicate names work without
        # exploding the number of TMDB calls.
        for person in people[:3]:
            if person.get("id") is None:
                continue
            credits = self._request(f"/person/{int(person['id'])}/combined_credits", {})
            if director:
                for item in credits.get("crew", []) or []:
                    if str(item.get("job") or "").casefold() != "director" and str(
                        item.get("department") or ""
                    ).casefold() != "directing":
                        continue
                    results.append(item)
            else:
                results.extend(credits.get("cast", []) or [])
        return results

    def _matches_filters(
        self,
        mapped: dict[str, Any],
        *,
        query: str | None,
        media_type: str | None,
        genre: str | None,
        year: int | None,
    ) -> bool:
        if media_type and mapped.get("media_type") != media_type:
            return False
        if query:
            haystack = " ".join(
                str(v or "") for v in (mapped.get("title"), mapped.get("original_title"))
            ).casefold()
            if query.casefold() not in haystack:
                return False
        if year and mapped.get("release_year") != year:
            return False
        if genre:
            genres = " ".join(mapped.get("genres") or []).casefold()
            if genre.casefold() not in genres:
                return False
        return True

    def _discover_or_title_results(
        self,
        *,
        query: str | None,
        media_type: str | None,
        genre: str | None,
        year: int | None,
        required_items: int,
    ) -> tuple[list[dict[str, Any]], int]:
        types = [media_type] if media_type else ["movie", "series"]
        raw_results: list[dict[str, Any]] = []
        total = 0

        def fetch_type(public_type: str) -> tuple[str, list[dict[str, Any]], int]:
            endpoint_type = self._endpoint_type(public_type)
            if query:
                path = f"/search/{endpoint_type}"
                params: dict[str, Any] = {
                    "query": query,
                    "include_adult": str(self.settings.tmdb_include_adult).lower(),
                }
                if year:
                    params[
                        "primary_release_year"
                        if public_type == "movie"
                        else "first_air_date_year"
                    ] = year
            else:
                path = f"/discover/{endpoint_type}"
                params = {
                    "include_adult": str(self.settings.tmdb_include_adult).lower(),
                    "sort_by": "popularity.desc",
                }
                if year:
                    params[
                        "primary_release_year"
                        if public_type == "movie"
                        else "first_air_date_year"
                    ] = year
                genre_id = self._genre_id(public_type, genre)
                if genre and genre_id is None:
                    return endpoint_type, [], 0
                if genre_id is not None:
                    params["with_genres"] = genre_id
            raw, subtotal = self._fetch_pages(
                path,
                params=params,
                required_items=required_items,
                max_pages=min(10, max(1, math.ceil(required_items / 20) + 1)),
            )
            return endpoint_type, raw, subtotal

        # A combined movie+TV search should not become a serial network
        # waterfall.  There are at most two independent provider branches.
        with ThreadPoolExecutor(max_workers=len(types)) as executor:
            futures = [executor.submit(fetch_type, public_type) for public_type in types]
            for future in as_completed(futures):
                endpoint_type, raw, subtotal = future.result()
                total += subtotal
                for item in raw:
                    normalized = dict(item)
                    normalized["media_type"] = endpoint_type
                    raw_results.append(normalized)
        return raw_results, total

    def search(
        self,
        *,
        query: str | None,
        media_type: str | None,
        actor: str | None,
        director: str | None,
        genre: str | None,
        year: int | None,
        page: int,
        page_size: int,
    ) -> ProviderSearchPage:
        query = query.strip() if query else None
        actor = actor.strip() if actor else None
        director = director.strip() if director else None
        genre = genre.strip() if genre else None
        required = max(page * page_size, page_size)

        if not any([query, media_type, actor, director, genre, year]):
            return ProviderSearchPage([], page, page_size, 0, 0)

        if actor or director:
            actor_items = self._search_person_credits(actor, director=False) if actor else None
            director_items = (
                self._search_person_credits(director, director=True) if director else None
            )
            pools: list[dict[str, dict[str, Any]]] = []
            for raw_pool in (actor_items, director_items):
                if raw_pool is None:
                    continue
                mapped_pool: dict[str, dict[str, Any]] = {}
                for raw in raw_pool:
                    mapped = self._map_search_item(raw, str(raw.get("media_type") or ""))
                    if not mapped or not self._matches_filters(
                        mapped,
                        query=query,
                        media_type=media_type,
                        genre=genre,
                        year=year,
                    ):
                        continue
                    mapped_pool[mapped["media_key"]] = mapped
                pools.append(mapped_pool)
            if not pools:
                mapped_items: list[dict[str, Any]] = []
            else:
                keys = set(pools[0])
                for pool in pools[1:]:
                    keys.intersection_update(pool)
                mapped_items = [pools[0][key] for key in keys]
            mapped_items.sort(
                key=lambda item: (
                    float(item.get("popularity") or 0),
                    int(item.get("provider_vote_count") or 0),
                ),
                reverse=True,
            )
            total = len(mapped_items)
            start = (page - 1) * page_size
            items = mapped_items[start : start + page_size]
            total_pages = math.ceil(total / page_size) if total else 0
            return ProviderSearchPage(items, page, page_size, total, total_pages)

        raw_results, provider_total = self._discover_or_title_results(
            query=query,
            media_type=media_type,
            genre=genre,
            year=year,
            required_items=required,
        )
        mapped_by_key: dict[str, dict[str, Any]] = {}
        for raw in raw_results:
            mapped = self._map_search_item(raw, str(raw.get("media_type") or ""))
            if not mapped:
                continue
            if not self._matches_filters(
                mapped,
                query=None,  # TMDB title search already handles translated/alternative names.
                media_type=media_type,
                genre=genre,
                year=year,
            ):
                continue
            mapped_by_key[mapped["media_key"]] = mapped
        mapped_items = sorted(
            mapped_by_key.values(),
            key=lambda item: (
                float(item.get("popularity") or 0),
                int(item.get("provider_vote_count") or 0),
            ),
            reverse=True,
        )
        start = (page - 1) * page_size
        items = mapped_items[start : start + page_size]
        total = max(provider_total, len(mapped_items))
        total_pages = math.ceil(total / page_size) if total else 0
        return ProviderSearchPage(items, page, page_size, total, total_pages)

    def _resolve_legacy_imdb(self, imdb_id: str) -> tuple[str, int]:
        data = self._request(
            f"/find/{imdb_id}",
            {"external_source": "imdb_id"},
        )
        movie = (data.get("movie_results") or [])
        if movie:
            return "movie", int(movie[0]["id"])
        tv = (data.get("tv_results") or [])
        if tv:
            return "series", int(tv[0]["id"])
        raise MediaNotFoundError(f"No TMDB title found for IMDb ID {imdb_id}")

    def get_title(self, media_key: str) -> dict[str, Any]:
        parsed = self.parse_media_key(media_key)
        if parsed is None and media_key.startswith("tt"):
            parsed = self._resolve_legacy_imdb(media_key)
        if parsed is None:
            raise MediaNotFoundError(f"Unsupported media identifier: {media_key}")
        media_type, tmdb_id = parsed
        if media_type == "movie":
            data = self._request(
                f"/movie/{tmdb_id}",
                {"append_to_response": "credits,external_ids"},
            )
            return self._map_movie_detail(data)
        data = self._request(
            f"/tv/{tmdb_id}",
            {"append_to_response": "aggregate_credits,external_ids"},
        )
        return self._map_tv_detail(data)

    def get_episodes(self, media_key: str) -> list[dict[str, Any]]:
        parsed = self.parse_media_key(media_key)
        if parsed is None and media_key.startswith("tt"):
            parsed = self._resolve_legacy_imdb(media_key)
        if parsed is None or parsed[0] != "series":
            return []
        _, tmdb_id = parsed
        details = self._request(f"/tv/{tmdb_id}", {})
        season_numbers = [
            int(item["season_number"])
            for item in details.get("seasons", [])
            if item.get("season_number") is not None
            and int(item.get("season_number") or 0) > 0
            and int(item.get("episode_count") or 0) > 0
        ]

        def fetch(number: int) -> tuple[int, dict[str, Any]]:
            return number, self._request(f"/tv/{tmdb_id}/season/{number}", {})

        seasons: dict[int, dict[str, Any]] = {}
        # Bounded concurrency prevents long-running series from turning into a
        # completely serial N-request waterfall while still respecting TMDB.
        with ThreadPoolExecutor(max_workers=min(6, max(1, len(season_numbers)))) as executor:
            futures = [executor.submit(fetch, number) for number in season_numbers]
            for future in as_completed(futures):
                number, payload = future.result()
                seasons[number] = payload

        result: list[dict[str, Any]] = []
        for season_number in sorted(seasons):
            payload = seasons[season_number]
            for item in payload.get("episodes", []) or []:
                if item.get("id") is None or item.get("episode_number") is None:
                    continue
                episode_id = int(item["id"])
                result.append(
                    {
                        "episode_key": self.episode_key(episode_id),
                        "provider": "tmdb",
                        "provider_id": str(episode_id),
                        "tmdb_id": episode_id,
                        "imdb_id": None,
                        "season_number": season_number,
                        "episode_number": int(item["episode_number"]),
                        "title": str(item.get("name") or f"Episode {item['episode_number']}"),
                        "release_date": self._iso_date(item.get("air_date")),
                        "runtime_minutes": int(item["runtime"]) if item.get("runtime") else None,
                        "plot": item.get("overview") or None,
                        "raw_payload": item,
                    }
                )
        return result

    def _map_list(self, items: Iterable[dict[str, Any]], hint: str) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for raw in items:
            mapped = self._map_search_item(raw, hint)
            if mapped:
                result.append(mapped)
        return result

    def home_sections(self) -> dict[str, list[dict[str, Any]]]:
        """Fetch independent TMDB home feeds concurrently.

        The home page used to make seven sequential upstream calls, which made
        the first uncached request unnecessarily slow on a small VPS.
        """
        requests: dict[str, tuple[str, dict[str, Any]]] = {
            "popular_movies": (
                "/movie/popular",
                {"page": 1, "region": self.settings.tmdb_region},
            ),
            "popular_series": ("/tv/popular", {"page": 1}),
            "now_movies": (
                "/movie/now_playing",
                {"page": 1, "region": self.settings.tmdb_region},
            ),
            "on_air_tv": ("/tv/on_the_air", {"page": 1}),
            "top_movies": (
                "/movie/top_rated",
                {"page": 1, "region": self.settings.tmdb_region},
            ),
            "top_tv": ("/tv/top_rated", {"page": 1}),
            "trending": ("/trending/all/week", {}),
        }

        payloads: dict[str, list[dict[str, Any]]] = {}

        def fetch(name: str, spec: tuple[str, dict[str, Any]]) -> tuple[str, list[dict[str, Any]]]:
            path, params = spec
            data = self._request(path, params)
            return name, [item for item in (data.get("results") or []) if isinstance(item, dict)]

        with ThreadPoolExecutor(max_workers=7) as executor:
            futures = [executor.submit(fetch, name, spec) for name, spec in requests.items()]
            for future in as_completed(futures):
                name, results = future.result()
                payloads[name] = results

        # Warm the two genre lookups concurrently as well; mapping search/home
        # summaries then performs no additional sequential genre requests.
        _ = self.genre_maps

        popular_movies = payloads.get("popular_movies", [])
        popular_tv = payloads.get("popular_series", [])
        now_movies = payloads.get("now_movies", [])
        on_air_tv = payloads.get("on_air_tv", [])
        top_movies = payloads.get("top_movies", [])
        top_tv = payloads.get("top_tv", [])
        trending = payloads.get("trending", [])

        new_releases = self._map_list(now_movies, "movie") + self._map_list(on_air_tv, "tv")
        new_releases.sort(
            key=lambda item: item.get("release_date") or "0000-00-00", reverse=True
        )
        top_rated = self._map_list(top_movies, "movie") + self._map_list(top_tv, "tv")
        top_rated.sort(
            key=lambda item: (
                float(item.get("provider_rating") or 0),
                int(item.get("provider_vote_count") or 0),
            ),
            reverse=True,
        )
        recommendations: list[dict[str, Any]] = []
        for raw in trending:
            mapped = self._map_search_item(raw, str(raw.get("media_type") or ""))
            if mapped:
                recommendations.append(mapped)

        return {
            "popular_movies": self._map_list(popular_movies, "movie")[:12],
            "popular_series": self._map_list(popular_tv, "tv")[:12],
            "new_releases": new_releases[:12],
            "top_rated": top_rated[:12],
            "recommendations": recommendations[:12],
        }

