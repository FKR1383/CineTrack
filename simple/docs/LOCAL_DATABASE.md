# Local SQLite Database

Database file: `cinetrack_simple.db` in the application's private database directory.

Tables:

- `users`
- `password_reset_tokens`
- `media_cache`
- `api_cache`
- `user_media`
- `ratings`
- `comments`
- `custom_lists`
- `custom_list_items`
- `user_episodes`
- `activity`
- `reports`

All personal application state lives locally. Foreign keys are enabled and SQLite WAL mode is requested for reliability.
