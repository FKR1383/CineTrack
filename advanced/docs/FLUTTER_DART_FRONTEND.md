# Flutter/Dart frontend

All application UI and logic is implemented in Flutter/Dart under `mobile/lib/`.

The Android folder contains build/manifest resources only. There is no custom Kotlin/Java application implementation; `FlutterActivity` comes from the Flutter SDK. Generated plugin registrant files created by Flutter tooling are not project application source.

## Main layers

- `core/api`: Dio, auth refresh, pinning, image bytes
- `core/auth`: secure token storage
- `features/auth`
- `features/home`
- `features/search`
- `features/media`
- `features/library`
- `features/lists`
- `features/profile`
- `features/admin`
- `features/shared`: repository/models/navigation helpers

## TMDB boundary

Flutter knows only CineTrack `media_id` values such as `tmdb-movie-157336`; it does not contain the TMDB token. Poster URLs returned to Flutter point back to the CineTrack API and are fetched with the pinned same-origin Dio client.

## Verification

```bash
./scripts/verify_flutter_frontend.sh
```
