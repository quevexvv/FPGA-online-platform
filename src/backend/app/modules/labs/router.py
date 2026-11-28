from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.router import get_current_user
from app.modules.bookings.service import now_utc, progress
from app.modules.labs import service
from app.modules.labs.schemas import LabDetail, LabSummary
from app.modules.users.models import User


def prevent_caching(response: Response) -> None:
    response.headers["Cache-Control"] = "no-store"


router = APIRouter(
    prefix="/labs",
    tags=["Laboratories"],
    dependencies=[Depends(get_current_user), Depends(prevent_caching)],
    responses={401: {"description": "Valid login session required"}},
)
Current = Annotated[User, Depends(get_current_user)]


def with_progress(model, lab, entry):
    return model.model_validate(lab).model_copy(
        update={
            "deadline": entry.deadline,
            "status": entry.status,
            "position": entry.position,
            "blocked_reason": entry.blocked_reason,
            "is_locked": entry.blocked_reason is not None,
        }
    )


Db = Annotated[Session, Depends(get_db)]


@router.get("", response_model=list[LabSummary])
def list_labs(
    db: Db,
    user: Current,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    entries = {row.lab_id: row for row in progress(db, user.id, now_utc())}
    return [
        with_progress(LabSummary, lab, entries[lab.id])
        for lab in service.list_labs(db, limit, offset)
        if lab.id in entries
    ]


@router.get(
    "/{lab_id}",
    response_model=LabDetail,
    responses={404: {"description": "Laboratory missing or unpublished"}},
)
def get_lab(lab_id: UUID, db: Db, user: Current):
    lab = service.get_lab(db, lab_id)
    entry = next(row for row in progress(db, user.id, now_utc()) if row.lab_id == lab_id)
    return with_progress(LabDetail, lab, entry)
