# Simple Model Requirement Audit

This audit follows the supplied course PDF. The PDF names IMDb; this project intentionally uses TMDB instead by user decision while preserving the required **simple architecture**: mobile application directly calls the movie/TV information service and personal data is local.

## Architecture — PASS

- Mobile directly calls TMDB; there is no custom backend.
- UI, application logic, API communication and local persistence are separate layers.
- Personal information is stored in SQLite.

## Functional requirements

1. Registration — PASS. Local users table; first/last name, username, email, hashed password, optional avatar, bio; username/email unique.
2. Login/logout — PASS. Local verification; remembered session 30 days or shorter 1-day session; logout clears session.
3. Password recovery — PARTIAL BY ARCHITECTURAL LIMITATION. Same-device email lookup + expiring reset token is complete locally; actual email delivery requires an external mail/auth service and is intentionally absent in a no-server model.
4. Profile management — PASS.
5. Movie/series search — PASS. Title plus actor/director/genre/year/type support using TMDB search/discover/person credits.
6. Movie details — PASS using TMDB equivalents; local app-user rating is also shown.
7. Series details — PASS.
8. Seasons/episodes — PASS using TMDB season endpoints.
9. Watch status — PASS: plan_to_watch, watching, completed, paused, dropped; favorites independent.
10. Episode watched marking — PASS.
11. Watch progress — PASS; watched/remaining counts, exact percentage and required color states.
12. Watch library — PASS with pagination and filters.
13. Rating — PASS; 1–5 stars, edit/delete, distribution percentages.
14. Comments — PASS locally across accounts on the same device.
15. Spoiler comments — PASS; spoilers start hidden in UI.
16. Favorites — PASS.
17. Personal lists — PASS; create/edit/delete/add/remove; intentionally local/private.
18. Home content — PASS: popular movies, popular series, new releases, top rated, trending recommendations.
19. User statistics — PASS: movies, series, episodes, approximate watch time, favorite genre, average rating, favorites and list count.
20. Data/network error management — PASS with Persian error states and retry; stale JSON cache can serve temporary provider/network failures.

## Simple-model-specific requirements

- Connected directly to information API — PASS (TMDB substitution).
- Movie/series data direct from service — PASS.
- Async network requests — PASS (Dio futures).
- Loading indicators — PASS.
- Network error management — PASS.
- Appropriate display models — PASS.
- Personal data local — PASS (SQLite + SharedPreferences session metadata).
- Avoid unnecessary/repeated requests — PASS (in-flight deduplication + SQLite response cache).
- Poster temporary cache — PASS (`cached_network_image`).

## Non-functional requirements

- Performance: API response caching, image caching, pagination, request deduplication and concurrent home loading implemented.
- Usability: Persian RTL, responsive layouts, clear validation/errors/loading states.
- Security: local passwords stored as salted PBKDF2-HMAC-SHA256 hashes; HTTPS-only TMDB endpoints; parameterized SQLite queries. The TMDB application read credential is build-time configured and is inherently client-visible in a direct-client model.
- Reliability: SQLite transactions/constraints, WAL, stale API cache fallback, idempotent local upserts.
- Compatibility: Flutter Android UI adapts to different sizes.
- Maintainability: UI/API/storage/security separated into modules.
- Scalability: search and local library/comments use pagination; API/provider layer is replaceable.
- Resource usage: image cache, JSON response TTL cache, no background polling, deduplicated requests.

## Deliberately not included

The advanced-only backend/server items are absent by design: FastAPI/backend API, PostgreSQL server database, Redis, JWT server authentication, admin panel, server-side validation, Swagger/OpenAPI, Docker/Nginx deployment and server-side provider caching.
