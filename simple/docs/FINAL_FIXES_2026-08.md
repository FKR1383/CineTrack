# Final fixes – Cine Track Simple

- Every successful local login creates a 30-day local session.
- Optional biometric app unlock is implemented with `local_auth`.
- Secure logout clears the local session and biometric preference.
- **Safe cache cleanup** deletes API response cache and image files, while preserving media summaries used by user history. Detail freshness is invalidated instead of deleting ratings, comments, favorites, lists, watch states, watched episodes, or users.
- Fixed Android SQLite WAL initialization (`rawQuery`) and the asynchronous `setState` retry bug on Home.
- Blue/black dark branding and a generated Cine Track Simple logo are included.
