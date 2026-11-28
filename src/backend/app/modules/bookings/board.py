import subprocess
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.bookings import service
from app.modules.bookings.models import Board, Booking, RunBooking
from app.modules.bookings.schemas import BoardStatus
from app.modules.runs.models import Run
from app.modules.runs.service import utc


def sample_board(client):
    try:
        output = subprocess.run(
            [client.executable.with_name("fpga-board-status")],
            env=client.environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=6,
            check=True,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError, UnicodeError):
        return "unavailable"
    return output if output in ("free", "busy") else "unavailable"


def occupancy(db, now):
    running = db.scalar(
        select(Run)
        .where(
            Run.mode == "hardware",
            Run.withdrawn_at.is_(None),
            Run.queue_claimed_at.is_not(None),
            Run.result_snapshot["status"].as_string().is_(None),
        )
        .order_by(Run.queue_claimed_at, Run.id)
        .limit(1)
    )
    booking = None
    if running:
        booking = db.scalar(
            select(Booking)
            .join(RunBooking, RunBooking.booking_id == Booking.id)
            .where(RunBooking.run_id == running.id)
        )
    if booking is None:
        booking = db.scalar(select(Booking).where(*service.occupied(now), Booking.starts_at <= now))
    return booking, running is not None


def heartbeat(engine, client):
    stamp = service.now_utc()
    observation = sample_board(client)
    with Session(engine) as db, db.begin():
        service.lock_board(db)
        row = db.get(Board, 1)
        if row.observed_at and utc(row.observed_at) >= stamp:
            return
        booking, running = occupancy(db, stamp)
        in_use = booking is not None or running
        if observation == "busy" or in_use:
            row.release_pending = True
        if observation == "free" and not in_use and row.release_pending:
            row.released_at = stamp
            row.release_pending = False
        row.observed_at = stamp
        row.observation = observation


def status(db, user_id):
    now = service.now_utc()
    board = db.get(Board, 1)
    observed = utc(board.observed_at) if board.observed_at else None
    physical = (
        board.observation if observed and observed >= now - timedelta(seconds=90) else "unavailable"
    )
    booking, running = occupancy(db, now)
    busy = physical == "busy" or booking is not None or running
    session = service.slot(booking, user_id, now) if booking else None
    return BoardStatus(
        state="unavailable" if physical == "unavailable" else "busy" if busy else "free",
        current_session=session,
        session_ends_at=session.ends_at if session else None,
        released_at=utc(board.released_at)
        if board.released_at and not busy and physical == "free"
        else None,
        updated_at=observed,
        server_time=now,
    )
