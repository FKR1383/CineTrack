# Simple Model Architecture

## Runtime flow

```text
Flutter UI
   ↓
Application / repository layer
   ├──────────────→ TMDB v3 HTTPS API
   │                    ↓
   │              movie/TV/person data
   │
   └──────────────→ SQLite local database
                        ↓
                 accounts, sessions,
                 library, ratings,
                 comments, lists,
                 episodes, activity,
                 API response cache
```

Posters are downloaded from TMDB's image CDN and cached by `cached_network_image` on the device.

## Layers

- `lib/features/*`: UI and user flows.
- `lib/features/shared/repository.dart`: application/data orchestration.
- `lib/core/api/tmdb_client.dart`: direct TMDB HTTPS transport, request deduplication and response cache.
- `lib/core/storage/local_database.dart`: SQLite schema.
- `lib/core/storage/session_store.dart`: remembered local login session.
- `lib/core/security/password_hasher.dart`: salted PBKDF2-HMAC-SHA256 local password hashing.

## No server

The project deliberately contains no backend directory and no server deployment. The simple model's personal data is local to the installed application/device.
