# CineTrack advanced-model feature-by-feature checklist

Source of requirements: `docs/project-requirements-fa.pdf`.

> Provider decision: the assignment names IMDb. The team later chose **TMDB**. Therefore provider-specific rows are implemented with TMDB and are intentionally marked as a substitution, while the required advanced architecture remains `Flutter -> custom backend -> external movie/TV service`.

## System actors (section 4)

| Requirement | Status | Backend proof | Flutter proof |
|---|---|---|---|
| Guest can search movie/series | ✅ | `GET /api/v1/media/search`, `services/providers/tmdb.py` | `features/search/search_screen.dart` |
| Guest can view title details | ✅ | `GET /api/v1/media/{media_id}` | `features/media/media_detail_screen.dart` |
| Guest can view popular/new/top/recommended titles | ✅ | `GET /api/v1/media/home`, real TMDB feeds | `features/home/home_screen.dart` |
| Guest can view seasons/episodes | ✅ | `GET /api/v1/media/{media_id}/seasons` | media detail screen |
| Member has profile | ✅ | `/users/me`, PostgreSQL `users` | profile screen |
| Member can manage watch state | ✅ | `/me/library/{media_id}`, `user_media` | library/detail UI |
| Member can mark watched episodes | ✅ | `/me/episodes/{episode_id}`, `user_episodes` | episode UI |
| Member can rate/comment | ✅ | ratings/comments APIs + tables | detail UI |
| Member can favorite/create lists | ✅ | favorites/custom-list APIs | lists/library UI |
| Member can see activity statistics | ✅ | `/users/me/stats`, `/users/me/activity` | profile UI |
| Admin can manage users | ✅ | `/admin/users*` + RBAC | admin screen |
| Admin can remove inappropriate comments | ✅ | `DELETE /admin/comments/{comment_id}` | admin screen |
| Admin can review reports | ✅ | `/admin/reports*` | admin screen |
| Admin can manage cached media | ✅ | `/admin/media*` | admin screen |
| Admin can see system statistics | ✅ | `/admin/stats` | admin screen |
| External media service | ⚠️ TMDB substitution | `services/providers/tmdb.py` | Flutter never calls TMDB directly |

## Functional requirements (section 5)

| § | Requirement | Status | Implementation proof |
|---|---|---|---|
| 5.1 | Registration: name, username, email, password, optional avatar/bio | ✅ | `api/v1/auth.py`, auth schemas, `register_screen.dart` |
| 5.1 | Automatic profile statistics/favorites | ✅ | `services/users.py`, `/users/me/stats` |
| 5.1 | Duplicate email/username prevention | ✅ | DB unique constraints + registration conflict handling |
| 5.2 | Email/password login and secure logout | ✅ | JWT access + rotating/revocable refresh tokens |
| 5.2 | 1-month remembered login / shorter session option | ✅ | `remember_me`, 30-day vs 1-day refresh lifetime |
| 5.3 | Password recovery by email | ✅ | reset-token DB + SMTP/console mail modes + deep-link screen |
| 5.4 | View/edit profile | ✅ | `GET/PATCH /users/me`, avatar upload/delete |
| 5.5 | Search by title | ✅ | live `/search/movie` + `/search/tv` through TMDB provider |
| 5.5 | Search/filter actor | ✅ | `/search/person` + combined credits |
| 5.5 | Search/filter director | ✅ | person crew credits filtered to directing |
| 5.5 | Search/filter genre/year/type | ✅ | TMDB discover/search + genre maps |
| 5.6 | Movie title/original title/poster/plot/year/runtime/genre/country/director/cast/provider rating/app rating | ✅ | movie detail mapping + CineTrack rating aggregate |
| 5.7 | Series title/poster/plot/genre/start/end/status/seasons/episodes/cast/provider rating | ✅ | TV detail + aggregate credits |
| 5.8 | Season/episode number/title/date/runtime/plot/watched | ✅ | TMDB season endpoints + `seasons_for()` + user markers |
| 5.9 | Watch status | ✅ | five-state `WatchStatus` persisted in `user_media` |
| 5.9 | Favorite independent of watch status | ✅ | separate `favorites` table/API |
| 5.10 | Mark episodes watched + watched/remaining counts | ✅ | `user_episodes` + progress API |
| 5.11 | Exact series progress percentage | ✅ | backend progress calculation + Flutter progress UI |
| 5.11 | Required progress color states | ✅ | `library_screen.dart` / UI helpers |
| 5.12 | Watch-list sections | ✅ | library filters for watching/watched/planned/favorites |
| 5.13 | 1–5 stars, percentage distribution, edit rating | ✅ | unique rating per user/title + distribution response |
| 5.14 | Comment text/user/avatar/date/spoiler | ✅ | comments schema/service/UI |
| 5.15 | Spoilers hidden initially, reveal on action | ✅ | detail comment UI |
| 5.16 | Separate favorites list | ✅ | favorites API/UI |
| 5.17 | Personal lists CRUD + add/remove titles | ✅ | `/me/lists*`, lists screen |
| 5.18 | Popular movies/series/new/top/recommended home sections | ✅ | real TMDB home feeds + personalized local recommendations |
| 5.19 | Watched movie/series/episode counts | ✅ | `/users/me/stats` |
| 5.19 | Approximate watch time | ✅ | stats service from runtime/episodes |
| 5.19 | Favorite genre | ✅ | stats aggregation |
| 5.19 | Average submitted rating | ✅ | stats aggregation |
| 5.20 | Network/provider/not-found/unavailable errors | ✅ | standardized `AppError`, Dio `ApiException`, retry/error UI |

## Advanced-model requirements (section 7)

| § | Requirement | Status | Implementation proof |
|---|---|---|---|
| 7.1 | Independent backend | ✅ | FastAPI project under `backend/` |
| 7.2 | Custom API for mobile | ✅ | versioned `/api/v1`; 41 documented paths |
| 7.3 | Backend calls external movie/TV service and normalizes data | ⚠️ TMDB substitution | `services/providers/tmdb.py` -> `services/media.py` |
| 7.4 | Server database | ✅ | PostgreSQL + SQLAlchemy + Alembic |
| 7.4 | Users | ✅ | `users` |
| 7.4 | Movies/series | ✅ | unified `media` with provider/type fields |
| 7.4 | Seasons/episodes | ✅ | `seasons`, `episodes` |
| 7.4 | User watch status | ✅ | `user_media` |
| 7.4 | Ratings/comments/favorites/lists/reports | ✅ | corresponding normalized tables |
| 7.5 | External-data cache | ✅ | PostgreSQL durable cache + Redis TTL + disk poster cache |
| 7.5 | Reduced provider calls | ✅ | details/episodes TTL, home TTL, poster disk cache |
| 7.5 | Provider outage fallback | ✅ | stale Redis/DB/media/poster fallback when data exists |
| 7.6 | Authentication | ✅ | JWT access + rotating refresh + Argon2 |
| 7.7 | User/admin roles | ✅ | RBAC dependencies and admin-only routes |
| 7.8 | Server-side validation | ✅ | Pydantic constraints + DB constraints + upload validation |
| 7.9 | Standard errors | ✅ | HTTP status/code/message/detail/request-id envelope |
| 7.10 | API documentation | ✅ | Swagger, ReDoc, `docs/openapi.json` |

## Non-functional requirements (section 8)

| § | Requirement | Status | Implementation proof / qualification |
|---|---|---|---|
| 8.1 | Main pages target <3 sec | ✅ design; runtime must be measured on deployment | lazy detail sections, provider/cache strategy, benchmark script |
| 8.1 | Reasonable search latency | ✅ | bounded provider requests, pagination, Redis fallback |
| 8.1 | Optimized images | ✅ | server resizes and converts posters to WebP |
| 8.1 | Pagination/lazy loading | ✅ | search/library/comments pagination; secondary detail async |
| 8.1 | Avoid unnecessary repeated requests | ✅ | GET de-duplication, TTL caches, poster cache |
| 8.1 | Concurrent users | ✅ architecture | async FastAPI endpoints where appropriate + DB pool/provider bounded concurrency; deployment uses one worker for 1GB VPS |
| 8.2 | Simple UI/navigation | ✅ | bottom navigation + Material components |
| 8.2 | Clear errors/client validation/RTL/loading | ✅ | Persian RTL app, form validators, loaders/errors/retry |
| 8.3 | Passwords not plaintext | ✅ | Argon2 hashes |
| 8.3 | HTTPS + custom CA pin | ✅ | Nginx TLS + SHA-256 Flutter certificate pin |
| 8.3 | External API secret hidden from users | ✅ | TMDB token/key only in server environment |
| 8.3 | Authorized data access | ✅ | ownership checks + RBAC |
| 8.3 | Secure token storage | ✅ | `flutter_secure_storage` |
| 8.3 | Malicious-input protection | ✅ | validation, ORM-bound SQL, file checks, poster origin allowlist |
| 8.4 | Activity survives ordinary failures | ✅ | transactional PostgreSQL |
| 8.4 | Internet disconnected message | ✅ | Dio/connectivity error mapping |
| 8.4 | Mutations not repeated unintentionally | ✅ | idempotency keys + DB uniqueness |
| 8.4 | External provider outage doesn't kill backend | ✅ | authentication/user data independent + cached media fallback |
| 8.5 | Common Android versions/responsive screens | ✅ | Flutter responsive layouts + Android config |
| 8.6 | Maintainable/modular/separated layers | ✅ | Flutter feature/repository layers + backend API/service/provider layers |
| 8.7 | Scalable/extensible structure | ✅ | provider abstraction, migrations, versioned API, normalized DB |
| 8.8 | Reduce battery/network usage | ✅ | no polling, request de-duplication, caches, compressed posters |

## Production acceptance commands

After placing a **new/rotated** TMDB token in the server environment:

```bash
PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python \
  /path/to/project/scripts/check_tmdb_live.py Interstellar
```

Expected prefix: `TMDB LIVE OK:`. This deliberately searches a real title outside the old demo catalog.

```bash
curl http://127.0.0.1:8000/ready
curl --cacert /etc/nginx/tls/timetv/ca.crt \
  https://31.57.118.82/api/v1/media/provider-status
```

For performance evidence:

```bash
./scripts/benchmark_api.sh https://31.57.118.82 /etc/nginx/tls/timetv/ca.crt
```
