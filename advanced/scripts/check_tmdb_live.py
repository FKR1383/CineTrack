#!/usr/bin/env python3
"""Fail-fast acceptance check for a real TMDB connection.

Run with the same environment file as the backend. It never prints credentials.
"""
from __future__ import annotations

import sys

from app.config import get_settings
from app.services.providers.factory import get_media_provider


def main() -> int:
    query = " ".join(sys.argv[1:]).strip() or "Interstellar"
    settings = get_settings()
    if not settings.tmdb_configured:
        print("ERROR: TMDB credentials are not configured.", file=sys.stderr)
        return 2
    provider = get_media_provider()
    result = provider.search(
        query=query,
        media_type=None,
        actor=None,
        director=None,
        genre=None,
        year=None,
        page=1,
        page_size=5,
    )
    if not result.items:
        print(f"ERROR: TMDB returned no results for {query!r}.", file=sys.stderr)
        return 3
    first = result.items[0]
    print(
        "TMDB LIVE OK:",
        first.get("title"),
        f"media_id={first.get('media_key')}",
        f"tmdb_id={first.get('tmdb_id')}",
        f"poster={'yes' if first.get('poster_source_url') else 'no'}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
