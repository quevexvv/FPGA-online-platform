"""Persist a queue claim before dispatching a run."""

import sqlalchemy as sa
from alembic import op

revision = "0006_claim_fpga_run"
down_revision = "0005_add_group_and_runs"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("runs", sa.Column("queue_claimed_at", sa.DateTime(timezone=True), nullable=True))


def downgrade():
    op.drop_column("runs", "queue_claimed_at")
