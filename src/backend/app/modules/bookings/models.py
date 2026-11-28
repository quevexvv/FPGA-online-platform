from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import CheckConstraint, DateTime, ForeignKey, Index, Integer, false
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base


class Board(Base):
    __tablename__ = "booking_board"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=False)
    observation: Mapped[str | None]
    observed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    released_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    release_pending: Mapped[bool] = mapped_column(server_default=false())


class LabPolicy(Base):
    __tablename__ = "lab_policies"
    __table_args__ = (
        CheckConstraint("min_minutes >= 1 AND max_minutes >= min_minutes", name="duration_range"),
        CheckConstraint("position >= 0", name="positive_position"),
    )
    lab_id: Mapped[UUID] = mapped_column(ForeignKey("labs.id"), primary_key=True)
    min_minutes: Mapped[int] = mapped_column(default=5)
    max_minutes: Mapped[int] = mapped_column(default=60)
    position: Mapped[int] = mapped_column(default=0)
    deadline: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Booking(Base):
    __tablename__ = "bookings"
    __table_args__ = (
        CheckConstraint("starts_at < ends_at", name="positive_interval"),
        Index("ix_bookings_board_interval", "board_id", "starts_at", "ends_at"),
        Index("ix_bookings_owner_end", "user_id", "ends_at"),
    )
    id: Mapped[UUID] = mapped_column(primary_key=True, default=uuid4)
    board_id: Mapped[int] = mapped_column(ForeignKey("booking_board.id"), default=1)
    lab_id: Mapped[UUID] = mapped_column(ForeignKey("labs.id"))
    user_id: Mapped[UUID] = mapped_column(ForeignKey("users.id"))
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    checked_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    min_minutes: Mapped[int]
    max_minutes: Mapped[int]


class RunBooking(Base):
    __tablename__ = "run_bookings"
    run_id: Mapped[UUID] = mapped_column(ForeignKey("runs.id"), primary_key=True)
    booking_id: Mapped[UUID] = mapped_column(ForeignKey("bookings.id"))
