# Advanced model requirement traceability

Source: `project-requirements-fa.pdf`. This matrix checks the advanced model plus the functional/non-functional sections that apply to the application.

**Provider decision:** the PDF names IMDb. The team has explicitly selected TMDB instead because the official IMDb commercial API is not suitable for this student project. Rows whose literal text requires IMDb are therefore marked **TMDB substitution**, while the advanced backend architecture is fully implemented.

## Actors and functional requirements

| Section | Requirement | Status | Implementation |
|---|---|---|---|
| 4.1 | Guest search | ✅ | public `/media/search`, SearchScreen |
| 4.1 | Guest details/popular/seasons/episodes | ✅ | Home, detail, seasons APIs/UI |
| 4.2 | User profile | ✅ | users DB + ProfileScreen |
| 4.2 | Add titles/watch status | ✅ | `user_media`, library API/UI |
| 4.2 | Watched episodes | ✅ | `user_episodes` |
| 4.2 | Ratings/comments | ✅ | ratings/comments tables + UI |
| 4.2 | Favorites/custom lists | ✅ | favorites/custom_lists |
| 4.2 | Activity statistics | ✅ | `/me/stats`, `/me/activity` |
| 4.3 | Manage users | ✅ | admin endpoints/UI |
| 4.3 | Delete inappropriate comments | ✅ | admin moderation |
| 4.3 | Review reports | ✅ | reports workflow |
| 4.3 | Manage cached titles | ✅ | admin media cache endpoints |
| 4.3 | Overall statistics | ✅ | admin stats |
| 4.4 | External movie service | ⚠️ TMDB substitution | real TMDB provider |
| 5.1 | Registration fields + optional image/bio | ✅ | auth schemas/API/Flutter |
| 5.1 | automatic profile counts/favorites | ✅ | stats/profile APIs |
| 5.1 | duplicate username/email prevention | ✅ | unique DB + 409 validation |
| 5.2 | Login/logout + 30-day or shorter session | ✅ | JWT + rotating refresh tokens |
| 5.3 | Password recovery by email | ✅ | reset-token + SMTP/console mail |
| 5.4 | Profile view/edit | ✅ | `/me`, upload/delete avatar |
| 5.5 | Search title | ✅ | live TMDB search |
| 5.5 | actor/director/genre/year filters | ✅ | TMDB person credits/discover/search |
| 5.6 | Movie detail fields | ✅ | TMDB details + credits/external IDs |
| 5.7 | Series detail fields | ✅ | TV detail + aggregate credits |
| 5.8 | Seasons/episodes fields | ✅ | real TMDB season endpoints + cache |
| 5.9 | Watch status | ✅ | five statuses + independent favorite |
| 5.10 | Watched episode marking/counts | ✅ | user episode API/model |
| 5.11 | Progress percent and colors | ✅ | backend calculation + Flutter bar |
| 5.12 | Watch list sections | ✅ | library filters/statuses |
| 5.13 | 1–5 rating, percentages, edit | ✅ | unique rating + distribution |
| 5.14 | Comment metadata | ✅ | text/user/avatar/date/spoiler |
| 5.15 | Spoiler initially hidden | ✅ | spoiler UI reveal |
| 5.16 | Separate favorites | ✅ | favorites table/API/UI |
| 5.17 | Personal list CRUD/items | ✅ | custom lists/items |
| 5.18 | popular movie/TV/new/top/recommendations | ✅ | TMDB home feeds + personalization |
| 5.19 | User stats | ✅ | movies/series/episodes/time/genre/rating |
| 5.20 | Network/provider errors | ✅ | standardized errors + retry/offline UI |

## Advanced model requirements

| Section | Requirement | Status | Implementation |
|---|---|---|---|
| 7.1 | Independent backend | ✅ | FastAPI |
| 7.2 | Custom mobile API | ✅ | versioned `/api/v1`, OpenAPI |
| 7.3 | Backend fetches external media data, normalizes response | ⚠️ TMDB substitution | `services/providers/tmdb.py` + `services/media.py` |
| 7.4 | Server database | ✅ | PostgreSQL + Alembic; all suggested entities |
| 7.5 | Temporary external-data storage/cache | ✅ | Redis + durable DB + poster disk cache |
| 7.6 | Authentication | ✅ | JWT access + rotating refresh |
| 7.7 | User/admin access levels | ✅ | RBAC dependencies/endpoints |
| 7.8 | Server-side validation | ✅ | Pydantic + DB constraints |
| 7.9 | Standard server errors | ✅ | AppError envelope + middleware |
| 7.10 | API documentation | ✅ | Swagger/ReDoc/OpenAPI |

## Non-functional requirements

| Section | Requirement | Status | Notes |
|---|---|---|---|
| 8.1 | normal pages <3s | ✅ design / runtime benchmark required | cache, lazy detail sections, optimized posters |
| 8.1 | reasonable search | ✅ | live TMDB + bounded paging/fallback |
| 8.1 | optimized images | ✅ | backend WebP resize/cache |
| 8.1 | pagination/lazy lists | ✅ | paginated search/library/comments |
| 8.1 | avoid unnecessary requests | ✅ | TTL cache; poster route avoids full-detail fanout |
| 8.1 | concurrent users | ✅ architecture | FastAPI/threadpool + DB pool; one worker chosen for 1GB VPS |
| 8.2 | simple UI/easy navigation | ✅ | Material UI/bottom navigation |
| 8.2 | clear errors/forms/RTL/loading | ✅ | Persian RTL + validation/loading/error states |
| 8.3 | password not plaintext | ✅ | Argon2 |
| 8.3 | HTTPS + CA pin | ✅ | Nginx TLS + Flutter pinning |
| 8.3 | external keys hidden | ✅ | server env only |
| 8.3 | authorized data access | ✅ | RBAC/ownership checks |
| 8.3 | secure token storage | ✅ | flutter_secure_storage |
| 8.3 | malicious input defense | ✅ | validation, bound SQL, upload checks, poster SSRF allowlist |
| 8.4 | user activity survives ordinary errors | ✅ | PostgreSQL transactions |
| 8.4 | offline message | ✅ | API exception/offline UI |
| 8.4 | no duplicate mutation | ✅ | unique constraints + idempotency |
| 8.4 | provider outage does not kill whole backend | ✅ | local auth/user data + stale cache fallback |
| 8.5 | common Android versions/screen sizes | ✅ project config | responsive Flutter layouts |
| 8.6 | readable/modular/separated code | ✅ | features/repository/provider/services layers |
| 8.7 | future scaling | ✅ | provider abstraction, migrations, API modules |
| 8.8 | reduce battery/network use | ✅ | caching, no polling, compressed posters |

## Literal mismatch to be disclosed in presentation/report

The original document says IMDb in sections 4.4, 5.5, 7.3, 7.5 and architecture diagrams. This build uses TMDB. Do not tell the instructor that it is literally IMDb-backed; describe the provider substitution accurately.
