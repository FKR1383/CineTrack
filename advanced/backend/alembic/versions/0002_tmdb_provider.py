"""Add generic provider/TMDB identity fields while preserving user data.

Revision ID: 0002
Revises: 0001
"""
from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def _columns(table: str) -> set[str]:
    inspector = sa.inspect(op.get_bind())
    return {col["name"] for col in inspector.get_columns(table)}


def _indexes(table: str) -> set[str]:
    inspector = sa.inspect(op.get_bind())
    return {idx["name"] for idx in inspector.get_indexes(table) if idx.get("name")}


def upgrade() -> None:
    media_cols = _columns("media")
    with op.batch_alter_table("media") as batch:
        batch.alter_column("imdb_id", existing_type=sa.String(length=20), type_=sa.String(length=64))
        if "provider" not in media_cols:
            batch.add_column(sa.Column("provider", sa.String(length=20), nullable=True))
        if "provider_id" not in media_cols:
            batch.add_column(sa.Column("provider_id", sa.String(length=40), nullable=True))
        if "tmdb_id" not in media_cols:
            batch.add_column(sa.Column("tmdb_id", sa.Integer(), nullable=True))
        if "external_imdb_id" not in media_cols:
            batch.add_column(sa.Column("external_imdb_id", sa.String(length=20), nullable=True))

    # Existing records came from the old IMDb/demo build. Keep them intact but
    # label them legacy so TMDB records can coexist without breaking user lists.
    op.execute("UPDATE media SET provider='legacy' WHERE provider IS NULL")
    op.execute("UPDATE media SET provider_id=imdb_id WHERE provider_id IS NULL")
    with op.batch_alter_table("media") as batch:
        batch.alter_column("provider", existing_type=sa.String(length=20), nullable=False, server_default="tmdb")

    media_indexes = _indexes("media")
    if "ix_media_provider" not in media_indexes:
        op.create_index("ix_media_provider", "media", ["provider"], unique=False)
    if "ix_media_provider_id" not in media_indexes:
        op.create_index("ix_media_provider_id", "media", ["provider_id"], unique=False)
    if "ix_media_tmdb_id" not in media_indexes:
        op.create_index("ix_media_tmdb_id", "media", ["tmdb_id"], unique=False)
    if "ix_media_external_imdb_id" not in media_indexes:
        op.create_index("ix_media_external_imdb_id", "media", ["external_imdb_id"], unique=False)
    try:
        op.create_unique_constraint(
            "uq_media_provider_type_id", "media", ["provider", "media_type", "provider_id"]
        )
    except Exception:
        # SQLite batch mode/test fixtures can surface this differently; the
        # unique media_key remains authoritative regardless.
        pass

    episode_cols = _columns("episodes")
    with op.batch_alter_table("episodes") as batch:
        batch.alter_column("imdb_id", existing_type=sa.String(length=20), type_=sa.String(length=64))
        if "provider" not in episode_cols:
            batch.add_column(sa.Column("provider", sa.String(length=20), nullable=True))
        if "provider_id" not in episode_cols:
            batch.add_column(sa.Column("provider_id", sa.String(length=40), nullable=True))
        if "tmdb_id" not in episode_cols:
            batch.add_column(sa.Column("tmdb_id", sa.Integer(), nullable=True))
        if "external_imdb_id" not in episode_cols:
            batch.add_column(sa.Column("external_imdb_id", sa.String(length=20), nullable=True))
    op.execute("UPDATE episodes SET provider='legacy' WHERE provider IS NULL")
    op.execute("UPDATE episodes SET provider_id=imdb_id WHERE provider_id IS NULL")
    with op.batch_alter_table("episodes") as batch:
        batch.alter_column("provider", existing_type=sa.String(length=20), nullable=False, server_default="tmdb")

    episode_indexes = _indexes("episodes")
    if "ix_episodes_provider" not in episode_indexes:
        op.create_index("ix_episodes_provider", "episodes", ["provider"], unique=False)
    if "ix_episodes_provider_id" not in episode_indexes:
        op.create_index("ix_episodes_provider_id", "episodes", ["provider_id"], unique=False)
    if "ix_episodes_tmdb_id" not in episode_indexes:
        op.create_index("ix_episodes_tmdb_id", "episodes", ["tmdb_id"], unique=False)
    if "ix_episodes_external_imdb_id" not in episode_indexes:
        op.create_index("ix_episodes_external_imdb_id", "episodes", ["external_imdb_id"], unique=False)


def downgrade() -> None:
    for name in [
        "ix_episodes_external_imdb_id",
        "ix_episodes_tmdb_id",
        "ix_episodes_provider_id",
        "ix_episodes_provider",
    ]:
        try:
            op.drop_index(name, table_name="episodes")
        except Exception:
            pass
    with op.batch_alter_table("episodes") as batch:
        for column in ["external_imdb_id", "tmdb_id", "provider_id", "provider"]:
            try:
                batch.drop_column(column)
            except Exception:
                pass
        batch.alter_column("imdb_id", existing_type=sa.String(length=64), type_=sa.String(length=20))

    try:
        op.drop_constraint("uq_media_provider_type_id", "media", type_="unique")
    except Exception:
        pass
    for name in [
        "ix_media_external_imdb_id",
        "ix_media_tmdb_id",
        "ix_media_provider_id",
        "ix_media_provider",
    ]:
        try:
            op.drop_index(name, table_name="media")
        except Exception:
            pass
    with op.batch_alter_table("media") as batch:
        for column in ["external_imdb_id", "tmdb_id", "provider_id", "provider"]:
            try:
                batch.drop_column(column)
            except Exception:
                pass
        batch.alter_column("imdb_id", existing_type=sa.String(length=64), type_=sa.String(length=20))
