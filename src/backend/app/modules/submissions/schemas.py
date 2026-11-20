from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

MAX_SOURCE_BYTES = 64 * 1024


class SubmissionCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    source_code: Annotated[str, Field(strict=True, min_length=1, max_length=MAX_SOURCE_BYTES)]

    @field_validator("source_code")
    @classmethod
    def validate_source(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("Source code must not be blank")
        if "\x00" in value:
            raise ValueError("Source code must not contain null characters")
        try:
            encoded = value.encode("utf-8")
        except UnicodeEncodeError:
            raise ValueError("Source code must be valid UTF-8 text") from None
        if len(encoded) > MAX_SOURCE_BYTES:
            raise ValueError(f"Source code must not exceed {MAX_SOURCE_BYTES} UTF-8 bytes")
        return value


class SubmissionSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    lab_id: UUID
    created_at: datetime

    @field_validator("created_at")
    @classmethod
    def normalize_created_at(cls, value: datetime) -> datetime:
        if value.tzinfo is None:
            return value.replace(tzinfo=timezone.utc)
        return value.astimezone(timezone.utc)


class SubmissionDetail(SubmissionSummary):
    source_code: str
