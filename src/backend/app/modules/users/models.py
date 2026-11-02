from datetime import datetime
from enum import StrEnum
from uuid import UUID, uuid4

from sqlalchemy import Boolean, CheckConstraint, DateTime, Index, String, Uuid, func, text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class UserRole(StrEnum):
    student = "student"
    teacher = "teacher"


class User(Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint("role IN ('student', 'teacher')", name="role_allowed"),
        CheckConstraint("length(trim(full_name)) > 0", name="full_name_not_blank"),
        CheckConstraint("length(trim(email)) > 0", name="email_not_blank"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    email: Mapped[str] = mapped_column(String(254), nullable=False)
    full_name: Mapped[str] = mapped_column(String(200), nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    role: Mapped[str] = mapped_column(
        String(20), nullable=False, default=UserRole.student.value, server_default="student"
    )
    is_active: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default=text("true")
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )


Index("uq_users_email_lower", func.lower(User.email), unique=True)
