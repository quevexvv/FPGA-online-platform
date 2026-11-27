from datetime import datetime, time, timedelta, timezone
from uuid import NAMESPACE_URL, UUID, uuid5
from zoneinfo import ZoneInfo

from fastapi import HTTPException
from sqlalchemy import or_, select, update
from sqlalchemy.orm import Session

from app.modules.bookings.models import Board, Booking, LabPolicy
from app.modules.bookings.schemas import FreeInterval, Interval, Policy, Progress, Slot
from app.modules.labs.models import Lab
from app.modules.labs.service import get_lab
from app.modules.runs.models import Run
from app.modules.runs.service import utc
from app.modules.submissions.models import Submission

GRACE = timedelta(minutes=15)


def now_utc():
    return datetime.now(timezone.utc)


def lock_board(db: Session):
    # Serializes overlap checks across processes on both SQLite and PostgreSQL.
    db.execute(update(Board).where(Board.id == 1).values(id=1))


def progress(db: Session, user_id: UUID, now: datetime) -> list[Progress]:
    attempted = set(
        db.scalars(select(Submission.lab_id).where(Submission.user_id == user_id).distinct())
    )
    passed = set(
        db.scalars(
            select(Submission.lab_id)
            .join(Run, Run.submission_id == Submission.id)
            .where(
                Submission.user_id == user_id,
                Run.mode == "hardware",
                Run.result_snapshot["status"].as_string() == "passed",
                Run.result_snapshot["hardware_verified"].as_boolean().is_(True),
            )
            .distinct()
        )
    )
    rows = db.execute(
        select(Lab, LabPolicy)
        .outerjoin(LabPolicy, LabPolicy.lab_id == Lab.id)
        .where(Lab.is_published.is_(True))
    ).all()
    first_unpassed = min(
        (
            rule.position
            for lab, rule in rows
            if rule and rule.position > 0 and lab.id not in passed
        ),
        default=None,
    )
    result = []
    for lab, rule in rows:
        pos = rule.position if rule else 0
        deadline = utc(rule.deadline) if rule and rule.deadline else None
        reason = None
        if deadline and now >= deadline:
            reason = "deadline"
        elif first_unpassed is not None and pos > first_unpassed:
            reason = "previous_lab"
        result.append(
            Progress(
                lab_id=lab.id,
                title=lab.title,
                position=pos,
                deadline=deadline,
                min_minutes=rule.min_minutes if rule else 5,
                max_minutes=rule.max_minutes if rule else 60,
                status="passed"
                if lab.id in passed
                else "in_progress"
                if lab.id in attempted
                else "not_started",
                blocked_reason=reason,
            )
        )
    return sorted(result, key=lambda row: (row.position, row.title, row.lab_id))


def require_access(db, user_id, lab_id, now):
    entry = next((row for row in progress(db, user_id, now) if row.lab_id == lab_id), None)
    if entry is None:
        raise HTTPException(404, "Laboratory not found")
    if entry.blocked_reason:
        raise HTTPException(409, entry.blocked_reason)
    return entry


def state(row: Booking, now: datetime):
    if row.cancelled_at:
        return "cancelled"
    start, end = utc(row.starts_at), utc(row.ends_at)
    if not row.checked_in_at and now >= min(end, start + GRACE):
        return "no_show"
    if now >= end:
        return "finished"
    return "active" if row.checked_in_at else "reserved"


def slot(row, user_id, now):
    mine = row.user_id == user_id
    return Slot(
        starts_at=utc(row.starts_at),
        ends_at=utc(row.ends_at),
        mine=mine,
        booking_id=row.id if mine else None,
        lab_id=row.lab_id if mine else None,
        state=state(row, now),
    )


def occupied(now):
    return (
        Booking.cancelled_at.is_(None),
        Booking.ends_at > now,
        or_(Booking.checked_in_at.is_not(None), Booking.starts_at > now - GRACE),
    )


def reserve(db, user_id, lab_id, interval: Interval, slot_id=None):
    lock_board(db)
    now = now_utc()
    rule = require_access(db, user_id, lab_id, now)
    start, end = interval.starts_at, interval.ends_at
    if slot_id:
        day = start.astimezone(ZoneInfo("Asia/Tomsk")).date()
        if not any(
            gap.slot_id == slot_id and gap.starts_at <= start and end <= gap.ends_at
            for gap in free_intervals(db, day, now, lab_id, user_id)
        ):
            raise HTTPException(409, "Slot has changed")
    if start < now or (rule.deadline and end > rule.deadline):
        raise HTTPException(409, "Interval outside available dates")
    if (
        not timedelta(minutes=rule.min_minutes)
        <= end - start
        <= timedelta(minutes=rule.max_minutes)
    ):
        raise HTTPException(422, "Duration outside laboratory limits")
    if db.scalar(
        select(Booking.id)
        .where(
            *occupied(now),
            or_(Booking.user_id == user_id, (Booking.starts_at < end) & (Booking.ends_at > start)),
        )
        .limit(1)
    ):
        raise HTTPException(409, "Reservation conflict")
    row = Booking(
        user_id=user_id,
        lab_id=lab_id,
        starts_at=start,
        ends_at=end,
        min_minutes=rule.min_minutes,
        max_minutes=rule.max_minutes,
    )
    db.add(row)
    db.flush()
    response = slot(row, user_id, now)
    db.commit()
    return response


def change(db, user_id, booking_id, cancel):
    lock_board(db)
    now = now_utc()
    row = db.scalar(select(Booking).where(Booking.id == booking_id, Booking.user_id == user_id))
    if row is None:
        raise HTTPException(404, "Booking not found")
    if cancel:
        if row.cancelled_at is None:
            if now >= utc(row.starts_at):
                raise HTTPException(409, "Booking has already started")
            row.cancelled_at = now
    elif not (utc(row.starts_at) <= now < utc(row.ends_at)) or state(row, now) not in (
        "reserved",
        "active",
    ):
        raise HTTPException(409, "Check-in unavailable")
    elif not row.checked_in_at:
        row.checked_in_at = now
    response = slot(row, user_id, now)
    db.commit()
    return response


def for_submission(db, user_id, lab_id):
    lock_board(db)
    now = now_utc()
    require_access(db, user_id, lab_id, now)
    row = db.scalar(
        select(Booking).where(
            *occupied(now),
            Booking.starts_at <= now,
            Booking.user_id == user_id,
            Booking.lab_id == lab_id,
        )
    )
    if row is None:
        raise HTTPException(409, "Active booking required")
    if not row.checked_in_at:
        row.checked_in_at = now
    return row


def schedule(db, user_id, window: Interval):
    now = now_utc()
    rows = db.scalars(
        select(Booking)
        .where(Booking.starts_at < window.ends_at, Booking.ends_at > window.starts_at)
        .order_by(Booking.starts_at, Booking.id)
    )
    return [
        slot(row, user_id, now)
        for row in rows
        if row.user_id == user_id or state(row, now) not in ("cancelled", "no_show")
    ]


def set_policy(db, lab_id, data: Policy):
    lock_board(db)
    get_lab(db, lab_id)
    row = db.get(LabPolicy, lab_id) or LabPolicy(lab_id=lab_id)
    for key, value in data.model_dump().items():
        setattr(row, key, utc(value) if key == "deadline" and value else value)
    db.add(row)
    db.commit()
    return data


def free_intervals(db, day, now, lab_id=None, user_id=None):
    start = datetime.combine(day, time.min, ZoneInfo("Asia/Tomsk")).astimezone(timezone.utc)
    end = start + timedelta(days=1)
    deadline = end
    minimum = timedelta(minutes=1)
    if lab_id is not None:
        entry = require_access(db, user_id, lab_id, now)
        minimum = timedelta(minutes=entry.min_minutes)
        if entry.deadline:
            deadline = min(end, entry.deadline)
    rows = db.execute(
        select(Booking.starts_at, Booking.ends_at)
        .where(*occupied(now), Booking.starts_at < end, Booking.ends_at > start)
        .order_by(Booking.starts_at)
    )
    gaps = []
    cursor = start
    # Offer whole minutes from the next usable minute; use the original gap bounds for its ID.
    first_minute = now.replace(second=0, microsecond=0)
    if first_minute < now:
        first_minute += timedelta(minutes=1)
    for a, b in [*rows, (end, end)]:
        right = min(utc(a), end)
        left = max(cursor, first_minute)
        latest = min(right, deadline)
        if latest - left >= minimum:
            key = uuid5(NAMESPACE_URL, f"fpga/1/{cursor.isoformat()}/{right.isoformat()}")
            gaps.append(FreeInterval(slot_id=key, starts_at=left, ends_at=latest))
        cursor = max(cursor, utc(b))
    return gaps
