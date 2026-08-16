# API examples

Base path: `/api/v1`

## Provider status

```http
GET /api/v1/media/provider-status
```

Example response:

```json
{"provider":"tmdb","configured":true,"live_search":true,"architecture":"Flutter -> CineTrack backend -> TMDB"}
```

## Search

```http
GET /api/v1/media/search?q=Interstellar&page=1&page_size=20
```

```http
GET /api/v1/media/search?actor=Bryan%20Cranston&media_type=series
```

```http
GET /api/v1/media/search?director=Christopher%20Nolan&year=2014
```

A result uses a provider-neutral application identifier:

```json
{
  "media_id": "tmdb-movie-157336",
  "media_type": "movie",
  "title": "Interstellar",
  "poster_url": "/api/v1/media/tmdb-movie-157336/poster",
  "provider_rating": 8.5
}
```

## Detail

```http
GET /api/v1/media/tmdb-movie-157336
```

## Poster

```http
GET /api/v1/media/tmdb-movie-157336/poster
```

The server fetches/optimizes/caches the upstream image; Flutter does not use the TMDB CDN URL directly.

## Swagger

Use `/docs` and `docs/openapi.json` for the complete request/response contract.
