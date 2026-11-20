from collections.abc import Sequence
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.labs.models import Lab


def list_published(db: Session, limit: int, offset: int) -> Sequence[Lab]:
    return db.scalars(
        select(Lab)
        .where(Lab.is_published.is_(True))
        .order_by(Lab.title, Lab.id)
        .limit(limit)
        .offset(offset)
    ).all()


def find_published(db: Session, lab_id: UUID) -> Lab | None:
    return db.scalar(select(Lab).where(Lab.id == lab_id, Lab.is_published.is_(True)))
