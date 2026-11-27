from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

from app.modules.runs.service import utc


class Interval(BaseModel):
    model_config = ConfigDict(extra="forbid")
    starts_at: AwareDatetime
    ends_at: AwareDatetime

    @model_validator(mode="after")
    def normalize(self):
        self.starts_at = utc(self.starts_at)
        self.ends_at = utc(self.ends_at)
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must follow starts_at")
        return self


class Policy(BaseModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)
    min_minutes: int = Field(default=5, ge=1, le=1440)
    max_minutes: int = Field(default=60, ge=1, le=1440)
    position: int = Field(default=0, ge=0)
    deadline: AwareDatetime | None = None

    @model_validator(mode="after")
    def validate_range(self):
        if self.max_minutes < self.min_minutes:
            raise ValueError("max_minutes must be at least min_minutes")
        return self


class Slot(Interval):
    mine: bool
    booking_id: UUID | None
    lab_id: UUID | None
    state: Literal["reserved", "active", "finished", "no_show", "cancelled"]


class Progress(BaseModel):
    lab_id: UUID
    title: str
    position: int
    deadline: datetime | None
    min_minutes: int
    max_minutes: int
    status: Literal["not_started", "in_progress", "passed"]
    blocked_reason: Literal["deadline", "previous_lab"] | None


class BookingCreate(Interval):
    lab_id: UUID
    slot_id: UUID | None = None


class FreeInterval(Interval):
    slot_id: UUID
    available: Literal[True] = True


class BoardStatus(BaseModel):
    state: Literal["free", "busy", "unavailable"]
    current_session: Slot | None
    session_ends_at: datetime | None
    released_at: datetime | None
    updated_at: datetime | None
    server_time: datetime
