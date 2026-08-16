# CineTrack — Simple Model (Flutter + TMDB + SQLite)

This repository is the **simple-model** edition of CineTrack.

## Architecture

```text
User
  ↓
Flutter / Dart Android app
  ├── Direct HTTPS requests → TMDB API
  ├── Poster/image cache → device cache
  └── Personal data → local SQLite database
```

There is **no custom backend, server, Docker, PostgreSQL, Redis, Nginx, JWT, or server deployment** in this edition.

The course PDF names IMDb as the information provider. By explicit project decision, this implementation substitutes **TMDB** as the movie/TV provider while preserving the simple-model architecture (mobile app directly contacts the information API).

## Implemented features

- Guest access to home, search, details, seasons and episodes.
- Local registration with first/last name, username, unique email, password, optional avatar and bio.
- Local login/logout with 1-day or 30-day remembered session.
- Salted PBKDF2-HMAC-SHA256 password hashes; plaintext passwords are never stored.
- Same-device password recovery token flow (see limitation below).
- Profile editing and local avatar storage.
- TMDB search by title; filters for movie/series, actor, director, genre and year.
- Movie details: title/original title, poster, overview, year/date, runtime, genres, countries, director/creator, cast, TMDB rating and local CineTrack rating.
- Series details: poster, overview, genres, years, status, seasons, episodes, cast, ratings.
- Episode watched/unwatched marking and watched/remaining counts.
- Progress percentage and specified black/yellow/red/green/purple behavior.
- Watch states: plan to watch, watching, completed, paused, dropped.
- Independent favorites.
- 1–5 star local ratings with edit/delete and percentage distribution.
- Local comments with username/avatar/date/spoiler flag; spoiler text starts hidden.
- Personal local lists with add/remove/edit/delete.
- Home: popular movies, popular TV, new releases, top rated and trending recommendations.
- User statistics: watched movies/series/episodes, approximate watch time, favorite genre, average rating, favorites and list count.
- Activity history.
- SQLite API response cache with stale fallback for temporary network/provider failures.
- Cached network posters.
- Request deduplication for simultaneous identical TMDB requests.
- RTL Persian responsive UI, loading/empty/error/retry states and pagination.
- TMDB attribution notice.

## One limitation inherent to the local-only model

The assignment asks for password recovery "through email". A real secure email reset requires an external authentication/mail backend. This simple-model build intentionally has **no custom server**, so it implements a same-device email-address lookup that creates a 15-minute local reset token and immediately opens the reset screen. No claim is made that an email was actually sent.

## TMDB token

No API token is committed to this repository. Pass your TMDB **API Read Access Token** at run/build time:

```bash
--dart-define=TMDB_READ_ACCESS_TOKEN=YOUR_TOKEN
```

Because the simple architecture contacts TMDB directly, an application credential is necessarily present in the compiled client. Do not use a personal/account-management credential; use the TMDB application read token intended for API access.

## Verify TMDB access

Before running Flutter, you can verify the application read token without storing it in the project:

```bash
TMDB_READ_ACCESS_TOKEN='YOUR_TOKEN' ./scripts/check_tmdb.sh Interstellar
```

## Run

```bash
cd mobile
flutter clean
flutter pub get
flutter analyze
TMDB_READ_ACCESS_TOKEN='YOUR_TOKEN' ../scripts/run_flutter.sh
```

Or directly:

```bash
flutter run \
  --dart-define=TMDB_READ_ACCESS_TOKEN='YOUR_TOKEN' \
  --dart-define=TMDB_LANGUAGE=en-US \
  --dart-define=TMDB_REGION=US
```

## Build APK

```bash
cd mobile
TMDB_READ_ACCESS_TOKEN='YOUR_TOKEN' ../scripts/build_android.sh
```

Output:

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

See `docs/SIMPLE_MODEL_AUDIT.md` for requirement-by-requirement coverage.


## Final login, biometric and cache behavior

- Every successful login is remembered for **30 days**.
- Biometric unlock is optional and can be enabled at login or later from Profile. It protects a still-valid remembered session; secure logout removes that session and disables biometric unlock.
- Android biometric authentication uses the Flutter `local_auth` plugin and requires an enrolled fingerprint/face on the device.
- **Safe cache cleanup** in Profile clears TMDB/API/image cache but preserves users, ratings, comments, favorites, personal lists, watch status, watched episodes and activity.
- App display name: **Cine Track Simple** with the blue/black Cine Track branding.
