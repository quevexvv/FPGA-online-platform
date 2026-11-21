from collections.abc import Sequence
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import Row, select
from sqlalchemy.orm import Session

from app.modules.labs.models import Lab
from app.modules.labs.service import get_lab
from app.modules.runs.models import Run
from app.modules.runs.service import enqueue, public_run
from app.modules.submissions import repository
from app.modules.submissions.models import Submission
from app.modules.submissions.schemas import SubmissionCreate, SubmissionHistoryItem
from app.modules.users.models import User, UserRole


def submit(db: Session, user: User, lab_id: UUID, data: SubmissionCreate) -> Submission:
    if user.role != UserRole.student:
        raise HTTPException(status_code=403, detail="Only students can submit solutions")
    get_lab(db, lab_id)
    submission = repository.create(db, user.id, lab_id, data.source_code)
    enqueue(db, submission.id)
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


def history(db: Session, user_id: UUID, limit: int, offset: int) -> list[SubmissionHistoryItem]:
    latest = (
        select(Run.id)
        .where(Run.submission_id == Submission.id)
        .order_by(Run.created_at.desc(), Run.id.desc())
        .limit(1)
        .correlate(Submission)
        .scalar_subquery()
    )
    rows = db.execute(
        select(Submission.id, Submission.lab_id, Submission.created_at, Lab.title, Run)
        .join(Lab, Lab.id == Submission.lab_id)
        .outerjoin(Run, Run.id == latest)
        .where(Submission.user_id == user_id)
        .order_by(Submission.created_at.desc(), Submission.id.desc())
        .limit(limit)
        .offset(offset)
    )
    items = []
    for submission_id, lab_id, created_at, title, run in rows:
        status = public_run(submission_id, run)
        items.append(
            SubmissionHistoryItem(
                id=submission_id,
                lab_id=lab_id,
                lab_title=title,
                created_at=created_at,
                run_state=status.state,
                result_status=status.result_status,
                elapsed_seconds=status.elapsed_seconds,
                open_passed=sum(test.match for test in status.tests) if status.summary else None,
                open_total=len(status.tests) if status.summary else None,
                total_passed=status.summary.passed if status.summary else None,
                total_tests=status.summary.planned if status.summary else None,
            )
        )
    return items
