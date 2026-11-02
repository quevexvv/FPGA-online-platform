"""Store student source submissions and preserve their ownership."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004_create_submissions"
down_revision: str | None = "0003_create_labs"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "submissions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("lab_id", sa.Uuid(), nullable=False),
        sa.Column("source_code", sa.Text(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_submissions")),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            ondelete="RESTRICT",
            name=op.f("fk_submissions_user_id_users"),
        ),
        sa.ForeignKeyConstraint(
            ["lab_id"],
            ["labs.id"],
            ondelete="RESTRICT",
            name=op.f("fk_submissions_lab_id_labs"),
        ),
        sa.CheckConstraint(
            "length(trim(source_code)) > 0", name=op.f("ck_submissions_source_code_not_blank")
        ),
    )
    op.create_index(
        "ix_submissions_user_lab_created_id",
        "submissions",
        ["user_id", "lab_id", "created_at", "id"],
    )
    op.create_index("ix_submissions_lab_id", "submissions", ["lab_id"])


def downgrade() -> None:
    op.drop_index("ix_submissions_lab_id", table_name="submissions")
    op.drop_index("ix_submissions_user_lab_created_id", table_name="submissions")
    op.drop_table("submissions")
