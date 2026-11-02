from unittest.mock import Mock

from fastapi.testclient import TestClient
from sqlalchemy.exc import OperationalError

from app.core.config import Settings
from app.db.session import get_db
from app.main import create_app


def make_application():
    settings = Settings(
        _env_file=None,
        database_url="postgresql+psycopg://test:test@127.0.0.1:65432/fpga_test",
    )
    return create_app(settings)


def test_health_works_without_database():
    with TestClient(make_application()) as client:
        response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_database_failure_does_not_expose_details():
    application = make_application()
    session = Mock()
    session.execute.side_effect = OperationalError("SELECT 1", {}, Exception("private detail"))
    application.dependency_overrides[get_db] = lambda: session
    with TestClient(application) as client:
        response = client.get("/health/db")
    assert response.status_code == 503
    assert response.json() == {"detail": "Database unavailable"}
    assert "private detail" not in response.text


def test_cors_accepts_frontend_and_rejects_unknown_origin():
    with TestClient(make_application()) as client:
        allowed = client.options(
            "/health",
            headers={
                "Origin": "http://localhost:5173",
                "Access-Control-Request-Method": "GET",
            },
        )
        denied = client.options(
            "/health",
            headers={
                "Origin": "https://other.example",
                "Access-Control-Request-Method": "GET",
            },
        )
    assert allowed.status_code == 200
    assert allowed.headers["access-control-allow-origin"] == "http://localhost:5173"
    assert denied.status_code == 400
    assert "access-control-allow-origin" not in denied.headers
