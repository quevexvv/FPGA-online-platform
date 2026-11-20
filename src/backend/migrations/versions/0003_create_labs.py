"""Add the published laboratory catalogue, without demo data."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003_create_labs"
down_revision: str | None = "0002_create_auth_sessions"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "labs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("statement", sa.Text(), nullable=False),
        sa.Column("template", sa.Text(), nullable=False),
        sa.Column("interface_description", sa.Text(), nullable=False),
        sa.Column("kind", sa.String(20), nullable=False),
        sa.Column("is_published", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_demo", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.CheckConstraint(
            "kind IN ('combinational', 'sequential')", name=op.f("ck_labs_kind_allowed")
        ),
        sa.CheckConstraint("length(trim(title)) > 0", name=op.f("ck_labs_title_not_blank")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_labs")),
    )


def downgrade() -> None:
    op.drop_table("labs")
