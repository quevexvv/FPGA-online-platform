from collections.abc import Sequence
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.modules.labs import repository
from app.modules.labs.models import Lab


def list_labs(db: Session, limit: int, offset: int) -> Sequence[Lab]:
    return repository.list_published(db, limit, offset)


def get_lab(db: Session, lab_id: UUID) -> Lab:
    lab = repository.find_published(db, lab_id)
    if lab is None:
        raise HTTPException(status_code=404, detail="Laboratory not found")
    return lab
