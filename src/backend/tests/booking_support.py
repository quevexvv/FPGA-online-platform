from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import update

from app.modules.bookings.models import Booking
from app.modules.labs.seed import DEMO_LAB_ID


def open_test_window(client, lab_id=DEMO_LAB_ID):
    user_id = UUID(client.get("/auth/me").json()["id"])
    now = datetime.now(timezone.utc)
    with client.app.state.session_factory() as db, db.begin():
        db.execute(update(Booking).where(Booking.ends_at > now).values(ends_at=now))
        db.add(
            Booking(
                user_id=user_id,
                lab_id=lab_id,
                starts_at=now - timedelta(minutes=1),
                ends_at=now + timedelta(minutes=10),
                min_minutes=5,
                max_minutes=60,
            )
        )
