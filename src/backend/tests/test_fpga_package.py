import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi.testclient import TestClient

from app.core.config import Settings, get_settings
from app.integrations.fpga.package import (
    LabBindings,
    LabTarget,
    export_package,
    main,
    prepare_package,
    read_bindings,
)
from app.main import create_app
from app.modules.labs.models import Lab
from app.modules.runs.models import Run
from app.modules.submissions.models import Submission
from app.modules.users.models import User

SOURCE = "module student_top;\r\n    // Кириллица, $(echo ignored), `text`\r\nendmodule\r\n"


@pytest.fixture
def saved_run(tmp_path):
    settings = Settings(_env_file=None, app_env="test", database_url=f"sqlite:///{tmp_path}/db")
    with TestClient(create_app(settings)) as client:
        with client.app.state.session_factory() as db:
            user = User(email="package@example.com", full_name="Student", password_hash="unused")
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
            submission = Submission(user_id=user.id, lab_id=lab.id, source_code=SOURCE)
            db.add(submission)
            db.flush()
            run = Run(submission_id=submission.id, mode="hardware")
            db.add(run)
            db.commit()
            yield db, run, lab, submission, settings


def bindings(lab):
    return LabBindings(
        schema_version=1, labs={lab.id: LabTarget(kind=lab.kind, test_set="counter-v1")}
    )


def test_export_preserves_source_and_uses_only_trusted_manifest(saved_run, tmp_path):
    db, run, lab, submission, _ = saved_run
    package = prepare_package(db, run.id, bindings(lab))
    path = export_package(package, tmp_path)
    assert json.loads((path / "manifest.json").read_text()) == {
        "schema_version": 1,
        "run_id": str(run.id),
        "top": "student_top",
        "kind": "sequential",
        "sources": ["src/student_top.v"],
        "test_set": "counter-v1",
    }
    assert (path / "src/student_top.v").read_bytes() == SOURCE.encode("utf-8")
    assert sorted(str(p.relative_to(path)) for p in path.rglob("*") if p.is_file()) == [
        "manifest.json",
        "src/student_top.v",
    ]
    db.refresh(run)
    assert run.status_snapshot is None and run.version == 1
    assert not db.dirty
    assert str(submission.user_id) not in (path / "manifest.json").read_text()
    with pytest.raises(FileExistsError):
        export_package(package, tmp_path)
    assert (path / "src/student_top.v").read_bytes() == SOURCE.encode("utf-8")


@pytest.mark.parametrize(
    "case", ["unknown", "unbound", "wrong_kind", "running", "finished", "mock"]
)
def test_unconfigured_or_started_jobs_are_rejected(saved_run, case):
    db, run, lab, _, _ = saved_run
    config = bindings(lab)
    run_id = run.id
    if case == "unknown":
        run_id = uuid4()
    elif case == "unbound":
        config.labs.clear()
    elif case == "wrong_kind":
        config.labs[lab.id] = LabTarget(kind="combinational", test_set="counter-v1")
    elif case == "running":
        run.status_snapshot = {"state": "running"}
    elif case == "finished":
        run.result_snapshot = {"status": "passed"}
    else:
        run.mode = "mock"
    with pytest.raises(ValueError):
        prepare_package(db, run_id, config)


@pytest.mark.parametrize("name", ["../secret", "/absolute", "x;echo", "a/b", "x\n", ""])
def test_test_set_is_an_identifier_not_a_path_or_command(name):
    with pytest.raises(ValueError):
        LabTarget(kind="sequential", test_set=name)


def test_extra_config_fields_are_forbidden_and_size_is_bounded(tmp_path):
    path = tmp_path / "bindings.json"
    path.write_text(json.dumps({"schema_version": 1, "labs": {}, "command": "echo"}))
    with pytest.raises(ValueError):
        read_bindings(path)
    path.write_bytes(b" " * (1024 * 1024 + 1))
    with pytest.raises(ValueError, match="exceeds"):
        read_bindings(path)


def test_existing_symlink_is_not_followed(saved_run, tmp_path):
    db, run, lab, _, _ = saved_run
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "keep").write_text("unchanged")
    (tmp_path / str(run.id)).symlink_to(outside, target_is_directory=True)
    with pytest.raises(FileExistsError):
        export_package(prepare_package(db, run.id, bindings(lab)), tmp_path)
    assert list(outside.iterdir()) == [outside / "keep"]
    assert (outside / "keep").read_text() == "unchanged"


def test_failed_write_removes_only_its_new_package(saved_run, tmp_path, monkeypatch):
    db, run, lab, _, _ = saved_run
    keep = tmp_path / "keep"
    keep.write_text("unrelated")

    def fail(*args, **kwargs):
        raise OSError("disk full")

    monkeypatch.setattr("app.integrations.fpga.package.json.dump", fail)
    with pytest.raises(OSError, match="disk full"):
        export_package(prepare_package(db, run.id, bindings(lab)), tmp_path)
    assert not (tmp_path / str(run.id)).exists()
    assert keep.read_text() == "unrelated"


def test_cli_exports_saved_run_without_submitting_it(saved_run, tmp_path, monkeypatch, capsys):
    _, run, lab, _, settings = saved_run
    config_path = tmp_path / "bindings.json"
    config_path.write_text(bindings(lab).model_dump_json())
    monkeypatch.setattr(
        "sys.argv",
        [
            "package",
            "--run-id",
            str(run.id),
            "--bindings",
            str(config_path),
            "--output-dir",
            str(tmp_path),
        ],
    )
    monkeypatch.setenv("DATABASE_URL", settings.database_url)
    get_settings.cache_clear()
    try:
        main()
    finally:
        get_settings.cache_clear()
    assert (tmp_path / str(run.id) / "manifest.json").exists()
    assert "remains queued" in capsys.readouterr().out


@pytest.mark.skipif(sys.platform != "linux" or not shutil.which("jq"), reason="Linux/jq required")
def test_package_is_accepted_by_the_actual_dispatcher_in_mock_mode(saved_run, tmp_path):
    db, run, lab, submission, _ = saved_run
    submission.source_code = "module student_top; endmodule\n"
    db.commit()
    package = prepare_package(db, run.id, bindings(lab))
    staging = tmp_path / "staging"
    staging.mkdir()
    path = export_package(package, staging)
    jobs = tmp_path / "jobs"
    incoming = jobs / "incoming"
    incoming.mkdir(parents=True)
    shutil.copytree(path, incoming / str(run.id))
    fpga = Path(__file__).resolve().parents[2] / "fpga"
    env = {
        **os.environ,
        "FPGA_JOBS_ROOT": str(jobs),
        "FPGA_DISPATCH_LAUNCH": "manual",
        "FPGA_RUN_CONFIG": "",
    }
    response = subprocess.run(
        [str(fpga / "bin/fpga-dispatch"), "submit", "--run-id", str(run.id), "--mode", "mock"],
        env=env,
        check=True,
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert json.loads(response.stdout)["disposition"] == "accepted"
    state = json.loads((jobs / "runs" / str(run.id) / "output/status.json").read_text())
    assert state["mode"] == "mock" and state["state"] == "starting"
    db.refresh(run)
    assert run.mode == "hardware" and run.status_snapshot is None
