from datetime import datetime, timezone
from typing import Annotated
from uuid import UUID

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    SecretStr,
    field_validator,
)

from app.modules.users.models import UserRole


def normalize_group(value: str | None) -> str | None:
    if value is None:
        return None
    value = value.strip()
    if any(not char.isprintable() for char in value):
        raise ValueError("Group must not contain control characters")
    return value or None


StudentGroup = Annotated[
    str | None, Field(max_length=32, strict=True), AfterValidator(normalize_group)
]


class GroupUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    group: StudentGroup


class Credentials(BaseModel):
    model_config = ConfigDict(extra="forbid")

    email: EmailStr = Field(max_length=254)
    password: SecretStr = Field(min_length=1, max_length=128)

    @field_validator("email", mode="before")
    @classmethod
    def normalize_email(cls, value):
        return value.strip().lower() if isinstance(value, str) else value


class Registration(Credentials):
    full_name: str = Field(min_length=1, max_length=200)
    group: StudentGroup = None
    password: SecretStr = Field(min_length=12, max_length=128)

    @field_validator("full_name", mode="before")
    @classmethod
    def strip_name(cls, value):
        return value.strip() if isinstance(value, str) else value


class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    full_name: str
    group: str | None
    role: UserRole
    is_active: bool
    created_at: datetime

    @field_validator("created_at")
    @classmethod
    def ensure_timezone(cls, value):
        return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


class LoginResult(BaseModel):
    user: UserPublic
    csrf_token: str


class CsrfResult(BaseModel):
    csrf_token: str
