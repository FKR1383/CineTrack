# Flutter ↔ CineTrack API connection

Default production base URL:

```text
https://31.57.118.82/api/v1
```

The Flutter app receives the URL and certificate fingerprint at build/run time:

```bash
flutter run \
  --dart-define="API_BASE_URL=https://31.57.118.82/api/v1" \
  --dart-define="CERT_SHA256=<sha256 fingerprint>"
```

## Authentication

Access token is sent as:

```http
Authorization: Bearer <access-token>
```

Refresh tokens are stored in secure storage and rotated server-side. Logout revokes the refresh session and clears device tokens.

## Main public endpoints

```text
GET /media/provider-status
GET /media/home
GET /media/search
GET /media/{media_id}
GET /media/{media_id}/poster
GET /media/{media_id}/seasons
GET /media/{media_id}/comments
```

## User endpoints

Registration/login/reset/profile, library/watch state, favorites, ratings, episode markers, personal lists, comments/reports and activity/statistics are documented in Swagger/OpenAPI.

## Errors

Application errors use a stable envelope with HTTP status, code, message, optional detail and request ID. Flutter maps network/offline/validation/not-found/provider errors to Persian user-facing messages.

## Idempotency

Sensitive POST/PUT operations can send `Idempotency-Key`; the backend persists scoped responses so retrying a request does not accidentally duplicate the action.

## Images

Poster paths returned by the API are same-origin paths. Flutter uses the same pinned Dio client to download bytes and keeps an in-memory cache. It intentionally rejects direct cross-origin poster URLs.
