from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from fastapi.testclient import TestClient
from sqlalchemy import func, inspect, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.db.base import Base
from app.db.session import create_database_engine
from app.main import create_app
from app.modules.auth.models import AuthSession
from app.modules.labs.models import Lab
from app.modules.labs.seed import DEMO_LAB_ID, seed_demo
from app.modules.submissions.models import Submission
from app.modules.submissions.schemas import MAX_SOURCE_BYTES
from app.modules.users.models import User

SOURCE = "module student_top;\r\n    // Тестовый исходник\r\nendmodule\r\n"
SUBMIT_PATH = f"/labs/{DEMO_LAB_ID}/submissions"
PASSWORD = "Submission demo password 123"


@pytest.fixture
def settings(tmp_path):
    return Settings(
        _env_file=None, app_env="test", database_url=f"sqlite:///{tmp_path}/submissions.db"
    )


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as client:
        with client.app.state.session_factory() as db:
            seed_demo(db)
        yield client


def login(client, email="owner@example.com"):
    credentials = {"email": email, "password": PASSWORD}
    response = client.post("/auth/register", json={**credentials, "full_name": "Student"})
    assert response.status_code == 201
    response = client.post("/auth/login", json=credentials)
    assert response.status_code == 200
    return {"X-CSRF-Token": response.json()["csrf_token"]}


@pytest.fixture
def headers(client):
    return login(client)


def submit(client, headers, source=SOURCE, path=SUBMIT_PATH):
    return client.post(path, json={"source_code": source}, headers=headers)


def count_submissions(client):
    with client.app.state.session_factory() as db:
        return db.scalar(select(func.count()).select_from(Submission))


def test_submit_list_and_detail_preserve_exact_code_and_owner(client, headers):
    response = submit(client, headers)
    assert response.status_code == 201
    data = response.json()
    assert set(data) == {"id", "lab_id", "created_at"}
    assert data["lab_id"] == str(DEMO_LAB_ID)
    assert datetime.fromisoformat(data["created_at"]).utcoffset() == timedelta(0)
    assert response.headers["location"] == f"/submissions/{data['id']}"
    assert response.headers["cache-control"] == "no-store"
    with client.app.state.session_factory() as db:
        stored = db.get(Submission, UUID(data["id"]))
        assert stored.user_id == db.scalar(select(User.id))
        assert stored.source_code == SOURCE
    listing = client.get(SUBMIT_PATH)
    assert listing.status_code == 200
    assert listing.json() == [data]
    assert listing.headers["cache-control"] == "no-store"
    detail = client.get(response.headers["location"])
    assert detail.status_code == 200
    assert detail.json() == {**data, "source_code": SOURCE}
    assert detail.headers["cache-control"] == "no-store"


@pytest.mark.parametrize("suffix", ["", "/source"])
@pytest.mark.parametrize("reader_role", ["student", "teacher"])
def test_other_user_cannot_list_or_open_source_even_as_teacher(
    client, headers, reader_role, suffix
):
    created = submit(client, headers).json()
    client.cookies.clear()
    login(client, "other@example.com")
    with client.app.state.session_factory() as db:
        db.scalar(select(User).where(User.email == "other@example.com")).role = reader_role
        db.commit()
    assert client.get(SUBMIT_PATH).json() == []
    foreign = client.get(f"/submissions/{created['id']}{suffix}")
    missing = client.get(f"/submissions/{uuid4()}{suffix}")
    assert foreign.status_code == missing.status_code == 404
    assert foreign.json() == missing.json() == {"detail": "Submission not found"}
    assert foreign.headers["cache-control"] == "no-store"


def test_download_preserves_utf8_and_line_endings_after_lab_is_unpublished(client, headers):
    created = submit(client, headers).json()
    with client.app.state.session_factory() as db:
        db.get(Lab, DEMO_LAB_ID).is_published = False
        db.commit()
    response = client.get(f"/submissions/{created['id']}/source")
    assert response.status_code == 200
    assert response.content == SOURCE.encode("utf-8")
    assert response.headers["content-type"] == "text/plain; charset=utf-8"
    assert response.headers["content-disposition"] == (
        f'attachment; filename="submission-{created["id"]}.v"'
    )
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["cache-control"] == "no-store"
    assert count_submissions(client) == 1


@pytest.mark.parametrize("state", ["anonymous", "forged", "expired", "inactive", "logged_out"])
def test_all_routes_reject_invalid_sessions(client, headers, state):
    created = submit(client, headers).json()
    if state in ("anonymous", "forged", "logged_out"):
        token = client.cookies.get("fpga_session")
        if state == "logged_out":
            assert client.post("/auth/logout", headers=headers).status_code == 204
        client.cookies.clear()
        if state != "anonymous":
            client.cookies.set("fpga_session", token if state == "logged_out" else "forged")
    else:
        with client.app.state.session_factory() as db:
            if state == "expired":
                db.scalar(select(AuthSession)).expires_at = datetime.now(timezone.utc) - timedelta(
                    1
                )
            else:
                db.scalar(select(User)).is_active = False
            db.commit()
    assert submit(client, headers).status_code == 401
    assert client.get(SUBMIT_PATH).status_code == 401
    assert client.get(f"/submissions/{created['id']}").status_code == 401
    download = client.get(f"/submissions/{created['id']}/source")
    assert download.status_code == 401
    assert download.headers["cache-control"] == "no-store"
    assert count_submissions(client) == 1


@pytest.mark.parametrize("state", ["missing", "wrong", "foreign_origin", "previous_login"])
def test_csrf_and_origin_protect_submission(client, headers, state):
    if state == "missing":
        headers = {}
    elif state == "wrong":
        headers = {"X-CSRF-Token": "wrong"}
    elif state == "foreign_origin":
        headers = {**headers, "Origin": "https://untrusted.example"}
    else:
        assert (
            client.post(
                "/auth/login", json={"email": "owner@example.com", "password": PASSWORD}
            ).status_code
            == 200
        )
    response = submit(client, headers)
    assert response.status_code == 403
    assert response.headers["cache-control"] == "no-store"
    assert count_submissions(client) == 0


def test_trusted_frontend_can_submit_with_recovered_csrf(client, headers):
    csrf = client.get("/auth/csrf").json()["csrf_token"]
    response = submit(client, {"X-CSRF-Token": csrf, "Origin": "http://localhost:5173"})
    assert response.status_code == 201
    assert response.headers["access-control-allow-origin"] == "http://localhost:5173"
    assert response.headers["access-control-allow-credentials"] == "true"


def test_teacher_cannot_create_student_submissions(client, headers):
    with client.app.state.session_factory() as db:
        db.scalar(select(User)).role = "teacher"
        db.commit()
    assert submit(client, headers).status_code == 403
    assert count_submissions(client) == 0


def test_only_published_labs_accept_code_but_own_history_remains_available(client, headers):
    created = submit(client, headers).json()
    with client.app.state.session_factory() as db:
        db.get(Lab, DEMO_LAB_ID).is_published = False
        db.commit()
    assert submit(client, headers).status_code == 404
    assert submit(client, headers, path=f"/labs/{uuid4()}/submissions").status_code == 404
    assert client.get(SUBMIT_PATH).json() == [created]
    assert client.get(f"/submissions/{created['id']}").json()["source_code"] == SOURCE
    assert client.get(f"/labs/{uuid4()}/submissions").json() == []
    assert count_submissions(client) == 1


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"source_code": ""},
        {"source_code": " \t\r\n"},
        {"source_code": None},
        {"source_code": 123},
        {"source_code": "hello\x00world"},
        {"source_code": "x" * (MAX_SOURCE_BYTES + 1)},
        {"source_code": "я" * (MAX_SOURCE_BYTES // 2 + 1)},
        {"source_code": SOURCE, "user_id": str(uuid4())},
        {"source_code": SOURCE, "lab_id": str(uuid4())},
        {"source_code": SOURCE, "test_set": "untrusted"},
        {"source_code": SOURCE, "status": "passed"},
    ],
)
def test_invalid_payload_does_not_create_rows_or_echo_source(client, headers, payload):
    response = client.post(SUBMIT_PATH, json=payload, headers=headers)
    assert response.status_code == 422
    assert response.headers["cache-control"] == "no-store"
    for error in response.json()["detail"]:
        assert set(error) <= {"type", "loc", "msg"}
    assert count_submissions(client) == 0


@pytest.mark.parametrize("source", ["x" * MAX_SOURCE_BYTES, "я" * (MAX_SOURCE_BYTES // 2)])
def test_utf8_byte_limit_is_inclusive(client, headers, source):
    response = submit(client, headers, source)
    assert response.status_code == 201
    assert client.get(response.headers["location"]).json()["source_code"] == source


def test_invalid_unicode_is_a_validation_error(client, headers):
    response = client.post(
        SUBMIT_PATH,
        content=b'{"source_code":"\\ud800"}',
        headers={**headers, "Content-Type": "application/json"},
    )
    assert response.status_code == 422
    assert count_submissions(client) == 0


def test_history_filters_lab_and_has_stable_pagination(client, headers):
    first = submit(client, headers).json()
    second = submit(client, headers, "module changed; endmodule").json()
    assert first["id"] != second["id"]
    other_lab_id = uuid4()
    with client.app.state.session_factory() as db:
        db.add(
            Lab(
                id=other_lab_id,
                title="Other lab",
                description="",
                statement="Task",
                template="",
                interface_description="Interface",
                kind="sequential",
                is_published=True,
            )
        )
        timestamp = datetime(2026, 1, 1, tzinfo=timezone.utc)
        for stored in db.scalars(select(Submission)):
            stored.created_at = timestamp
        db.commit()
    submit(client, headers, path=f"/labs/{other_lab_id}/submissions")
    expected_ids = sorted([first["id"], second["id"]], reverse=True)
    page1 = client.get(f"{SUBMIT_PATH}?limit=1&offset=0").json()
    page2 = client.get(f"{SUBMIT_PATH}?limit=1&offset=1").json()
    assert [page1[0]["id"], page2[0]["id"]] == expected_ids
    assert client.get(f"{SUBMIT_PATH}?limit=1&offset=2").json() == []


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1", "limit=abc"])
def test_history_validates_page_parameters(client, headers, query):
    assert client.get(f"{SUBMIT_PATH}?{query}").status_code == 422


def test_invalid_ids_and_malformed_json(client, headers):
    assert client.get("/submissions/not-a-uuid").status_code == 422
    assert client.get("/labs/not-a-uuid/submissions").status_code == 422
    assert submit(client, headers, path="/labs/not-a-uuid/submissions").status_code == 422
    assert (
        client.post(
            SUBMIT_PATH, content="{broken", headers={**headers, "Content-Type": "application/json"}
        ).status_code
        == 422
    )
    assert count_submissions(client) == 0


def test_submissions_survive_restart_without_changing_prior_source(client, headers, settings):
    first = submit(client, headers).json()
    second = submit(client, headers, "module next; endmodule").json()
    token = client.cookies.get("fpga_session")
    with TestClient(create_app(settings)) as restarted:
        restarted.cookies.set("fpga_session", token)
        assert restarted.get(f"/submissions/{first['id']}").json()["source_code"] == SOURCE
        assert restarted.get(f"/submissions/{second['id']}").json()["source_code"] != SOURCE
        assert len(restarted.get(SUBMIT_PATH).json()) == 2


def test_sqlite_migration_preserves_existing_users_labs_and_sessions(settings):
    engine = create_database_engine(settings)
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    user_id, lab_id = uuid4(), uuid4()
    try:
        with engine.begin() as connection:
            config.attributes["connection"] = connection
            command.upgrade(config, "0003_create_labs")
            connection.execute(
                User.__table__.insert().values(
                    id=user_id, email="existing@example.com", full_name="Existing student"
                )
            )
            connection.execute(
                Lab.__table__.insert().values(
                    id=lab_id,
                    title="Existing lab",
                    description="",
                    statement="Task",
                    template="",
                    interface_description="Interface",
                    kind="combinational",
                    is_published=True,
                )
            )
            connection.execute(
                AuthSession.__table__.insert().values(
                    token_hash="a" * 64,
                    user_id=user_id,
                    csrf_hash="b" * 64,
                    expires_at=datetime.now(timezone.utc) + timedelta(hours=1),
                )
            )
            command.upgrade(config, "head")
            assert compare_metadata(MigrationContext.configure(connection), Base.metadata) == []
            assert connection.scalar(select(func.count()).select_from(Submission)) == 0
            command.downgrade(config, "0003_create_labs")
            assert "submissions" not in inspect(connection).get_table_names()
            assert connection.scalar(select(User.id)) == user_id
            assert connection.scalar(select(Lab.id)) == lab_id
            assert connection.scalar(select(AuthSession.token_hash)) == "a" * 64
            command.upgrade(config, "head")
            assert "submissions" in inspect(connection).get_table_names()
    finally:
        engine.dispose()


def test_postgresql_persists_source_and_restricts_deleting_its_lab(database_engine):
    with Session(database_engine) as db:
        user = User(email="source@example.com", full_name="Student")
        db.add(user)
        lab_id = seed_demo(db)
        db.add(Submission(user_id=user.id, lab_id=lab_id, source_code=SOURCE))
        db.commit()
        submission = db.scalar(select(Submission))
        assert submission.source_code == SOURCE
        assert submission.created_at.tzinfo is not None
        db.delete(db.get(Lab, lab_id))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        assert db.scalar(select(Submission)).source_code == SOURCE
