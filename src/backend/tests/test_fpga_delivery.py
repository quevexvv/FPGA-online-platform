import json
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.integrations.fpga.delivery import (
    AlreadyRegisteredError,
    DeliveryConflictError,
    deliver_package,
)
from app.integrations.fpga.package import JobPackage
from app.main import create_app
from app.modules.labs.models import Lab
from app.modules.runs.models import Run
from app.modules.submissions.models import Submission
from app.modules.users.models import User

pytestmark = pytest.mark.skipif(sys.platform != "linux", reason="Linux dispatcher host required")


@pytest.fixture
def package():
    run_id = uuid4()
    return JobPackage(
        run_id,
        {
            "schema_version": 1,
            "run_id": str(run_id),
            "top": "student_top",
            "kind": "sequential",
            "sources": ["src/student_top.v"],
            "test_set": "counter-v1",
        },
        "module student_top;\r\n// Исходник\r\nendmodule\r\n".encode(),
    )


@pytest.fixture
def jobs(tmp_path):
    root = tmp_path / "jobs"
    (root / "incoming").mkdir(parents=True)
    return root


def test_repeat_delivery_keeps_exact_source_and_existing_upload(package, jobs):
    receipt = deliver_package(package, jobs)
    source = receipt.path / "src/student_top.v"
    original_inode = source.stat().st_ino
    assert receipt.disposition == "uploaded"
    assert source.read_bytes() == package.source
    assert json.loads((receipt.path / "manifest.json").read_text()) == package.manifest
    assert deliver_package(package, jobs).disposition == "existing_upload"
    assert source.stat().st_ino == original_inode
    assert not (jobs / "runs" / str(package.run_id)).exists()
    assert not list((jobs / "incoming").glob(".upload-*"))


@pytest.mark.parametrize("change", ["source", "manifest", "extra_file", "source_link"])
def test_conflicting_upload_is_not_overwritten(package, jobs, tmp_path, change):
    path = deliver_package(package, jobs).path
    source = path / "src/student_top.v"
    if change == "source":
        source.write_bytes(b"different student code")
    elif change == "manifest":
        manifest = package.manifest | {"test_set": "other-v1"}
        (path / "manifest.json").write_text(json.dumps(manifest))
    elif change == "extra_file":
        (path / "extra").write_text("keep")
    else:
        outside = tmp_path / "outside.v"
        outside.write_bytes(package.source)
        source.unlink()
        source.symlink_to(outside)
    before = source.read_bytes()
    with pytest.raises(DeliveryConflictError):
        deliver_package(package, jobs)
    assert source.read_bytes() == before


@pytest.mark.parametrize("registered", ["run", "pending", "run_link"])
def test_registered_or_interrupted_run_is_never_reuploaded(package, jobs, tmp_path, registered):
    runs = jobs / "runs"
    runs.mkdir()
    path = runs / (f".{package.run_id}.pending" if registered == "pending" else str(package.run_id))
    if registered == "run_link":
        path.symlink_to(tmp_path / "missing")
    else:
        path.mkdir()
    with pytest.raises(AlreadyRegisteredError):
        deliver_package(package, jobs)
    assert not (jobs / "incoming" / str(package.run_id)).exists()


@pytest.mark.parametrize("target", ["root", "incoming", "runs", "locks", "upload", "lock"])
def test_symlinks_are_not_followed(package, jobs, tmp_path, target):
    outside = tmp_path / "outside"
    outside.mkdir()
    marker = outside / "keep"
    marker.write_text("unchanged")
    (jobs / "runs/.locks").mkdir(parents=True)
    paths = {
        "root": jobs,
        "incoming": jobs / "incoming",
        "runs": jobs / "runs",
        "locks": jobs / "runs/.locks",
        "upload": jobs / "incoming" / str(package.run_id),
        "lock": jobs / "runs/.locks" / str(package.run_id),
    }
    path = paths[target]
    if path.is_dir():
        shutil.rmtree(path)
    path.symlink_to(marker if target == "lock" else outside)
    with pytest.raises((ValueError, OSError)):
        deliver_package(package, jobs)
    assert marker.read_text() == "unchanged"
    assert list(outside.iterdir()) == [marker]


def test_partial_package_is_not_visible_under_run_id(package, jobs, monkeypatch):
    from app.integrations.fpga import delivery

    export = delivery.export_package
    destination = jobs / "incoming" / str(package.run_id)

    def observe(package, staging):
        assert not destination.exists()
        path = export(package, staging)
        assert not destination.exists()
        return path

    monkeypatch.setattr(delivery, "export_package", observe)
    deliver_package(package, jobs)
    assert (destination / "manifest.json").is_file()
    assert (destination / "src/student_top.v").is_file()


def test_write_error_removes_only_private_incomplete_upload(package, jobs, monkeypatch):
    keep = jobs / "incoming/keep"
    keep.write_text("another job")

    def fail(*args, **kwargs):
        raise OSError("disk full")

    monkeypatch.setattr("app.integrations.fpga.package.json.dump", fail)
    with pytest.raises(OSError, match="disk full"):
        deliver_package(package, jobs)
    assert list((jobs / "incoming").iterdir()) == [keep]


def test_concurrent_delivery_publishes_once(package, jobs):
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(deliver_package, package, jobs) for _ in range(2)]
        results = [future.result(timeout=10) for future in futures]
    assert sorted(result.disposition for result in results) == ["existing_upload", "uploaded"]
    assert len(list((jobs / "incoming").iterdir())) == 1


def test_uses_dispatcher_lock_and_times_out(package, jobs):
    import fcntl

    locks = jobs / "runs/.locks"
    locks.mkdir(parents=True)
    with (locks / str(package.run_id)).open("ab") as held:
        fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with pytest.raises(TimeoutError, match="lock is busy"):
            deliver_package(package, jobs, timeout_seconds=0.05)
    assert not list((jobs / "incoming").iterdir())
    assert deliver_package(package, jobs).disposition == "uploaded"


@pytest.mark.parametrize("timeout", [0, -1, float("inf"), float("nan"), 301])
def test_invalid_timeout_is_rejected_before_writing(package, jobs, timeout):
    with pytest.raises(ValueError, match="timeout"):
        deliver_package(package, jobs, timeout_seconds=timeout)
    assert not (jobs / "runs").exists()


def test_mismatched_id_is_rejected_before_writing(package, jobs):
    invalid = replace(package, manifest=package.manifest | {"run_id": str(uuid4())})
    with pytest.raises(ValueError, match="run ID"):
        deliver_package(invalid, jobs)
    assert not (jobs / "runs").exists()


@pytest.mark.skipif(not shutil.which("jq"), reason="jq required")
def test_delivered_package_is_accepted_once_by_actual_dispatcher(package, jobs):
    deliver_package(package, jobs)
    dispatcher = Path(__file__).resolve().parents[2] / "fpga/bin/fpga-dispatch"
    env = {**os.environ, "FPGA_JOBS_ROOT": str(jobs), "FPGA_DISPATCH_LAUNCH": "manual"}
    args = [str(dispatcher), "submit", "--run-id", str(package.run_id), "--mode", "mock"]
    first = subprocess.run(args, env=env, check=True, capture_output=True, text=True, timeout=15)
    assert json.loads(first.stdout)["disposition"] == "accepted"
    with pytest.raises(AlreadyRegisteredError):
        deliver_package(package, jobs)
    second = subprocess.run(args, env=env, check=True, capture_output=True, text=True, timeout=15)
    assert json.loads(second.stdout)["disposition"] == "existing"
    state = json.loads((jobs / "runs" / str(package.run_id) / "output/status.json").read_text())
    assert state["mode"] == "mock" and state["state"] == "starting"


def test_cli_delivers_saved_solution_without_starting_or_changing_run(jobs, tmp_path):
    settings = Settings(_env_file=None, app_env="test", database_url=f"sqlite:///{tmp_path}/db")
    with TestClient(create_app(settings)) as client:
        with client.app.state.session_factory() as db:
            user = User(email="delivery@example.com", full_name="Student", password_hash="unused")
            lab = Lab(
                title="Counter",
                description="",
                statement="",
                template="",
                interface_description="",
                kind="sequential",
                is_published=True,
            )
            db.add_all([user, lab])
            db.flush()
            submission = Submission(
                user_id=user.id, lab_id=lab.id, source_code="module student_top; endmodule\n"
            )
            db.add(submission)
            db.flush()
            run = Run(submission_id=submission.id, mode="hardware")
            db.add(run)
            db.commit()
            config = tmp_path / "bindings.json"
            config.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "labs": {str(lab.id): {"kind": "sequential", "test_set": "counter-v1"}},
                    }
                )
            )
            result = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "app.integrations.fpga.delivery",
                    "--run-id",
                    str(run.id),
                    "--bindings",
                    str(config),
                    "--jobs-root",
                    str(jobs),
                ],
                env={**os.environ, "APP_ENV": "test", "DATABASE_URL": settings.database_url},
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, result.stderr
            assert json.loads(result.stdout.splitlines()[0])["disposition"] == "uploaded"
            assert "remains queued" in result.stdout
            db.refresh(run)
            assert run.status_snapshot is None and run.result_snapshot is None and run.version == 1
            assert (jobs / "incoming" / str(run.id) / "src/student_top.v").read_text() == (
                submission.source_code
            )
