from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.modules.labs.models import LabKind


class LabSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    description: str
    kind: LabKind
    is_demo: bool
    deadline: datetime | None = None
    status: Literal["not_started", "in_progress", "passed"] = "not_started"
    is_locked: bool = False
    blocked_reason: Literal["deadline", "previous_lab"] | None = None
    position: int = 0


class LabDetail(LabSummary):
    statement: str
    template: str
    interface_description: str
