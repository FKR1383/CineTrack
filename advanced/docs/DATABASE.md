# Database

Production uses PostgreSQL with Alembic migrations.

## User/account data

- `users`: identity, profile, role, active state, Argon2 password hash
- `refresh_tokens`: rotating/revocable login sessions
- `password_reset_tokens`: one-time hashed reset tokens

## Media cache

- `media`: provider-neutral media key, provider/TMDB IDs, optional external IMDb ID, metadata, upstream poster source, cache timestamp
- `seasons`
- `episodes`

The physical legacy columns named `imdb_id`/`imdb_rating` are preserved by SQLAlchemy mappings where needed to migrate the old database without deleting user references. API semantics are generic (`media_id`, `provider_rating`).

## User activity

- `user_media`: watch status
- `user_episodes`: watched episode markers
- `ratings`: unique 1–5 rating per user/title
- `comments`: spoiler/hidden moderation state
- `favorites`
- `custom_lists`
- `custom_list_items`
- `reports`
- `idempotency_records`
- `audit_logs`

Foreign keys and unique constraints prevent duplicate ratings/favorites/list items and keep user data consistent.

## Migration from the previous build

Migration `0002_tmdb_provider.py` adds provider/TMDB identity columns while keeping existing rows and their user relationships. Previous rows are marked `legacy`; new TMDB rows can coexist. Old IMDb media keys can still be resolved through TMDB `/find` when opened, allowing gradual migration rather than destructive reset.

## Cache strategy

- Search: live TMDB request by default; Redis stores previous result for fallback.
- Details: PostgreSQL TTL cache.
- Episodes: PostgreSQL TTL cache.
- Home: TMDB section keys cached in Redis; media rows durable in PostgreSQL.
- Posters: optimized WebP disk cache under the upload directory.
