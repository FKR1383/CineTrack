# Implementation validation summary

This document records build-time checks; `ADVANCED_MODEL_AUDIT.md` contains the requirement-by-requirement audit.

- Production provider factory: TMDB only.
- No hard-coded production movie catalog.
- Search attempts TMDB on every request when `TMDB_SEARCH_LIVE=true`.
- PostgreSQL user database and durable media cache.
- Redis fallback cache.
- Same-origin poster proxy/cache and Flutter pinned image transport.
- Native Ubuntu deployment; no Docker runtime required.
- Automated backend suite includes direct TMDB adapter contract test using mocked HTTP transport plus integration tests.
- Secrets excluded from source archive.
- Flutter application logic is Dart.

Runtime live-TMDB acceptance cannot be embedded in a public artifact because it requires the team's private token. Run `scripts/check_tmdb_live.py` after credential configuration.
