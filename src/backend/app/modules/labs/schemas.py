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


class LabDetail(LabSummary):
    statement: str
    template: str
    interface_description: str
