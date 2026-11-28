"""Booking calendar for the single board and laboratory policies."""

import sqlalchemy as sa
from alembic import op

revision = "0007_bookings"
down_revision = "0006_claim_fpga_run"
branch_labels = None
depends_on = None


def upgrade():
    board = op.create_table(
        "booking_board", sa.Column("id", sa.Integer, primary_key=True, autoincrement=False)
    )
    op.bulk_insert(board, [{"id": 1}])
    op.create_table(
        "lab_policies",
        sa.Column("lab_id", sa.Uuid, sa.ForeignKey("labs.id"), primary_key=True),
        sa.Column("min_minutes", sa.Integer, nullable=False),
        sa.Column("max_minutes", sa.Integer, nullable=False),
        sa.Column("position", sa.Integer, nullable=False),
        sa.Column("deadline", sa.DateTime(timezone=True)),
        sa.CheckConstraint(
            "min_minutes >= 1 AND max_minutes >= min_minutes", name="duration_range"
        ),
        sa.CheckConstraint("position >= 0", name="positive_position"),
    )
    op.create_table(
        "bookings",
        sa.Column("id", sa.Uuid, primary_key=True),
        sa.Column("board_id", sa.Integer, sa.ForeignKey("booking_board.id"), nullable=False),
        sa.Column("lab_id", sa.Uuid, sa.ForeignKey("labs.id"), nullable=False),
        sa.Column("user_id", sa.Uuid, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("checked_in_at", sa.DateTime(timezone=True)),
        sa.Column("cancelled_at", sa.DateTime(timezone=True)),
        sa.Column("min_minutes", sa.Integer, nullable=False),
        sa.Column("max_minutes", sa.Integer, nullable=False),
        sa.CheckConstraint("starts_at < ends_at", name="positive_interval"),
    )
    op.create_index("ix_bookings_board_interval", "bookings", ["board_id", "starts_at", "ends_at"])
    op.create_index("ix_bookings_owner_end", "bookings", ["user_id", "ends_at"])
    op.create_table(
        "run_bookings",
        sa.Column("run_id", sa.Uuid, sa.ForeignKey("runs.id"), primary_key=True),
        sa.Column("booking_id", sa.Uuid, sa.ForeignKey("bookings.id"), nullable=False),
    )
    op.add_column("runs", sa.Column("withdrawn_at", sa.DateTime(timezone=True)))


def downgrade():
    op.drop_column("runs", "withdrawn_at")
    for table in ("run_bookings", "bookings", "lab_policies", "booking_board"):
        op.drop_table(table)
