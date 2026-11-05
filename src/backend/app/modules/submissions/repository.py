from collections.abc import Sequence
from uuid import UUID

from sqlalchemy import Row, select
from sqlalchemy.orm import Session

from app.modules.submissions.models import Submission


def create(db: Session, user_id: UUID, lab_id: UUID, source_code: str) -> Submission:
    submission = Submission(user_id=user_id, lab_id=lab_id, source_code=source_code)
    db.add(submission)
    db.flush()
    return submission


def list_owned(db: Session, user_id: UUID, lab_id: UUID, limit: int, offset: int) -> Sequence[Row]:
    return db.execute(
        select(Submission.id, Submission.lab_id, Submission.created_at)
        .where(Submission.user_id == user_id, Submission.lab_id == lab_id)
        .order_by(Submission.created_at.desc(), Submission.id.desc())
        .limit(limit)
        .offset(offset)
    ).all()


def find_owned(db: Session, user_id: UUID, submission_id: UUID) -> Submission | None:
    return db.scalar(
        select(Submission).where(Submission.id == submission_id, Submission.user_id == user_id)
    )
