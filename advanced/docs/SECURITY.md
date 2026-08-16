# Security

## Transport

Production traffic is HTTPS through Nginx. The deployment generates a private CA and IP-SAN server certificate. Flutter pins the server certificate SHA-256 fingerprint.

## Passwords and sessions

- Argon2 password hashes; plaintext passwords are never stored.
- short-lived JWT access tokens.
- rotating refresh tokens persisted server-side and revocable on logout.
- 1-day or 30-day refresh lifetime depending on `remember_me`.
- one-time hashed password-reset tokens.

## Authorization

Guest, authenticated user and administrator paths are separated. Admin endpoints require admin role; ordinary users cannot mutate another user's private data.

## TMDB credentials

`TMDB_READ_ACCESS_TOKEN` / `TMDB_API_KEY` exist only in server environment files. They are never returned by provider-status, OpenAPI, logs or Flutter.

## Input protection

Pydantic validates email, passwords, rating range, non-empty comments, identifiers and pagination. SQLAlchemy uses bound parameters. Uploads validate type/size and are decoded/re-encoded server-side.

## Poster proxy SSRF protection

The poster proxy accepts HTTPS URLs only when the hostname matches the configured TMDB image origin. It limits response size, requires image content, decodes with Pillow and re-encodes to WebP.

## Rate limits and idempotency

Global request rate limiting and idempotency records reduce abuse and accidental duplicate mutations.

## Secrets in the release archive

The final archive must not contain `.env`, TLS private keys, Android signing keys, or real TMDB credentials. Generate/configure those on the target machine.
