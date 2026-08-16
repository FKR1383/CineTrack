#!/usr/bin/env python3
"""Pre-download optimized posters for the current home feed.

Uses server-side TMDB poster URLs only and never prints credentials.
"""
from __future__ import annotations

import argparse

from app.database import SessionLocal
from app.services.media import get_cached_media, home_sections
from app.services.posters import ensure_cached_poster


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=30)
    args = parser.parse_args()
    limit = max(0, min(args.limit, 100))

    ok = failed = 0
    with SessionLocal() as db:
        sections = home_sections(db, None)
        keys: list[str] = []
        seen: set[str] = set()
        for items in sections.values():
            for item in items:
                key = str(item.get("media_id") or "")
                if key and key not in seen:
                    seen.add(key)
                    keys.append(key)
        for key in keys[:limit]:
            media = get_cached_media(db, key)
            if media is None or not media.poster_url:
                continue
            try:
                path = ensure_cached_poster(media)
                ok += 1
                print(f"poster cached: {key} -> {path.name}")
            except Exception as exc:  # acceptance utility: continue through individual CDN failures
                failed += 1
                print(f"poster failed: {key}: {exc}")
    print(f"Poster prewarm complete: cached={ok}, failed={failed}, requested_limit={limit}")
    return 0 if ok or limit == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
