from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from fastapi.testclient import TestClient
from sqlalchemy import func, inspect, select, text
from sqlalchemy.orm import Session
from sqlalchemy.orm.exc import StaleDataError

from app.core.config import Settings
from app.db.base import Base
from app.db.session import create_database_engine
from app.main import create_app
from app.modules.auth.models import AuthSession
from app.modules.labs.seed import DEMO_LAB_ID, seed_demo
from app.modules.runs.models import Run
from app.modules.runs.service import configure_public_vectors, enqueue, record_executor_snapshot
from app.modules.runs.sync import main as sync_main
from app.modules.submissions.models import Submission
from app.modules.users.models import User

ACCOUNT = {"email": "run@example.com", "full_name": "Иван", "password": "Strong demo password 123"}
T0 = datetime(2026, 11, 13, 8, 0, tzinfo=timezone.utc)


@pytest.fixture
def settings(tmp_path):
    return Settings(_env_file=None, app_env="test", database_url=f"sqlite:///{tmp_path}/run.db")


@pytest.fixture
def client(settings):
    with TestClient(create_app(settings)) as client:
        with client.app.state.session_factory() as db:
            seed_demo(db)
        yield client


def sign_in(client, account=ACCOUNT):
    assert client.post("/auth/register", json=account).status_code == 201
    return client.post(
        "/auth/login", json={key: account[key] for key in ("email", "password")}
    ).json()


@pytest.fixture
def submission(client):
    login = sign_in(client)
    response = client.post(
        f"/labs/{DEMO_LAB_ID}/submissions",
        headers={"X-CSRF-Token": login["csrf_token"]},
        json={"source_code": "module student_top; endmodule"},
    )
    assert response.status_code == 201
    return response.json()["id"]


def endpoint(submission):
    return f"/submissions/{submission}/run"


def status(run_id, state="running", outcome=None, mode="hardware"):
    return {
        "schema_version": 1,
        "run_id": str(run_id),
        "mode": mode,
        "state": state,
        "stage": "finalizing" if state == "finished" else "testing",
        "started_at": T0.isoformat(),
        "updated_at": (T0 + timedelta(seconds=5 if state == "finished" else 1)).isoformat(),
        "finished_at": (T0 + timedelta(seconds=5)).isoformat() if state == "finished" else None,
        "result_status": outcome,
    }


def result(run_id, mode="hardware", outcome="passed"):
    return {
        "schema_version": 1,
        "run_id": str(run_id),
        "mode": mode,
        "status": outcome,
        "hardware_verified": mode == "hardware",
        "started_at": T0.isoformat(),
        "finished_at": (T0 + timedelta(seconds=5)).isoformat(),
        "summary": {"planned": 2, "executed": 2, "passed": 2, "failed": 0},
        "observations": [
            {
                "vector_index": 0,
                "din": "0x3e5",
                "steps": 0,
                "dout": "0x03039",
                "expected_dout": "0x03039",
                "mask": "0x3ffff",
                "match": True,
            },
            {
                "vector_index": 1,
                "din": "0x003",
                "steps": 0,
                "dout": "0x00001",
                "expected_dout": "0x00001",
                "mask": "0x3ffff",
                "match": True,
            },
        ],
        "error": None,
        "logs": ["logs/private-build-path.log"],
    }


def ingest(client, run_id, status_data, result_data=None):
    with client.app.state.session_factory() as db:
        changed = record_executor_snapshot(db, UUID(str(run_id)), status_data, result_data)
        db.commit()
        return changed


def test_submission_queues_atomically_and_get_is_read_only(client, submission):
    response = client.get(endpoint(submission))
    data = response.json()
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert data["state"] == "queued" and data["stage"] is None
    assert data["mode"] == "hardware" and data["hardware_verified"] is False
    assert data["result_status"] is None and data["summary"] is None
    assert data["tests"] == [] and data["poll_after_seconds"] == 3
    assert data["elapsed_seconds"] == 0 and data["started_at"] is None
    assert data["queued_at"].endswith("Z")
    assert client.get(endpoint(submission)).json() == data
    with client.app.state.session_factory() as db:
        assert db.scalar(select(func.count()).select_from(Run)) == 1


@pytest.mark.parametrize("role", ["student", "teacher"])
def test_status_is_private_and_no_public_write_route_exists(client, submission, role):
    client.cookies.clear()
    sign_in(client, {**ACCOUNT, "email": "outsider@example.com"})
    with client.app.state.session_factory() as db:
        db.scalar(select(User).where(User.email == "outsider@example.com")).role = role
        db.commit()
    foreign = client.get(endpoint(submission))
    missing = client.get(endpoint(uuid4()))
    assert foreign.status_code == missing.status_code == 404
    assert foreign.json() == missing.json()
    assert foreign.headers["cache-control"] == "no-store"
    assert client.post(endpoint(submission), json={"state": "finished"}).status_code == 405


@pytest.mark.parametrize("state", ["anonymous", "forged", "expired", "inactive"])
def test_status_rejects_invalid_sessions(client, submission, state):
    if state in ("anonymous", "forged"):
        client.cookies.clear()
        if state == "forged":
            client.cookies.set("fpga_session", "forged")
    else:
        with client.app.state.session_factory() as db:
            if state == "expired":
                db.scalar(select(AuthSession)).expires_at = datetime.now(timezone.utc) - timedelta(
                    1
                )
            else:
                db.scalar(select(User)).is_active = False
            db.commit()
    response = client.get(endpoint(submission))
    assert response.status_code == 401
    assert response.headers["cache-control"] == "no-store"


def test_running_then_finished_filters_private_observations(client, submission):
    run_id = client.get(endpoint(submission)).json()["run_id"]
    with client.app.state.session_factory() as db:
        db.get(Run, UUID(run_id)).public_vector_indices = [1]
        db.commit()
    ingest(client, run_id, status(run_id))
    running = client.get(endpoint(submission)).json()
    assert running["state"] == "running" and running["stage"] == "testing"
    assert running["hardware_verified"] is False and running["tests"] == []
    report = result(run_id)
    finished = status(run_id, "finished", "passed")
    assert ingest(client, run_id, finished, report) is True
    assert ingest(client, run_id, finished, report) is False
    response = client.get(endpoint(submission))
    data = response.json()
    assert data["state"] == "finished" and data["result_status"] == "passed"
    assert data["hardware_verified"] is True and data["poll_after_seconds"] is None
    assert data["elapsed_seconds"] == 5
    assert data["tests"] == [report["observations"][1]]
    assert data["summary"] == report["summary"]
    assert "0x03039" not in response.text and "private-build-path" not in response.text
    assert "logs" not in data and "result_snapshot" not in data
    with client.app.state.session_factory() as db:
        assert len(db.get(Run, UUID(run_id)).result_snapshot["observations"]) == 2


def test_latest_attempt_and_mock_never_claims_hardware(client, submission):
    with client.app.state.session_factory() as db:
        first = db.scalar(select(Run))
        first.created_at = datetime.now(timezone.utc) - timedelta(seconds=10)
        second = enqueue(db, UUID(submission), mode="mock", public_vector_indices=(1,))
        db.commit()
        run_id = second.id
    ingest(client, run_id, status(run_id, "finished", "passed", "mock"), result(run_id, "mock"))
    data = client.get(endpoint(submission)).json()
    assert data["run_id"] == str(run_id) and data["mode"] == "mock"
    assert data["hardware_verified"] is False


@pytest.mark.parametrize(
    "outcome", ["build_error", "board_error", "invalid_input", "busy", "internal_error"]
)
def test_executor_errors_do_not_expose_raw_messages_or_paths(client, submission, outcome):
    run_id = client.get(endpoint(submission)).json()["run_id"]
    report = result(run_id, outcome=outcome)
    report.update(
        hardware_verified=False,
        observations=[],
        summary={"planned": 2, "executed": 0, "passed": 0, "failed": 0},
        error={"stage": "building", "code": "private_secret", "message": "/home/private/secret"},
    )
    ingest(client, run_id, status(run_id, "finished", outcome), report)
    response = client.get(endpoint(submission))
    assert response.json()["error"]["code"] == outcome
    assert response.json()["hardware_verified"] is False
    assert "private" not in response.text and "secret" not in response.text


def test_mismatch_can_be_hardware_verified(client, submission):
    run_id = client.get(endpoint(submission)).json()["run_id"]
    report = result(run_id, outcome="mismatch")
    report["observations"][0].update(dout="0x00000", match=False)
    report["summary"].update(passed=1, failed=1)
    ingest(client, run_id, status(run_id, "finished", "mismatch"), report)
    data = client.get(endpoint(submission)).json()
    assert data["hardware_verified"] is True and data["result_status"] == "mismatch"
    assert data["tests"] == []


@pytest.mark.parametrize(
    "invalid",
    [
        "missing_result",
        "wrong_id",
        "wrong_mode",
        "wrong_status",
        "counts",
        "fake_match",
        "fake_hardware",
        "naive_time",
    ],
)
def test_invalid_executor_snapshot_does_not_change_saved_state(client, submission, invalid):
    run_id = client.get(endpoint(submission)).json()["run_id"]
    current = status(run_id)
    ingest(client, run_id, current)
    next_status, report = status(run_id, "finished", "passed"), result(run_id)
    if invalid == "missing_result":
        report = None
    elif invalid == "wrong_id":
        report["run_id"] = str(uuid4())
    elif invalid == "wrong_mode":
        next_status["mode"] = "mock"
    elif invalid == "wrong_status":
        next_status["result_status"] = "board_error"
    elif invalid == "counts":
        report["summary"]["executed"] = 1
    elif invalid == "fake_match":
        report["observations"][0]["match"] = False
    elif invalid == "fake_hardware":
        report["mode"] = "mock"
    else:
        next_status["updated_at"] = "2026-11-13T08:00:05"
    with pytest.raises(ValueError):
        ingest(client, run_id, next_status, report)
    with client.app.state.session_factory() as db:
        assert db.get(Run, UUID(run_id)).status_snapshot["state"] == "running"
        assert db.get(Run, UUID(run_id)).result_snapshot is None


def test_stale_updates_and_finished_rewrites_are_rejected(client, submission):
    run_id = client.get(endpoint(submission)).json()["run_id"]
    current = status(run_id)
    ingest(client, run_id, current)
    stale = deepcopy(current)
    stale["updated_at"] = T0.isoformat()
    with pytest.raises(ValueError, match="Stale"):
        ingest(client, run_id, stale)
    ingest(client, run_id, status(run_id, "finished", "passed"), result(run_id))
    with pytest.raises(ValueError, match="immutable"):
        ingest(client, run_id, current)


def test_optimistic_lock_prevents_a_stale_worker_overwriting_a_result(client, submission):
    run_id = UUID(client.get(endpoint(submission)).json()["run_id"])
    with client.app.state.session_factory() as first, client.app.state.session_factory() as second:
        first_run, second_run = first.get(Run, run_id), second.get(Run, run_id)
        first_run.status_snapshot = status(run_id)
        first.commit()
        second_run.status_snapshot = status(run_id, "finished", "passed")
        with pytest.raises(StaleDataError):
            second.commit()


def test_cli_import_and_restart_preserve_status(
    settings, client, submission, tmp_path, monkeypatch
):
    import json

    from app.core.config import get_settings

    run_id = client.get(endpoint(submission)).json()["run_id"]
    path = tmp_path / "status.json"
    path.write_text(json.dumps(status(run_id)))
    monkeypatch.setattr("sys.argv", ["sync", "--run-id", run_id, "--status", str(path)])
    monkeypatch.setenv("DATABASE_URL", settings.database_url)
    get_settings.cache_clear()
    try:
        sync_main()
    finally:
        get_settings.cache_clear()
    token = client.cookies.get("fpga_session")
    with TestClient(create_app(settings)) as reopened:
        reopened.cookies.set("fpga_session", token)
        assert reopened.get(endpoint(submission)).json()["state"] == "running"


@pytest.mark.parametrize(
    "group,expected", [(None, None), ("", None), ("  ", None), (" 8К51Т13 ", "8К51Т13")]
)
def test_group_is_separate_in_registration_login_and_me(client, group, expected):
    login = sign_in(client, {**ACCOUNT, "group": group})
    assert login["user"]["group"] == expected
    assert client.get("/auth/me").json()["group"] == expected
    assert client.get("/auth/me").json()["full_name"] == ACCOUNT["full_name"]


def test_existing_user_can_set_and_clear_group_with_csrf(client):
    login = sign_in(client)
    assert login["user"]["group"] is None
    assert client.patch("/auth/me", json={"group": "8К51Т13"}).status_code == 403
    headers = {"X-CSRF-Token": login["csrf_token"]}
    assert (
        client.patch("/auth/me", headers=headers, json={"group": "8К51Т13"}).json()["group"]
        == "8К51Т13"
    )
    assert client.patch("/auth/me", headers=headers, json={"group": None}).json()["group"] is None
    assert (
        client.patch(
            "/auth/me", headers=headers, json={"group": "8", "role": "teacher"}
        ).status_code
        == 422
    )
    with client.app.state.session_factory() as db:
        db.scalar(select(User)).role = "teacher"
        db.commit()
    assert client.get("/auth/me").json()["group"] is None
    assert client.patch("/auth/me", headers=headers, json={"group": "8"}).status_code == 403


@pytest.mark.parametrize("group", ["x" * 33, 123, [], "8\n13", "\x00"])
def test_invalid_groups_are_rejected(client, group):
    assert client.post("/auth/register", json={**ACCOUNT, "group": group}).status_code == 422


def test_configured_lan_origin_can_login_and_unlisted_origin_is_rejected(settings):
    settings.cors_origins = ["http://192.168.1.50:5173"]
    with TestClient(create_app(settings)) as client:
        origin = {"Origin": settings.cors_origins[0]}
        assert client.post("/auth/register", headers=origin, json=ACCOUNT).status_code == 201
        credentials = {key: ACCOUNT[key] for key in ("email", "password")}
        login = client.post("/auth/login", headers=origin, json=credentials)
        assert login.status_code == 200
        assert login.headers["access-control-allow-origin"] == origin["Origin"]
        assert (
            client.post(
                "/auth/login", headers={"Origin": "http://192.168.1.51:5173"}, json=credentials
            ).status_code
            == 403
        )


def test_upgrade_preserves_existing_data_and_does_not_invent_old_runs(settings):
    engine = create_database_engine(settings)
    config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
    user_id, lab_id, submission_id = uuid4(), uuid4(), uuid4()
    try:
        with engine.begin() as connection:
            config.attributes["connection"] = connection
            command.upgrade(config, "0004_create_submissions")
            connection.execute(
                text("INSERT INTO users (id, email, full_name) VALUES (:id, :email, :name)"),
                {"id": user_id.hex, "email": "old@example.com", "name": "Old"},
            )
            connection.execute(
                text(
                    "INSERT INTO labs (id,title,description,statement,template,"
                    "interface_description,kind,is_published,is_demo) "
                    "VALUES (:id,'Old','','','','','combinational',1,0)"
                ),
                {"id": lab_id.hex},
            )
            connection.execute(
                text(
                    "INSERT INTO submissions (id,user_id,lab_id,source_code) "
                    "VALUES (:id,:user,:lab,'module old; endmodule')"
                ),
                {"id": submission_id.hex, "user": user_id.hex, "lab": lab_id.hex},
            )
            command.upgrade(config, "head")
            assert compare_metadata(MigrationContext.configure(connection), Base.metadata) == []
            assert connection.scalar(select(User.group)) is None
            assert connection.scalar(select(Submission.id)) == submission_id
            assert connection.scalar(select(func.count()).select_from(Run)) == 0
            command.downgrade(config, "0004_create_submissions")
            assert "runs" not in inspect(connection).get_table_names()
            assert connection.scalar(select(Submission.id)) == submission_id
            command.upgrade(config, "head")
        from app.modules.runs.service import get_run

        with Session(engine) as db:
            assert get_run(db, user_id, submission_id).state == "not_started"
    finally:
        engine.dispose()


def test_transitions_in_one_second_and_visibility_freeze(client, submission):
    run_id = UUID(client.get(endpoint(submission)).json()["run_id"])
    with client.app.state.session_factory() as db, db.begin():
        configure_public_vectors(db, run_id, [1])
    initial = status(run_id)
    initial.update(state="starting", stage="dispatch", started_at=None)
    ingest(client, run_id, initial)
    active = status(run_id)
    active["stage"] = "building"
    ingest(client, run_id, active)
    ingest(client, run_id, status(run_id))
    with pytest.raises(ValueError, match="Conflicting"):
        ingest(client, run_id, active)
    with client.app.state.session_factory() as db, db.begin():
        configure_public_vectors(db, run_id, [1])
        with pytest.raises(ValueError, match="visibility"):
            configure_public_vectors(db, run_id, [0, 1])
    final, report = status(run_id, "finished", "passed"), result(run_id)
    final["updated_at"] = final["finished_at"] = report["finished_at"] = active["updated_at"]
    ingest(client, run_id, final, report)
    assert client.get(endpoint(submission)).json()["state"] == "finished"
