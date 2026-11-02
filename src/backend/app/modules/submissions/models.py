from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Text, Uuid, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Submission(Base):
    __tablename__ = "submissions"
    __table_args__ = (
        CheckConstraint("length(trim(source_code)) > 0", name="source_code_not_blank"),
        Index("ix_submissions_user_lab_created_id", "user_id", "lab_id", "created_at", "id"),
        Index("ix_submissions_lab_id", "lab_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    lab_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("labs.id", ondelete="RESTRICT"), nullable=False
    )
    source_code: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
