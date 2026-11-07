from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response
from fastapi.responses import PlainTextResponse
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.router import get_current_user, require_csrf
from app.modules.submissions import service
from app.modules.submissions.schemas import SubmissionCreate, SubmissionDetail, SubmissionSummary
from app.modules.users.models import User

router = APIRouter(
    tags=["Submissions"],
    responses={401: {"description": "Valid login session required"}},
)
Db = Annotated[Session, Depends(get_db)]
CurrentUser = Annotated[User, Depends(get_current_user)]


@router.post(
    "/labs/{lab_id}/submissions",
    response_model=SubmissionSummary,
    status_code=201,
    dependencies=[Depends(require_csrf)],
    responses={
        403: {"description": "Student role, allowed Origin and valid CSRF token required"},
        404: {"description": "Laboratory missing or unpublished"},
    },
)
def submit(lab_id: UUID, data: SubmissionCreate, user: CurrentUser, db: Db, response: Response):
    submission = service.submit(db, user, lab_id, data)
    response.headers["Location"] = f"/submissions/{submission.id}"
    return submission


@router.get("/labs/{lab_id}/submissions", response_model=list[SubmissionSummary])
def list_submissions(
    lab_id: UUID,
    user: CurrentUser,
    db: Db,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    return service.list_submissions(db, user.id, lab_id, limit, offset)


@router.get(
    "/submissions/{submission_id}",
    response_model=SubmissionDetail,
    responses={404: {"description": "Submission missing or owned by another user"}},
)
def get_submission(submission_id: UUID, user: CurrentUser, db: Db):
    return service.get_submission(db, user.id, submission_id)


@router.get(
    "/submissions/{submission_id}/source",
    response_class=PlainTextResponse,
    responses={404: {"description": "Submission missing or owned by another user"}},
)
def download_source(submission_id: UUID, user: CurrentUser, db: Db):
    submission = service.get_submission(db, user.id, submission_id)
    return PlainTextResponse(
        submission.source_code,
        headers={
            "Content-Disposition": f'attachment; filename="submission-{submission.id}.v"',
            "X-Content-Type-Options": "nosniff",
        },
    )
