"""Stand observations and student-visible build and programming logs."""

import sqlalchemy as sa
from alembic import op

revision = "0008_board_and_logs"
down_revision = "0007_bookings"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("booking_board", sa.Column("observation", sa.String()))
    op.add_column("booking_board", sa.Column("observed_at", sa.DateTime(timezone=True)))
    op.add_column("booking_board", sa.Column("released_at", sa.DateTime(timezone=True)))
    op.add_column(
        "booking_board",
        sa.Column("release_pending", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.add_column("runs", sa.Column("public_logs", sa.JSON()))


def downgrade():
    op.drop_column("runs", "public_logs")
    for name in ("release_pending", "released_at", "observed_at", "observation"):
        op.drop_column("booking_board", name)
