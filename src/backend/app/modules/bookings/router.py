from datetime import date
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.modules.auth.router import get_current_user, require_csrf
from app.modules.bookings import board, service
from app.modules.bookings.models import Booking
from app.modules.bookings.schemas import (
    BoardStatus,
    BookingCreate,
    FreeInterval,
    Interval,
    Policy,
    Progress,
    Slot,
)
from app.modules.users.models import User, UserRole


def private(response: Response):
    response.headers["Cache-Control"] = "no-store"


router = APIRouter(tags=["Bookings"], dependencies=[Depends(private)])
Db = Annotated[Session, Depends(get_db)]
Current = Annotated[User, Depends(get_current_user)]
write = [Depends(require_csrf)]


@router.get("/bookings", response_model=list[Slot])
def schedule(window: Annotated[Interval, Query()], user: Current, db: Db):
    return service.schedule(db, user.id, window)


@router.post("/labs/{lab_id}/bookings", status_code=201, response_model=Slot, dependencies=write)
def reserve(lab_id: UUID, data: Interval, user: Current, db: Db):
    if user.role != UserRole.student:
        raise HTTPException(403, "Student role required")
    return service.reserve(db, user.id, lab_id, data)


@router.post("/bookings/{booking_id}/check-in", response_model=Slot, dependencies=write)
def check_in(booking_id: UUID, user: Current, db: Db):
    return service.change(db, user.id, booking_id, cancel=False)


@router.delete("/bookings/{booking_id}", response_model=Slot, dependencies=write)
def cancel(booking_id: UUID, user: Current, db: Db):
    return service.change(db, user.id, booking_id, cancel=True)


@router.put("/labs/{lab_id}/policy", response_model=Policy, dependencies=write)
def configure(lab_id: UUID, data: Policy, user: Current, db: Db):
    if user.role != UserRole.teacher:
        raise HTTPException(403, "Teacher role required")
    return service.set_policy(db, lab_id, data)


@router.get("/me/labs", response_model=list[Progress])
def progress(user: Current, db: Db):
    return service.progress(db, user.id, service.now_utc())


@router.get("/bookings/slots", response_model=list[FreeInterval])
def slots(
    day: Annotated[date, Query(alias="date")], user: Current, db: Db, lab_id: UUID | None = None
):
    return service.free_intervals(db, day, service.now_utc(), lab_id, user.id)


@router.get("/bookings/me", response_model=list[Slot])
def my_bookings(
    user: Current,
    db: Db,
    limit: Annotated[int, Query(ge=1, le=100)] = 20,
    offset: Annotated[int, Query(ge=0)] = 0,
):
    now = service.now_utc()
    rows = db.scalars(
        select(Booking)
        .where(Booking.user_id == user.id)
        .order_by(Booking.starts_at.desc(), Booking.id.desc())
        .offset(offset)
        .limit(limit)
    )
    return [service.slot(row, user.id, now) for row in rows]


@router.post("/bookings", status_code=201, response_model=Slot, dependencies=write)
def create(data: BookingCreate, user: Current, db: Db):
    if user.role != UserRole.student:
        raise HTTPException(403, "Student role required")
    return service.reserve(db, user.id, data.lab_id, data, data.slot_id)


@router.get("/board/status", response_model=BoardStatus)
def board_status(user: Current, db: Db):
    return board.status(db, user.id)
