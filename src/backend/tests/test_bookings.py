from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Barrier
from uuid import UUID

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.core.config import Settings
from app.main import create_app
from app.modules.bookings import service
from app.modules.bookings.demo import LABS, prepare_demo
from app.modules.bookings.models import Booking, RunBooking
from app.modules.bookings.schemas import Interval
from app.modules.runs.models import Run
from app.modules.users.models import User

FIRST, SECOND = (str(row[0]) for row in LABS)
BASE = datetime(2030, 1, 2, 8, tzinfo=timezone.utc)


@pytest.fixture
def site(tmp_path, monkeypatch):
    clock = [BASE]
    monkeypatch.setattr(service, "now_utc", lambda: clock[0])
    app = create_app(Settings(app_env="test", database_url=f"sqlite:///{tmp_path}/booking.db"))
    with TestClient(app) as http:
        with app.state.session_factory() as db, db.begin():
            _, accounts = prepare_demo(db)
        with app.state.session_factory() as db, db.begin():
            assert prepare_demo(db)[1] == []
        yield http, dict(accounts), clock


def login(http, accounts, role):
    email = f"fpga-demo-{role}@example.com"
    response = http.post("/auth/login", json={"email": email, "password": accounts[email]})
    return {"X-CSRF-Token": response.json()["csrf_token"]}


def interval(start, end):
    return {
        "starts_at": (BASE + timedelta(minutes=start)).isoformat(),
        "ends_at": (BASE + timedelta(minutes=end)).isoformat(),
    }


def test_calendar_auth_limits_deadline_progress_and_owner(site):
    http, accounts, clock = site
    schedule = "/bookings"
    book = f"/labs/{FIRST}/bookings"
    rules = f"/labs/{FIRST}/policy"
    assert http.get(schedule, params=interval(0, 100)).status_code == 401
    h = login(http, accounts, "student")
    assert http.post(book, json=interval(2, 12)).status_code == 403
    assert http.put(rules, json={}, headers=h).status_code == 403
    assert http.post(book, json=interval(2, 6), headers=h).status_code == 422
    assert (
        http.post(
            book,
            json={"starts_at": "2030-01-02T08:00:00", "ends_at": interval(2, 12)["ends_at"]},
            headers=h,
        ).status_code
        == 422
    )
    assert http.post(f"/labs/{SECOND}/bookings", json=interval(2, 12), headers=h).status_code == 409
    a = http.post(book, json=interval(2, 12), headers=h).json()["booking_id"]
    assert http.post(book, json=interval(12, 22), headers=h).status_code == 409
    assert http.delete(f"/bookings/{a}", headers=h).json()["state"] == "cancelled"
    b = http.post(book, json=interval(2, 12), headers=h).json()["booking_id"]
    t = login(http, accounts, "teacher")
    assert http.post(book, json=interval(12, 22), headers=t).status_code == 403
    assert http.delete(f"/bookings/{b}", headers=t).status_code == 404
    (public,) = http.get(schedule, params=interval(0, 30)).json()
    assert public["booking_id"] is None and public["lab_id"] is None and not public["mine"]
    rule = {
        "min_minutes": 8,
        "max_minutes": 9,
        "position": 1,
        "deadline": interval(0, 30)["ends_at"],
    }
    assert http.put(rules, json=rule, headers=t).status_code == 200
    h = login(http, accounts, "student")
    assert http.post(f"/bookings/{b}/check-in", headers=h).status_code == 409
    clock[0] += timedelta(minutes=2)
    assert http.delete(f"/bookings/{b}", headers=h).status_code == 409
    source = {"source_code": "module student_top; endmodule"}
    ids = [
        http.post(f"/labs/{FIRST}/submissions", json=source, headers=h).json()["id"]
        for _ in range(2)
    ]
    assert len(set(ids)) == 2
    assert http.post(f"/bookings/{b}/check-in", headers=h).json()["state"] == "active"
    with http.app.state.session_factory() as db, db.begin():
        row = db.get(Booking, UUID(b))
        assert (row.min_minutes, row.max_minutes) == (5, 60)
        assert len(list(db.scalars(select(RunBooking)))) == 2
        run = db.scalar(select(Run).where(Run.submission_id == UUID(ids[0])))
        run.mode = "mock"
        run.result_snapshot = {"status": "passed", "hardware_verified": False}
    assert http.get("/me/labs").json()[1]["blocked_reason"] == "previous_lab"
    with http.app.state.session_factory() as db, db.begin():
        run = db.scalar(select(Run).where(Run.submission_id == UUID(ids[0])))
        run.mode = "hardware"
        run.result_snapshot = {"status": "passed", "hardware_verified": True}
    report = http.get("/me/labs").json()
    assert report[0]["status"] == "passed" and report[1]["blocked_reason"] is None
    clock[0] += timedelta(minutes=10)
    assert http.post(f"/labs/{FIRST}/submissions", json=source, headers=h).status_code == 409
    assert http.post(book, json=interval(25, 34), headers=h).status_code == 409
    assert http.post(book, json=interval(13, 23), headers=h).status_code == 422
    clock[0] += timedelta(minutes=18)
    assert http.get("/me/labs").json()[0]["blocked_reason"] == "deadline"


def test_no_show_frees_board_at_boundary_and_short_slot_expires(site):
    http, accounts, clock = site
    h = login(http, accounts, "student")
    path = f"/labs/{FIRST}/bookings"
    first = http.post(path, json=interval(0, 25), headers=h).json()["booking_id"]
    clock[0] += timedelta(minutes=15)
    assert http.post(f"/bookings/{first}/check-in", headers=h).status_code == 409
    assert http.get("/bookings", params=interval(0, 30)).json()[0]["state"] == "no_show"
    second = http.post(path, json=interval(15, 20), headers=h).json()["booking_id"]
    clock[0] += timedelta(minutes=5)
    assert http.post(f"/bookings/{second}/check-in", headers=h).status_code == 409
    assert http.post(path, json=interval(20, 30), headers=h).status_code == 201


def test_concurrent_cross_lab_reservations_and_adjacent_intervals(site):
    http, accounts, _ = site
    t = login(http, accounts, "teacher")
    assert http.put(f"/labs/{SECOND}/policy", headers=t, json={}).status_code == 200
    with http.app.state.session_factory() as db, db.begin():
        another = User(email="peer@example.com", full_name="Peer")
        db.add(another)
        db.flush()
        users = [
            db.scalar(select(User.id).where(User.email == "fpga-demo-student@example.com")),
            another.id,
        ]
    barrier = Barrier(2)

    def book(index):
        with http.app.state.session_factory() as db:
            barrier.wait(timeout=5)
            try:
                service.reserve(db, users[index], LABS[index][0], Interval(**interval(2, 12)))
                return 201
            except HTTPException as exc:
                return exc.status_code

    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(book, range(2)))
    assert sorted(results) == [201, 409]
    other = results.index(409)
    with http.app.state.session_factory() as db:
        service.reserve(db, users[other], LABS[other][0], Interval(**interval(12, 22)))


def test_frontend_slots_my_bookings_lab_fields_and_health(site):
    http, accounts, clock = site
    h = login(http, accounts, "student")
    params = {"date": "2030-01-02", "lab_id": FIRST}
    slots = http.get("/bookings/slots", params=params)
    assert slots.status_code == 200
    (gap,) = slots.json()
    assert gap["available"] and gap["ends_at"] == "2030-01-02T17:00:00Z"
    body = {**interval(3, 13), "lab_id": FIRST, "slot_id": gap["slot_id"]}
    booked = http.post("/bookings", headers=h, json=body)
    assert booked.status_code == 201
    booking = booked.json()
    assert http.get("/bookings/me").json() == [booking]
    available = http.get("/bookings/slots", params=params).json()
    assert len(available) == 1  # 3-minute earlier gap fails the lab minimum.
    assert available[0]["starts_at"] == booking["ends_at"]
    assert http.post("/bookings", headers=h, json=body).status_code == 409
    lab = http.get(f"/labs/{SECOND}").json()
    assert lab["is_locked"] and lab["blocked_reason"] == "previous_lab"
    catalogue = {row["id"]: row for row in http.get("/labs").json()}
    assert catalogue[SECOND]["status"] == lab["status"] == "not_started"
    assert http.delete("/bookings/" + booking["booking_id"], headers=h).status_code == 200
    assert http.get("/bookings/me").json()[0]["state"] == "cancelled"
    assert http.get("/health").status_code == http.get("/health/db").status_code == 200


def test_board_timer_busy_overrun_released_and_stale(site, monkeypatch):
    from app.modules.bookings import board

    http, accounts, clock = site
    h = login(http, accounts, "student")
    engine = http.app.state.session_factory.kw["bind"]

    def read():
        return http.get("/board/status").json()

    assert read()["state"] == "unavailable"
    signal = ["free"]
    monkeypatch.setattr(board, "sample_board", lambda client: signal[0])
    board.heartbeat(engine, None)
    assert read()["state"] == "free"
    http.post("/bookings", json={**interval(0, 10), "lab_id": FIRST}, headers=h)
    assert read()["state"] == "busy"
    submission = http.post(
        f"/labs/{FIRST}/submissions", json={"source_code": "module x; endmodule"}, headers=h
    ).json()
    with http.app.state.session_factory() as db, db.begin():
        run = db.scalar(select(Run).where(Run.submission_id == UUID(submission["id"])))
        run.queue_claimed_at = clock[0]
    clock[0] += timedelta(minutes=11)
    signal[0] = "busy"
    board.heartbeat(engine, None)
    state = read()
    assert state["state"] == "busy" and state["released_at"] is None
    assert state["current_session"]["mine"] and state["session_ends_at"] == "2030-01-02T08:10:00Z"
    with http.app.state.session_factory() as db, db.begin():
        db.scalar(select(Run)).result_snapshot = {"status": "passed"}
    clock[0] += timedelta(seconds=4)
    signal[0] = "free"
    board.heartbeat(engine, None)
    assert read()["released_at"] == "2030-01-02T08:11:04Z" and read()["state"] == "free"
    clock[0] += timedelta(seconds=91)
    assert read()["state"] == "unavailable"
