# TMDB Setup

The app uses TMDB v3 directly with application-level Bearer authentication.

1. Open your TMDB account settings.
2. Open API settings.
3. Use the **API Read Access Token**.
4. Do not commit it to source control.
5. Pass it with `--dart-define=TMDB_READ_ACCESS_TOKEN=...`.

Examples:

```bash
TMDB_READ_ACCESS_TOKEN='...' ../scripts/run_flutter.sh
```

```bash
flutter build apk --release \
  --dart-define=TMDB_READ_ACCESS_TOKEN='...' \
  --dart-define=TMDB_LANGUAGE=en-US \
  --dart-define=TMDB_REGION=US
```

Official TMDB references used by the implementation:

- https://developer.themoviedb.org/docs/authentication-application
- https://developer.themoviedb.org/docs/finding-data
- https://developer.themoviedb.org/docs/search-and-query-for-details
- https://developer.themoviedb.org/docs/image-basics

Attribution displayed in the app:

> This product uses the TMDB API but is not endorsed or certified by TMDB.
