import argparse
import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import create_database_engine
from app.modules.auth.models import AuthSession  # noqa: F401
from app.modules.labs.models import Lab
from app.modules.runs.models import Run
from app.modules.submissions.models import Submission
from app.modules.submissions.schemas import SubmissionCreate
from app.modules.users.models import User  # noqa: F401


class LabTarget(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)

    kind: Literal["combinational", "sequential"]
    test_set: Annotated[str, Field(strict=True, max_length=96, pattern=r"^[A-Za-z0-9_-]+$")]


class LabBindings(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[1]
    labs: dict[UUID, LabTarget]


@dataclass(frozen=True)
class JobPackage:
    run_id: UUID
    manifest: dict
    source: bytes


def prepare_package(db: Session, run_id: UUID, bindings: LabBindings) -> JobPackage:
    run = db.get(Run, run_id)
    if run is None:
        raise ValueError("Unknown backend run")
    if run.status_snapshot is not None or run.result_snapshot is not None:
        raise ValueError("Only a queued run can be prepared")
    if run.mode != "hardware":
        raise ValueError("Student solutions require hardware mode")
    submission = db.get(Submission, run.submission_id)
    if submission is None:
        raise ValueError("Run has no source submission")
    lab = db.get(Lab, submission.lab_id)
    target = bindings.labs.get(submission.lab_id)
    if lab is None or target is None:
        raise ValueError("Laboratory has no trusted FPGA configuration")
    if target.kind != lab.kind:
        raise ValueError("FPGA configuration does not match laboratory kind")
    source = SubmissionCreate(source_code=submission.source_code).source_code.encode("utf-8")
    return JobPackage(
        run_id=run.id,
        manifest={
            "schema_version": 1,
            "run_id": str(run.id),
            "top": "student_top",
            "kind": target.kind,
            "sources": ["src/student_top.v"],
            "test_set": target.test_set,
        },
        source=source,
    )


def export_package(package: JobPackage, output_dir: Path) -> Path:
    """Write to a private staging directory, never directly to dispatcher incoming."""
    root = output_dir.resolve(strict=True)
    if not root.is_dir():
        raise ValueError("Output directory must already exist")
    destination = root / str(package.run_id)
    destination.mkdir(mode=0o700)
    try:
        (destination / "src").mkdir(mode=0o700)
        with (destination / "src/student_top.v").open("xb") as stream:
            stream.write(package.source)
        with (destination / "manifest.json").open("x", encoding="utf-8") as stream:
            json.dump(package.manifest, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
    except BaseException:
        shutil.rmtree(destination)
        raise
    return destination


def read_bindings(path: Path) -> LabBindings:
    with path.open("rb") as stream:
        data = stream.read(1024 * 1024 + 1)
    if len(data) > 1024 * 1024:
        raise ValueError("Lab configuration exceeds 1 MiB")
    return LabBindings.model_validate_json(data)


def main():
    parser = argparse.ArgumentParser(description="Prepare a saved solution for FPGA delivery")
    parser.add_argument("--run-id", type=UUID, required=True)
    parser.add_argument("--bindings", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    bindings = read_bindings(args.bindings)
    engine = create_database_engine(get_settings())
    try:
        with Session(engine) as db:
            package = prepare_package(db, args.run_id, bindings)
        path = export_package(package, args.output_dir)
        print(f"Prepared package: {path}")
        print("No job was submitted. Backend run remains queued.")
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
