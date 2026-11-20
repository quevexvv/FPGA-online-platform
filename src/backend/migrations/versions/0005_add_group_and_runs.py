"""Store study groups and executor snapshots."""

import sqlalchemy as sa
from alembic import op

revision = "0005_add_group_and_runs"
down_revision = "0004_create_submissions"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("student_group", sa.String(32), nullable=True))
    op.create_table(
        "runs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("submission_id", sa.Uuid(), nullable=False),
        sa.Column("mode", sa.String(16), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("public_vector_indices", sa.JSON(), nullable=False),
        sa.Column("status_snapshot", sa.JSON(), nullable=True),
        sa.Column("result_snapshot", sa.JSON(), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_runs")),
        sa.ForeignKeyConstraint(
            ["submission_id"],
            ["submissions.id"],
            ondelete="RESTRICT",
            name=op.f("fk_runs_submission_id_submissions"),
        ),
        sa.CheckConstraint("mode IN ('hardware', 'mock')", name=op.f("ck_runs_mode_allowed")),
    )
    op.create_index("ix_runs_submission_created_id", "runs", ["submission_id", "created_at", "id"])


def downgrade():
    op.drop_index("ix_runs_submission_created_id", table_name="runs")
    op.drop_table("runs")
    op.drop_column("users", "student_group")
