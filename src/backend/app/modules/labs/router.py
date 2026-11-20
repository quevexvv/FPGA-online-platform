from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.router import get_current_user
from app.modules.labs import service
from app.modules.labs.schemas import LabDetail, LabSummary


def prevent_caching(response: Response) -> None:
    response.headers["Cache-Control"] = "no-store"


router = APIRouter(
    prefix="/labs",
    tags=["Laboratories"],
    dependencies=[Depends(get_current_user), Depends(prevent_caching)],
    responses={401: {"description": "Valid login session required"}},
)
Db = Annotated[Session, Depends(get_db)]


@router.get("", response_model=list[LabSummary])
def list_labs(
    db: Db,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    return service.list_labs(db, limit, offset)


@router.get(
    "/{lab_id}",
    response_model=LabDetail,
    responses={404: {"description": "Laboratory missing or unpublished"}},
)
def get_lab(lab_id: UUID, db: Db):
    return service.get_lab(db, lab_id)
