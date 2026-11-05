from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import uuid4

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from fastapi.testclient import TestClient
from sqlalchemy import func, inspect, select

from app.core.config import Settings
from app.db.base import Base
from app.db.session import create_database_engine
from app.main import create_app
from app.modules.auth.models import AuthSession
from app.modules.labs.models import Lab
from app.modules.labs.seed import DEMO_LAB_ID, seed_demo, seed_local_demo
from app.modules.users.models import User


@pytest.fixture
def settings(tmp_path):
    return Settings(_env_file=None, app_env="test", database_url=f"sqlite:///{tmp_path}/labs.db")


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as client:
        yield client


@pytest.fixture
def authenticated(client):
    credentials = {"email": "student@example.com", "password": "Student password 123"}
    assert (
        client.post("/auth/register", json={**credentials, "full_name": "Студент"}).status_code
        == 201
    )
    assert client.post("/auth/login", json=credentials).status_code == 200
    return client


@pytest.fixture
def lab_id(client):
    with client.app.state.session_factory() as db:
        return seed_demo(db)


@pytest.mark.parametrize("path", ["/labs", f"/labs/{DEMO_LAB_ID}"])
def test_catalogue_requires_valid_session(client, path):
    assert client.get(path).status_code == 401
    client.cookies.set("fpga_session", "forged")
    assert client.get(path).status_code == 401


def test_empty_catalogue_and_missing_lab(authenticated):
    assert authenticated.get("/labs").json() == []
    response = authenticated.get(f"/labs/{uuid4()}")
    assert response.status_code == 404
    assert response.json() == {"detail": "Laboratory not found"}


def test_list_and_detail_use_explicit_public_fields(authenticated, lab_id):
    response = authenticated.get("/labs")
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    items = response.json()
    assert len(items) == 1
    summary = items[0]
    assert set(summary) == {"id", "title", "description", "kind", "is_demo"}
    assert summary["id"] == str(lab_id)
    assert summary["kind"] == "combinational"
    assert summary["is_demo"] is True
    response = authenticated.get(f"/labs/{lab_id}")
    assert response.status_code == 200
    detail = response.json()
    assert set(detail) == set(summary) | {"statement", "template", "interface_description"}
    assert "module student_top" in detail["template"]
    assert "TODO" in detail["template"]
    assert "Verilog-2001" in detail["interface_description"]


@pytest.mark.parametrize("role", ["student", "teacher"])
def test_unpublished_labs_are_hidden_for_both_roles(authenticated, lab_id, role):
    with authenticated.app.state.session_factory() as db:
        db.scalar(select(User)).role = role
        db.commit()
    assert authenticated.get(f"/labs/{lab_id}").status_code == 200
    with authenticated.app.state.session_factory() as db:
        db.get(Lab, lab_id).is_published = False
        db.commit()
    assert authenticated.get("/labs").json() == []
    assert authenticated.get(f"/labs/{lab_id}").status_code == 404


def test_list_has_stable_pagination(authenticated, lab_id):
    with authenticated.app.state.session_factory() as db:
        for title in ("B", "A"):
            db.add(
                Lab(
                    title=title,
                    description="Description",
                    statement="Task",
                    template="Template",
                    interface_description="Interface",
                    kind="sequential",
                    is_published=True,
                )
            )
        db.commit()
    first = authenticated.get("/labs?limit=1&offset=0").json()
    second = authenticated.get("/labs?limit=1&offset=1").json()
    assert [first[0]["title"], second[0]["title"]] == ["A", "B"]
    assert first[0]["is_demo"] is False
    assert authenticated.get("/labs?offset=3").json() == []


@pytest.mark.parametrize("query", ["limit=0", "limit=101", "offset=-1", "limit=abc"])
def test_invalid_pagination_is_rejected(authenticated, query):
    assert authenticated.get(f"/labs?{query}").status_code == 422


def test_invalid_uuid_is_rejected(authenticated):
    assert authenticated.get("/labs/not-a-uuid").status_code == 422


@pytest.mark.parametrize("state", ["expired", "inactive", "logged_out"])
def test_invalidated_session_cannot_read_labs(authenticated, lab_id, state):
    if state == "logged_out":
        csrf = authenticated.get("/auth/csrf").json()["csrf_token"]
        assert authenticated.post("/auth/logout", headers={"X-CSRF-Token": csrf}).status_code == 204
    else:
        with authenticated.app.state.session_factory() as db:
            if state == "expired":
                db.scalar(select(AuthSession)).expires_at = datetime.now(timezone.utc) - timedelta(
                    seconds=1
                )
            else:
                db.scalar(select(User)).is_active = False
            db.commit()
    assert authenticated.get("/labs").status_code == 401
    assert authenticated.get(f"/labs/{lab_id}").status_code == 401


def test_local_seed_is_repeatable_persists_and_preserves_edits(settings):
    assert seed_local_demo(settings) == DEMO_LAB_ID
    with TestClient(create_app(settings)) as client:
        with client.app.state.session_factory() as db:
            lab = db.get(Lab, DEMO_LAB_ID)
            assert lab.is_demo and lab.is_published
            lab.title = "Edited title"
            lab.is_published = False
            db.commit()
    seed_local_demo(settings)
    with TestClient(create_app(settings)) as restarted:
        with restarted.app.state.session_factory() as db:
            assert db.scalar(select(func.count()).select_from(Lab)) == 1
            lab = db.get(Lab, DEMO_LAB_ID)
            assert lab.title == "Edited title"
            assert lab.is_published is False


def test_seed_rejects_non_sqlite_without_connecting():
    settings = Settings(
        _env_file=None,
        app_env="test",
        database_url="postgresql+psycopg://test:test@127.0.0.1:65432/fpga_test",
    )
    with pytest.raises(ValueError, match="local SQLite"):
        seed_local_demo(settings)


def test_sqlite_upgrade_preserves_existing_users_and_matches_models(settings):
    engine = create_database_engine(settings)
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    user_id = uuid4()
    try:
        with engine.begin() as connection:
            config.attributes["connection"] = connection
            command.upgrade(config, "0002_create_auth_sessions")
            connection.execute(
                User.__table__.insert().values(
                    id=user_id, email="existing@example.com", full_name="Existing user"
                )
            )
            command.upgrade(config, "head")
            assert connection.scalar(select(User.id)) == user_id
            assert connection.scalar(select(func.count()).select_from(Lab)) == 0
            assert compare_metadata(MigrationContext.configure(connection), Base.metadata) == []
            command.downgrade(config, "0002_create_auth_sessions")
            assert "labs" not in inspect(connection).get_table_names()
            assert connection.scalar(select(User.id)) == user_id
            command.upgrade(config, "head")
            assert "labs" in inspect(connection).get_table_names()
    finally:
        engine.dispose()
