from datetime import datetime, timezone
from uuid import UUID, uuid4

from sqlalchemy import JSON, CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Uuid
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Run(Base):
    __tablename__ = "runs"
    __table_args__ = (
        CheckConstraint("mode IN ('hardware', 'mock')", name="mode_allowed"),
        Index("ix_runs_submission_created_id", "submission_id", "created_at", "id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    submission_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("submissions.id", ondelete="RESTRICT"), nullable=False
    )
    mode: Mapped[str] = mapped_column(String(16), nullable=False, default="hardware")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc)
    )
    public_vector_indices: Mapped[list] = mapped_column(JSON, nullable=False, default=list)
    status_snapshot: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    result_snapshot: Mapped[dict | None] = mapped_column(JSON, nullable=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)

    __mapper_args__ = {"version_id_col": version}
