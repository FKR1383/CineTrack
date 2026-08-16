# TMDB provider setup

CineTrack production uses the real TMDB API through the backend.

## Secrets

Use the **API Read Access Token** as the preferred credential. The API Key is supported as a fallback.

Never commit either value and never place them in Flutter `--dart-define` values.

Production environment file:

```text
/etc/timetv/timetv.env
```

Required configuration:

```env
MEDIA_PROVIDER=tmdb
TMDB_READ_ACCESS_TOKEN=<secret bearer token>
TMDB_API_KEY=<optional secret api key>
TMDB_LANGUAGE=en-US
TMDB_REGION=US
TMDB_INCLUDE_ADULT=false
TMDB_SEARCH_LIVE=true
```

Configure interactively without echoing the token:

```bash
sudo ./scripts/configure_tmdb.sh /etc/timetv/timetv.env
```

## Runtime behavior

With `TMDB_SEARCH_LIVE=true`, every non-empty search request attempts a fresh TMDB API request. A successful result is normalized and persisted to PostgreSQL and also stored as a Redis fallback. If TMDB is temporarily unavailable, a previous Redis/PostgreSQL result may be returned.

Movie/TV details and episodes are TTL-cached to avoid repeated upstream downloads.

## Live acceptance test

```bash
cd /opt/timetv/backend
set -a
source /etc/timetv/timetv.env
set +a
PYTHONPATH=/opt/timetv/backend /opt/timetv/venv/bin/python \
  /path/to/project/scripts/check_tmdb_live.py Interstellar
```

Success example:

```text
TMDB LIVE OK: Interstellar media_id=tmdb-movie-157336 tmdb_id=157336 poster=yes
```

The script never prints credentials.

## APIs used

The adapter uses TMDB v3 endpoints for:

- movie/TV search and discover
- person search + combined credits for actor/director filtering
- movie and TV details
- aggregate TV credits and external IDs
- TV seasons/episodes
- popular, now-playing/on-air, top-rated and trending feeds
- TMDB image CDN only from the backend poster proxy

## Poster security

Flutter never receives `image.tmdb.org` URLs. PostgreSQL keeps the upstream image URL private and the public API exposes only:

```text
/api/v1/media/{media_id}/poster
```

The poster service accepts only the configured TMDB image hostname, preventing the proxy from becoming an arbitrary URL fetcher.

## Credential rotation

If a TMDB credential appears in a screenshot/chat/public repository, rotate it in TMDB before production and rerun `configure_tmdb.sh` followed by `update_native_backend.sh`.
