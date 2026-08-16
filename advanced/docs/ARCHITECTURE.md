# Architecture

## Advanced client/server model

```text
Android user
   |
Flutter/Dart Persian RTL client
   | HTTPS + SHA-256 certificate pinning
   v
Nginx :443
   |
FastAPI :8000 (localhost only)
   |-- PostgreSQL : users + activities + durable media cache
   |-- Redis      : short-lived search/home fallback cache
   `-- TMDB API   : discovery/details/credits/seasons
          |
          `-- image.tmdb.org (backend only)
```

The mobile client communicates only with the CineTrack API. External-provider credentials and upstream poster URLs stay server-side.

## Layers

### Flutter

- presentation/features
- Riverpod auth/application state
- repository layer
- Dio API client
- secure token storage
- certificate pinning
- same-origin poster/avatar byte cache

### Backend

- FastAPI routers
- Pydantic request/response schemas
- services/business logic
- provider abstraction (`MediaProvider`)
- TMDB adapter
- SQLAlchemy models/repositories
- Redis cache
- security/middleware/error handling

### Data

PostgreSQL is authoritative for user-owned data. TMDB metadata is a durable cache that can be refreshed without changing user records.

## Search flow

```text
Search form
 -> GET /api/v1/media/search
 -> TMDBProvider.search
 -> TMDB API
 -> normalized provider-neutral Media payload
 -> PostgreSQL upsert
 -> Redis fallback copy
 -> Flutter paginated result
```

`TMDB_SEARCH_LIVE=true` means the live provider is attempted for each search; cache is fallback rather than the production catalog.

## Detail flow

Search/home records are summaries. Opening a title fetches TMDB full details once and caches cast, crew, runtime, countries and external IDs. The detail screen renders the main detail first; comments and TV seasons can load separately so slow episode fetches do not block the whole page.

## Poster flow

Home/search already has `poster_path`; a poster request reuses that cached summary and **does not trigger a full TMDB details call**. On first poster request the backend downloads the TMDB image, validates it, converts/resizes to WebP and caches it. Subsequent calls are local-file responses.

## Provider substitution note

The original assignment names IMDb. This repository intentionally uses TMDB instead, by project-team decision. The provider abstraction isolates that difference; the advanced client/server responsibilities remain unchanged.
