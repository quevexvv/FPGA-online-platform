from collections.abc import Sequence
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import Row
from sqlalchemy.orm import Session

from app.modules.labs.service import get_lab
from app.modules.submissions import repository
from app.modules.submissions.models import Submission
from app.modules.submissions.schemas import SubmissionCreate
from app.modules.users.models import User, UserRole


def submit(db: Session, user: User, lab_id: UUID, data: SubmissionCreate) -> Submission:
    if user.role != UserRole.student:
        raise HTTPException(status_code=403, detail="Only students can submit solutions")
    get_lab(db, lab_id)
    submission = repository.create(db, user.id, lab_id, data.source_code)
    db.commit()
    return submission


def list_submissions(
    db: Session, user_id: UUID, lab_id: UUID, limit: int, offset: int
) -> Sequence[Row]:
    return repository.list_owned(db, user_id, lab_id, limit, offset)


def get_submission(db: Session, user_id: UUID, submission_id: UUID) -> Submission:
    submission = repository.find_owned(db, user_id, submission_id)
    if submission is None:
        raise HTTPException(status_code=404, detail="Submission not found")
    return submission
