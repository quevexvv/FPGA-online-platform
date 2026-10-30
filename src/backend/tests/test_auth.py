from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import select

from app.core.config import Settings
from app.core.security import token_digest, verify_password
from app.main import create_app
from app.modules.auth.models import AuthSession
from app.modules.users.models import User

PASSWORD = "My strong password 123"
STUDENT = {"email": "student@example.com", "full_name": "Иван", "password": PASSWORD}


@pytest.fixture
def settings(tmp_path):
    return Settings(
        _env_file=None, app_env="test", database_url=f"sqlite:///{tmp_path}/auth.sqlite3"
    )


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as client:
        yield client


def register_and_login(client):
    assert client.post("/auth/register", json=STUDENT).status_code == 201
    response = client.post("/auth/login", json={"email": STUDENT["email"], "password": PASSWORD})
    assert response.status_code == 200
    return response


def test_register_normalizes_email_hashes_password_and_returns_student(client):
    response = client.post(
        "/auth/register",
        json={
            **STUDENT,
            "email": "  Student@EXAMPLE.COM  ",
            "full_name": "  Иван  ",
        },
    )
    assert response.status_code == 201
    data = response.json()
    assert data["email"] == "student@example.com"
    assert data["full_name"] == "Иван"
    assert data["role"] == "student"
    assert data["is_active"] is True
    assert "password" not in response.text
    assert "hash" not in response.text
    assert response.headers["cache-control"] == "no-store"
    with client.app.state.session_factory() as db:
        user = db.scalar(select(User))
        assert user.password_hash.startswith("$argon2id$")
        assert user.password_hash != PASSWORD
        assert verify_password(PASSWORD, user.password_hash)
    assert client.get("/auth/me").status_code == 401


@pytest.mark.parametrize(
    "changes",
    [
        {"password": "tiny123"},
        {"password": "x" * 129},
        {"email": "broken"},
        {"full_name": "   "},
        {"role": "teacher"},
        {"is_active": False},
    ],
)
def test_invalid_registration_is_rejected_without_password_in_errors(client, changes):
    data = {**STUDENT, **changes}
    response = client.post("/auth/register", json=data)
    assert response.status_code == 422
    assert data["password"] not in response.text
    with client.app.state.session_factory() as db:
        assert db.scalar(select(User)) is None


def test_duplicate_email_is_rejected_ignoring_case(client):
    assert client.post("/auth/register", json=STUDENT).status_code == 201
    response = client.post("/auth/register", json={**STUDENT, "email": "STUDENT@example.com"})
    assert response.status_code == 409


def test_concurrent_registration_cannot_create_duplicate_users(client):
    with ThreadPoolExecutor(max_workers=2) as executor:
        responses = list(
            executor.map(lambda _: client.post("/auth/register", json=STUDENT), range(2))
        )
    assert sorted(r.status_code for r in responses) == [201, 409]


def test_login_me_logout_revokes_copied_cookie(client):
    login = register_and_login(client)
    token = client.cookies.get("fpga_session")
    csrf = login.json()["csrf_token"]
    cookie = login.headers["set-cookie"]
    assert "HttpOnly" in cookie and "SameSite=lax" in cookie
    assert "Max-Age=86400" in cookie
    assert client.get("/auth/me").json()["email"] == STUDENT["email"]
    with client.app.state.session_factory() as db:
        stored = db.scalar(select(AuthSession))
        assert stored.token_hash == token_digest(token)
        assert stored.csrf_hash == token_digest(csrf)
        assert stored.token_hash != token
    response = client.post("/auth/logout", headers={"X-CSRF-Token": csrf})
    assert response.status_code == 204
    assert "fpga_session" not in client.cookies
    client.cookies.set("fpga_session", token)
    assert client.get("/auth/me").status_code == 401


@pytest.mark.parametrize(
    "email,password",
    [
        ("student@example.com", "incorrect password"),
        ("missing@example.com", PASSWORD),
    ],
)
def test_invalid_credentials_have_same_error(client, email, password):
    client.post("/auth/register", json=STUDENT)
    response = client.post("/auth/login", json={"email": email, "password": password})
    assert response.status_code == 401
    assert response.json() == {"detail": "Invalid email or password"}
    assert "fpga_session" not in client.cookies


def test_login_accepts_case_and_rotates_existing_session(client):
    register_and_login(client)
    old = client.cookies.get("fpga_session")
    response = client.post(
        "/auth/login", json={"email": "STUDENT@example.com", "password": PASSWORD}
    )
    assert response.status_code == 200
    assert client.cookies.get("fpga_session") != old
    with client.app.state.session_factory() as db:
        assert db.get(AuthSession, token_digest(old)) is None


def test_disabled_user_cannot_login_or_use_existing_session(client):
    register_and_login(client)
    with client.app.state.session_factory() as db:
        user = db.scalar(select(User))
        user.is_active = False
        db.commit()
    assert client.get("/auth/me").status_code == 401
    response = client.post("/auth/login", json={"email": STUDENT["email"], "password": PASSWORD})
    assert response.status_code == 401


def test_user_without_local_password_cannot_login(client):
    with client.app.state.session_factory() as db:
        db.add(User(email=STUDENT["email"], full_name="TPU user", password_hash=None))
        db.commit()
    response = client.post("/auth/login", json={"email": STUDENT["email"], "password": PASSWORD})
    assert response.status_code == 401


def test_expired_session_is_rejected_and_removed(client):
    register_and_login(client)
    with client.app.state.session_factory() as db:
        session = db.scalar(select(AuthSession))
        session.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        db.commit()
    assert client.get("/auth/me").status_code == 401
    with client.app.state.session_factory() as db:
        assert db.scalar(select(AuthSession)) is None


def test_forged_cookie_is_rejected(client):
    client.cookies.set("fpga_session", "forged")
    assert client.get("/auth/me").status_code == 401


def test_logout_requires_csrf_and_keeps_session_on_failure(client):
    login = register_and_login(client)
    assert client.post("/auth/logout").status_code == 403
    assert client.post("/auth/logout", headers={"X-CSRF-Token": "wrong"}).status_code == 403
    assert client.get("/auth/me").status_code == 200
    assert (
        client.post(
            "/auth/logout",
            headers={
                "X-CSRF-Token": login.json()["csrf_token"],
                "Origin": "https://evil.example",
            },
        ).status_code
        == 403
    )
    assert client.get("/auth/me").status_code == 200


@pytest.mark.parametrize("endpoint", ["register", "login"])
def test_auth_mutations_reject_untrusted_origin(client, endpoint):
    response = client.post(
        f"/auth/{endpoint}",
        json=STUDENT,
        headers={
            "Origin": "https://evil.example",
        },
    )
    assert response.status_code == 403


def test_trusted_frontend_can_use_auth_and_logout(client):
    headers = {"Origin": "http://localhost:5173"}
    assert client.post("/auth/register", json=STUDENT, headers=headers).status_code == 201
    response = client.post(
        "/auth/login", json={"email": STUDENT["email"], "password": PASSWORD}, headers=headers
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == headers["Origin"]
    assert (
        client.post(
            "/auth/logout",
            headers={
                **headers,
                "X-CSRF-Token": response.json()["csrf_token"],
            },
        ).status_code
        == 204
    )


def test_user_and_session_survive_application_restart(settings):
    with TestClient(create_app(settings)) as first:
        login = register_and_login(first)
        token = first.cookies.get("fpga_session")
    with TestClient(create_app(settings)) as second:
        second.cookies.set("fpga_session", token)
        assert second.get("/auth/me").status_code == 200
        assert (
            second.post(
                "/auth/logout",
                headers={
                    "X-CSRF-Token": login.json()["csrf_token"],
                },
            ).status_code
            == 204
        )


def test_production_rejects_sqlite():
    with pytest.raises(ValidationError, match="SQLite is only available"):
        Settings(_env_file=None, app_env="production", database_url="sqlite:///./test.sqlite3")


def test_production_cookie_is_secure(client):
    from app.db.session import get_db

    assert client.post("/auth/register", json=STUDENT).status_code == 201
    settings = Settings(
        _env_file=None,
        app_env="production",
        database_url="postgresql+psycopg://test:test@127.0.0.1:65432/fpga_test",
    )
    application = create_app(settings)

    def local_db():
        with client.app.state.session_factory() as db:
            yield db

    application.dependency_overrides[get_db] = local_db
    with TestClient(application, base_url="https://api.example.com") as production:
        response = production.post(
            "/auth/login",
            json={
                "email": STUDENT["email"],
                "password": PASSWORD,
            },
        )
        assert response.status_code == 200
        assert "Secure" in response.headers["set-cookie"]
        assert "HttpOnly" in response.headers["set-cookie"]
        assert production.get("/auth/me").status_code == 200


def test_csrf_can_be_recovered_for_an_existing_session(client):
    login = register_and_login(client)
    response = client.get("/auth/csrf")
    assert response.status_code == 200
    assert response.json()["csrf_token"] == login.json()["csrf_token"]
    assert client.get("/auth/csrf").json() == response.json()
    assert client.get("/auth/csrf", headers={"Origin": "https://evil.example"}).status_code == 403
    assert (
        client.post(
            "/auth/logout",
            headers={
                "X-CSRF-Token": response.json()["csrf_token"],
            },
        ).status_code
        == 204
    )
    assert client.get("/auth/csrf").status_code == 401
