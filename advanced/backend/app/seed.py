from __future__ import annotations

from app.database import SessionLocal, create_all
from app.services.auth import ensure_admin_user
from app.services.media import seed_provider_catalog
from app.services.providers.base import MediaProviderError


def main() -> None:
    create_all()
    with SessionLocal() as db:
        admin = ensure_admin_user(db)
        added = 0
        try:
            added = seed_provider_catalog(db)
        except MediaProviderError as exc:
            # Authentication and all user-local features must remain available
            # during a temporary TMDB outage. Home/search will expose a clear
            # provider error when there is no cached media yet.
            print(f"TMDB seed skipped: {exc}")
        print(f"Admin: {admin.email}; TMDB media records added: {added}")


if __name__ == "__main__":
    main()
