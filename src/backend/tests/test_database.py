from pathlib import Path
from uuid import uuid4

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from fastapi.testclient import TestClient
from sqlalchemy import inspect, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.db.base import Base
from app.db.session import get_db
from app.main import create_app
from app.modules.users.models import User


def test_user_is_saved_with_defaults(database_engine):
    with Session(database_engine) as session:
        user = User(email="student@example.com", full_name="Иван Михайличенко")
        session.add(user)
        session.commit()
        session.refresh(user)
        assert user.id is not None
        assert user.role == "student"
        assert user.is_active is True
        assert user.password_hash is None
        assert user.created_at.tzinfo is not None
        user_id = user.id
    with Session(database_engine) as session:
        assert session.get(User, user_id).full_name == "Иван Михайличенко"


def test_email_is_unique_ignoring_case(database_engine):
    with Session(database_engine) as session:
        session.add(User(email="Student@example.com", full_name="Иван"))
        session.commit()
        session.add(User(email="student@example.com", full_name="Другой студент"))
        with pytest.raises(IntegrityError):
            session.commit()
        session.rollback()


@pytest.mark.parametrize("role", ["admin", "unknown"])
def test_unknown_role_is_rejected(database_engine, role):
    with Session(database_engine) as session:
        session.add(User(email="student@example.com", full_name="Иван", role=role))
        with pytest.raises(IntegrityError):
            session.commit()
        session.rollback()


def test_database_health_with_real_connection(database_engine):
    settings = Settings(
        _env_file=None,
        database_url=database_engine.url.render_as_string(hide_password=False),
    )
    application = create_app(settings)

    def override_db():
        with Session(database_engine) as session:
            yield session

    application.dependency_overrides[get_db] = override_db
    with TestClient(application) as client:
        response = client.get("/health/db")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "connected"}


def test_migration_matches_model_and_is_reversible(database_engine):
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    with database_engine.begin() as connection:
        context = MigrationContext.configure(connection)
        assert compare_metadata(context, Base.metadata) == []
        config.attributes["connection"] = connection
        command.downgrade(config, "base")
        assert "users" not in inspect(connection).get_table_names()
        command.upgrade(config, "head")
        assert "users" in inspect(connection).get_table_names()
        connection.execute(
            text("INSERT INTO users (id, email, full_name) VALUES (:id, :email, :name)"),
            {"id": uuid4(), "email": "raw@example.com", "name": "Иван"},
        )
        row = connection.execute(text("SELECT role, is_active FROM users")).one()
        assert row.role == "student"
        assert row.is_active is True
