# Testing and acceptance

## Automated backend

```bash
cd backend
PYTHONPATH=. python -m pytest -q
python -m compileall -q app tests alembic
```

Tests cover authentication/session behavior, advanced media/user flows, admin/errors, live-search semantics via a deterministic fake provider, and the concrete TMDB v3 adapter request/normalization behavior with `httpx.MockTransport`.

The fake provider exists **only in tests**; production factory supports TMDB.

## Real-provider acceptance

Requires the team's real server-side TMDB credential:

```bash
PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python \
  scripts/check_tmdb_live.py Interstellar
```

This is the proof that the deployed backend is not using a tiny hard-coded catalog.

## API manual acceptance

```text
GET /api/v1/media/provider-status
GET /api/v1/media/search?q=Interstellar
GET /api/v1/media/search?actor=Leonardo%20DiCaprio
GET /api/v1/media/search?director=Christopher%20Nolan
GET /api/v1/media/search?genre=Science%20Fiction&year=2014
```

Open one returned `media_id`, then its poster and seasons if series.

## Flutter

On a machine with Flutter/Android SDK:

```bash
cd mobile
flutter pub get
flutter analyze
flutter test
```

The release verification script also rejects custom Kotlin/Java application source.

## Performance acceptance

Measure `/media/home` and search through public Nginx and direct localhost. The UI renders loading states and posters independently; poster requests reuse summary rows so they do not force one full TMDB details API request per card.
