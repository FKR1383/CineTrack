# Advanced model final audit

Audit target: the latest CineTrack source after the TMDB migration.

## Executive result

The project has a real independent backend, user database and server-owned activity data. The old 11-title demo catalog and `placehold.co` poster generation are absent from the production path. Search is backed by TMDB, normalized in FastAPI, persisted in PostgreSQL, cached/fallback via Redis and returned to Flutter. Posters are real TMDB artwork proxied through the backend and cached as WebP.

The only deliberate difference from the assignment wording is the external provider name: **TMDB replaces IMDb by team decision**. `REQUIREMENTS_TRACEABILITY.md` identifies every literal IMDb row rather than claiming false compliance.

## Confirmed advanced components

### Backend/API

- FastAPI versioned custom API.
- Search/home/details/seasons/episodes provider service.
- PostgreSQL persistence and Alembic migration.
- Redis fallback/search/home cache.
- Swagger/ReDoc/OpenAPI.
- standardized errors/request IDs/rate limiting/idempotency.

### Real external data

Production factory supports TMDB, not demo. With server credential configured:

```text
Flutter -> /media/search -> FastAPI -> TMDB -> normalize -> DB/cache -> Flutter
```

`TMDB_SEARCH_LIVE=true` attempts TMDB on each search. Details/episodes retain TTL cache because repeatedly downloading unchanged details would violate the resource/caching goals of the project.

### Users

PostgreSQL stores accounts, Argon2 hashes, sessions, password resets, watch state, episode markers, ratings, comments, favorites, lists, reports and activity-related records. User data is not just local Flutter state.

### Posters

Old failure cause:

```text
Demo provider -> placehold.co text placeholder
```

Final path:

```text
TMDB poster_path -> private backend upstream URL
 -> /api/v1/media/{media_id}/poster
 -> origin/size/content validation
 -> resize/WebP/disk cache
 -> Flutter pinned same-origin bytes
```

The poster route first uses the already-cached search/home row, so loading a grid of posters does not cause a full TMDB details call for every card.

### Reliability

- provider outage: cached search/media/posters can continue where available;
- auth/library/admin remain independent of TMDB availability;
- writes use DB constraints/idempotency;
- PostgreSQL is authoritative for user activity.

## Runtime proof

Because the release archive intentionally contains no private TMDB token, run this on the deployed server after configuring credentials:

```bash
PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python \
  scripts/check_tmdb_live.py Interstellar
```

A successful response proves a real TMDB title outside the former demo set can be searched.

## Automated verification

The backend suite contains integration tests plus a direct TMDB adapter test using an HTTP mock transport to verify v3 paths and normalization. Run `pytest -q`. Flutter should be validated with `flutter analyze` and `flutter test` on a machine with Flutter SDK.
