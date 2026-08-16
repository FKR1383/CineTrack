# Final fixes – Cine Track Advanced

- Login sessions are issued for 30 days after every successful login.
- Optional biometric app unlock is implemented with `local_auth`. A valid 30-day server session remains required; biometric authentication only unlocks that remembered session on the device.
- Secure logout revokes the refresh token, clears local tokens, and disables biometric unlock for the logged-out session.
- Admin **cache clear** no longer deletes the `Media` database row. It only invalidates provider freshness, removes derived poster files, and expires the home cache. Ratings, comments, favorites, custom lists, watch status, watched episodes, and activity remain intact.
- Blue/black dark branding and a generated Cine Track logo are included.
