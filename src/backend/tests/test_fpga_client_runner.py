import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from booking_support import open_test_window
from fastapi.testclient import TestClient
from sqlalchemy import select

from app.core.config import Settings, get_settings
from app.db.session import create_database_engine
from app.integrations.fpga.client import DispatcherClient, DispatchError
from app.integrations.fpga.delivery import deliver_package, delivery_lock
from app.integrations.fpga.package import LabBindings, LabTarget, prepare_package
from app.integrations.fpga.runner import advance_run, main, sync_run
from app.integrations.fpga.worker import queue_step
from app.main import create_app
from app.modules.labs.seed import DEMO_LAB_ID, seed_demo
from app.modules.runs.models import Run
from app.modules.runs.schemas import ExecutorResult, ExecutorStatus
from app.modules.runs.service import configure_public_vectors
from app.modules.submissions.models import Submission

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux dispatcher host required")
FPGA = Path(__file__).resolve().parents[2] / "fpga"


@pytest.fixture
def jobs(tmp_path):
    path = tmp_path / "jobs with spaces"
    (path / "incoming").mkdir(parents=True)
    return path


def script(tmp_path, body):
    path = tmp_path / "dispatcher with spaces"
    path.write_text(f"#!{sys.executable}\n{body}\n")
    path.chmod(0o700)
    return path


@pytest.fixture
def saved(tmp_path):
    settings = Settings(_env_file=None, app_env="test", database_url=f"sqlite:///{tmp_path}/db")
    with TestClient(create_app(settings)) as http:
        with http.app.state.session_factory() as db:
            seed_demo(db)
        account = {
            "email": "runner@example.com",
            "full_name": "Student",
            "password": "Strong password 123",
        }
        assert http.post("/auth/register", json=account).status_code == 201
        login = http.post("/auth/login", json={k: account[k] for k in ("email", "password")}).json()
        open_test_window(http)
        response = http.post(
            f"/labs/{DEMO_LAB_ID}/submissions",
            headers={"X-CSRF-Token": login["csrf_token"]},
            json={"source_code": (FPGA / "examples/combinational/student_top.v").read_text()},
        )
        assert response.status_code == 201
        submission_id = response.json()["id"]
        with http.app.state.session_factory() as db:
            run_id = db.scalar(select(Run.id).where(Run.submission_id == UUID(submission_id)))
        bindings = LabBindings(
            schema_version=1,
            labs={DEMO_LAB_ID: LabTarget(kind="combinational", test_set="combinational-v1")},
        )
        yield (
            http,
            http.app.state.session_factory.kw["bind"],
            run_id,
            submission_id,
            bindings,
            settings,
        )


def starting(run_id, mode="hardware"):
    return ExecutorStatus(
        schema_version=1,
        run_id=run_id,
        mode=mode,
        state="starting",
        stage="dispatch",
        started_at=None,
        updated_at=datetime.now(timezone.utc),
        finished_at=None,
        result_status=None,
    )


def finished(run_id, mode="hardware"):
    now = datetime.now(timezone.utc)
    status = ExecutorStatus(
        schema_version=1,
        run_id=run_id,
        mode=mode,
        state="finished",
        stage="finalizing",
        started_at=now,
        updated_at=now,
        finished_at=now,
        result_status="passed",
    )
    result = ExecutorResult(
        schema_version=1,
        run_id=run_id,
        mode=mode,
        status="passed",
        hardware_verified=mode == "hardware",
        started_at=now,
        finished_at=now,
        summary={"planned": 0, "executed": 0, "passed": 0, "failed": 0},
        observations=[],
        error=None,
        logs=[],
    )
    return status, result


def test_submit_uses_literal_arguments_and_operator_environment(tmp_path, jobs, monkeypatch):
    path = script(
        tmp_path,
        """import json,os,sys
assert sys.argv[1:] == ['submit','--run-id',sys.argv[3],'--mode','hardware']
assert os.environ['FPGA_DISPATCH_LAUNCH'] == 'manual'
assert os.environ['FPGA_RUN_CONFIG'] == ''
assert os.environ['FPGA_JOBS_ROOT'].endswith('jobs with spaces')
print(json.dumps({'schema_version':1,'run_id':sys.argv[3],'disposition':'accepted'}))""",
    )
    monkeypatch.setenv("FPGA_RUN_CONFIG", "/unrelated/config")
    client = DispatcherClient(path, jobs, launch="manual")
    run_id = uuid4()
    assert client.submit(run_id, "hardware").run_id == run_id
    with pytest.raises(ValueError):
        client.submit("x;touch nope", "hardware")
    with pytest.raises(ValueError):
        client.submit(run_id, "hardware;echo nope")


@pytest.mark.parametrize(
    "body,match",
    [
        ("import time; time.sleep(10)", "timed out"),
        (
            "import sys; sys.stdout.close(); sys.stderr.close(); import time; time.sleep(10)",
            "timed out",
        ),
        ('import sys; sys.stderr.write("secret path"); sys.exit(2)', "exit code 2"),
        ('print("not json")', "invalid JSON"),
        ('print("[]")', "JSON object"),
        ('import sys; sys.stderr.write("x" * (4*1024*1024+1))', "exceeds"),
    ],
)
def test_process_failures_are_bounded_and_do_not_leak_stderr(tmp_path, jobs, body, match):
    client = DispatcherClient(script(tmp_path, body), jobs, timeout_seconds=0.2)
    with pytest.raises(DispatchError, match=match) as exc:
        client.submit(uuid4(), "hardware")
    assert "secret path" not in str(exc.value)


def test_response_identity_is_checked(tmp_path, jobs):
    other_id = uuid4()
    receipt = {"schema_version": 1, "run_id": str(other_id), "disposition": "accepted"}
    path = script(tmp_path, f"print({json.dumps(receipt)!r})")
    with pytest.raises(DispatchError, match="different run ID"):
        DispatcherClient(path, jobs).submit(uuid4(), "hardware")


@pytest.mark.parametrize("unsafe", ["runs", "run", "output", "result"])
def test_result_symlinks_are_rejected(tmp_path, jobs, unsafe):
    run_id = uuid4()
    output = jobs / "runs" / str(run_id) / "output"
    output.mkdir(parents=True)
    _, result = finished(run_id)
    file = output / "result.json"
    file.write_text(result.model_dump_json())
    target = {"runs": jobs / "runs", "run": output.parent, "output": output, "result": file}[unsafe]
    moved = tmp_path / "outside"
    target.rename(moved)
    target.symlink_to(moved, target_is_directory=unsafe != "result")
    client = DispatcherClient(script(tmp_path, "pass"), jobs)
    with pytest.raises((ValueError, OSError)):
        client.result(run_id, "hardware")


class FakeDispatcher:
    def __init__(self, jobs, run_id):
        self.jobs_root = jobs
        self.snapshot = starting(run_id)
        self.report = None
        self.submits = 0
        self.lose_ack = False

    def submit(self, run_id, mode, *, cutoff_us=None):
        self.submits += 1
        run = self.jobs_root / "runs" / str(run_id)
        run.mkdir(exist_ok=True)
        if self.lose_ack:
            self.lose_ack = False
            raise DispatchError("Lost acknowledgement")

    def status(self, run_id, mode):
        return self.snapshot

    def result(self, run_id, mode):
        if self.report is None:
            raise FileNotFoundError("Result not published yet")
        return self.report


def test_resume_after_lost_ack_and_final_result_is_immutable(saved, jobs):
    http, engine, run_id, submission_id, bindings, _ = saved
    client = FakeDispatcher(jobs, run_id)
    client.lose_ack = True
    with pytest.raises(DispatchError):
        advance_run(engine, client, bindings, run_id)
    assert http.get(f"/submissions/{submission_id}/run").json()["state"] == "queued"
    assert advance_run(engine, client, bindings, run_id) == "running"
    assert client.submits == 2
    client.snapshot, client.report = finished(run_id)
    assert advance_run(engine, client, bindings, run_id) == "finished"
    client.report = None
    assert advance_run(engine, client, bindings, run_id) == "finished"
    assert client.submits == 2
    assert http.get(f"/submissions/{submission_id}/run").json()["result_status"] == "passed"


def test_missing_result_and_wrong_identity_do_not_replace_saved_status(saved, jobs):
    http, engine, run_id, submission_id, bindings, _ = saved
    client = FakeDispatcher(jobs, run_id)
    advance_run(engine, client, bindings, run_id)
    client.snapshot, report = finished(run_id)
    with pytest.raises(FileNotFoundError):
        advance_run(engine, client, bindings, run_id)
    assert http.get(f"/submissions/{submission_id}/run").json()["state"] == "running"
    client.report = report.model_copy(update={"run_id": uuid4()})
    with pytest.raises(ValueError):
        advance_run(engine, client, bindings, run_id)
    assert http.get(f"/submissions/{submission_id}/run").json()["state"] == "running"


def test_unconfigured_lab_is_not_sent_and_visibility_cannot_change_after_start(saved, jobs):
    _, engine, run_id, _, bindings, _ = saved
    client = FakeDispatcher(jobs, run_id)
    with pytest.raises(ValueError):
        advance_run(engine, client, LabBindings(schema_version=1, labs={}), run_id)
    assert client.submits == 0
    advance_run(engine, client, bindings, run_id, [0])
    with pytest.raises(ValueError):
        advance_run(engine, client, bindings, run_id, [1])
    assert client.submits == 1


@pytest.mark.skipif(not shutil.which("jq"), reason="jq required")
def test_real_mock_dispatcher_to_database_to_owned_http_result(saved, jobs):
    http, engine, run_id, submission_id, bindings, _ = saved
    with http.app.state.session_factory() as db:
        package = prepare_package(db, run_id, bindings)
        run = db.get(Run, run_id)
        run.mode = "mock"
        configure_public_vectors(db, run_id, [0])
        db.commit()
    endpoint = f"/submissions/{submission_id}/run"
    assert http.get(endpoint).json()["state"] == "queued"
    deliver_package(package, jobs)
    client = DispatcherClient(FPGA / "bin/fpga-dispatch", jobs, launch="manual")
    assert client.submit(run_id, "mock").disposition == "accepted"
    assert client.submit(run_id, "mock").disposition == "existing"
    assert sync_run(engine, client, run_id) == "running"
    assert http.get(endpoint).json()["stage"] == "dispatch"
    run_path = jobs / "runs" / str(run_id)
    subprocess.run(
        [
            str(FPGA / "bin/fpga-run"),
            "--job",
            str(run_path / "input"),
            "--output",
            str(run_path / "output"),
            "--mode",
            "mock",
        ],
        env=client.environment,
        check=True,
        capture_output=True,
        timeout=30,
    )
    assert sync_run(engine, client, run_id) == "finished"
    response = http.get(endpoint)
    data = response.json()
    assert data["result_status"] == "passed" and data["hardware_verified"] is False
    assert data["mode"] == "mock"
    assert data["summary"]["executed"] > 0
    assert [item["vector_index"] for item in data["tests"]] == [0]
    assert "logs" not in data and str(jobs) not in response.text
    # The operator calls cleanup only after the backend has saved the result.
    cleanup = subprocess.run(
        [str(client.executable), "cleanup", "--run-id", str(run_id)],
        env=client.environment,
        check=True,
        capture_output=True,
        timeout=30,
    )
    assert json.loads(cleanup.stdout) == {
        "schema_version": 1,
        "run_id": str(run_id),
        "state": "cleaned",
    }
    assert not (run_path / "output").exists()
    assert client.submit(run_id, "mock").disposition == "existing"
    assert advance_run(engine, client, bindings, run_id, [0]) == "finished"
    assert http.get(endpoint).json() == data
    account = {
        "email": "other@example.com",
        "full_name": "Other",
        "password": "Strong password 456",
    }
    http.post("/auth/register", json=account)
    http.post("/auth/login", json={k: account[k] for k in ("email", "password")})
    assert http.get(endpoint).status_code == 404


@pytest.mark.skipif(
    not (shutil.which("jq") and shutil.which("iverilog")), reason="jq and Icarus Verilog required"
)
def test_invalid_hdl_reaches_a_terminal_result_in_the_owned_api(saved, jobs):
    http, engine, run_id, submission_id, bindings, _ = saved
    with http.app.state.session_factory() as db:
        db.get(Submission, UUID(submission_id)).source_code = "module student_top;"
        db.commit()

    client = DispatcherClient(FPGA / "bin/fpga-dispatch", jobs)
    assert advance_run(engine, client, bindings, run_id, [0]) == "finished"
    assert advance_run(engine, client, bindings, run_id, [0]) == "finished"
    response = http.get(f"/submissions/{submission_id}/run")
    assert response.status_code == 200
    data = response.json()
    assert data["state"] == "finished"
    assert data["result_status"] == "invalid_input"
    assert data["hardware_verified"] is False
    assert data["tests"] == []


def test_cli_once_persists_starting_snapshot(saved, jobs, tmp_path, monkeypatch):
    http, _, run_id, submission_id, bindings, settings = saved
    state = starting(run_id).model_dump(mode="json")
    code = f"""import sys,json
if sys.argv[1] == 'submit':
 print(json.dumps({{'schema_version':1,'run_id':sys.argv[3],'disposition':'accepted'}}))
else:
 print({json.dumps(state)!r})"""
    path = script(tmp_path, code)
    config = tmp_path / "bindings.json"
    config.write_text(bindings.model_dump_json())
    monkeypatch.setenv("DATABASE_URL", settings.database_url)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "runner",
            "--run-id",
            str(run_id),
            "--bindings",
            str(config),
            "--jobs-root",
            str(jobs),
            "--dispatcher",
            str(path),
            "--once",
        ],
    )
    get_settings.cache_clear()
    try:
        assert main() == 0
    finally:
        get_settings.cache_clear()
    assert http.get(f"/submissions/{submission_id}/run").json()["state"] == "running"


def test_queue_resumes_first_submission_before_dispatching_second(saved, jobs):
    http, engine, first, _, bindings, settings = saved
    login = http.post(
        "/auth/login", json={"email": "runner@example.com", "password": "Strong password 123"}
    ).json()
    new_submission = http.post(
        f"/labs/{DEMO_LAB_ID}/submissions",
        headers={"X-CSRF-Token": login["csrf_token"]},
        json={"source_code": "module next; endmodule"},
    )
    assert new_submission.status_code == 201
    second = UUID(http.get(f"/submissions/{new_submission.json()['id']}/run").json()["run_id"])
    client = FakeDispatcher(jobs, first)
    with delivery_lock(jobs / ".backend-queue.lock", 0), pytest.raises(TimeoutError):
        queue_step(engine, client, bindings)
    assert client.submits == 0
    client.lose_ack = True
    with pytest.raises(DispatchError):
        queue_step(engine, client, bindings)
    restarted = create_database_engine(settings)
    try:
        assert not (jobs / "runs" / str(second)).exists()
        assert queue_step(restarted, client, bindings) == (first, "running")
        assert queue_step(restarted, client, bindings) == (first, "running")
        client.snapshot, client.report = finished(first)
        assert queue_step(restarted, client, bindings) == (first, "finished")
        assert not (jobs / "runs" / str(second)).exists()
        client.snapshot, client.report = finished(second)
        assert queue_step(restarted, client, bindings) == (second, "finished")
        assert queue_step(restarted, client, bindings) is None
        assert client.submits == 3  # Includes the idempotent retry after the lost receipt.
    finally:
        restarted.dispose()


@pytest.mark.parametrize("already_admitted", [False, True])
def test_window_end_drops_waiter_but_recovers_accepted_run(saved, jobs, already_admitted):
    from datetime import timedelta

    from app.modules.bookings.models import Booking

    http, engine, run_id, submission, bindings, _ = saved
    client = FakeDispatcher(jobs, run_id)
    if already_admitted:
        client.lose_ack = True
        with pytest.raises(DispatchError):
            advance_run(engine, client, bindings, run_id)
        client.snapshot, client.report = finished(run_id)
    with http.app.state.session_factory() as db, db.begin():
        booking = db.scalar(select(Booking))
        booking.starts_at -= timedelta(hours=1)
        booking.ends_at -= timedelta(hours=1)
    assert queue_step(engine, client, bindings) == (run_id, "finished")
    data = http.get(f"/submissions/{submission}/run").json()
    assert data["result_status"] == ("passed" if already_admitted else "window_closed")
    assert data["hardware_verified"] == already_admitted
    assert client.submits == int(already_admitted)
    assert queue_step(engine, client, bindings) is None


def test_live_logs_owned_bounded_and_retained_after_cleanup(saved, jobs):
    http, engine, run_id, submission, bindings, _ = saved
    path = f"/submissions/{submission}/logs"
    client = FakeDispatcher(jobs, run_id)
    assert http.get(path).json()["build"] is None
    advance_run(engine, client, bindings, run_id)
    logdir = jobs / "runs" / str(run_id) / "output" / "logs"
    logdir.mkdir(parents=True)
    (logdir / "build.log").write_text("old line\n" * 4000 + "Error at /srv/private/top.v:4\n")
    (logdir / "program.log").symlink_to(logdir / "build.log")
    advance_run(engine, client, bindings, run_id)
    data = http.get(path).json()
    assert data["build"].startswith("[…]") and "Error at [path]" in data["build"]
    assert len(data["build"]) < 17000 and "/srv/" not in data["build"] and data["program"] is None
    (logdir / "program.log").unlink()
    (logdir / "program.log").write_text("Programming done\n")
    client.snapshot, client.report = finished(run_id)
    advance_run(engine, client, bindings, run_id)
    shutil.rmtree(logdir)
    assert http.get(path).json()["program"] == "Programming done\n"
    account = {"email": "peer@example.com", "full_name": "Peer", "password": "Strong password 456"}
    http.post("/auth/register", json=account)
    http.post("/auth/login", json={k: account[k] for k in ("email", "password")})
    assert http.get(path).status_code == 404
