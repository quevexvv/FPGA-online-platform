import argparse
import json
import math
import os
import shutil
import stat
import sys
import tempfile
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Literal
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import create_database_engine
from app.integrations.fpga.package import (
    JobPackage,
    LabTarget,
    export_package,
    prepare_package,
    read_bindings,
)
from app.modules.submissions.schemas import MAX_SOURCE_BYTES, SubmissionCreate


class DeliveryManifest(LabTarget):
    schema_version: Literal[1]
    run_id: UUID
    top: Literal["student_top"]
    sources: tuple[Literal["src/student_top.v"]]


class AlreadyRegisteredError(ValueError):
    pass


class DeliveryConflictError(ValueError):
    pass


@dataclass(frozen=True)
class DeliveryReceipt:
    run_id: UUID
    path: Path
    disposition: Literal["uploaded", "existing_upload"]


def require_directory(path: Path) -> None:
    if not stat.S_ISDIR(path.lstat().st_mode):
        raise ValueError(f"Expected a real directory: {path.name}")


def read_regular_file(path: Path, limit: int) -> bytes:
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("Expected a regular package file")
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Package file exceeds its size limit")
    return data


@contextmanager
def delivery_lock(path: Path, timeout_seconds: float):
    import fcntl

    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError("Expected a regular dispatcher lock")
        deadline = time.monotonic() + timeout_seconds
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Dispatcher run lock is busy") from None
                time.sleep(min(0.05, max(0, deadline - time.monotonic())))
        yield
    finally:
        os.close(fd)


def verify_existing_upload(path: Path, package: JobPackage) -> None:
    try:
        require_directory(path)
        require_directory(path / "src")
        if {p.name for p in path.iterdir()} != {"manifest.json", "src"}:
            raise ValueError("Unexpected package files")
        if {p.name for p in (path / "src").iterdir()} != {"student_top.v"}:
            raise ValueError("Unexpected source files")
        manifest = DeliveryManifest.model_validate_json(
            read_regular_file(path / "manifest.json", 4096)
        )
        source = read_regular_file(path / "src/student_top.v", MAX_SOURCE_BYTES)
        if manifest.model_dump(mode="json") != package.manifest or source != package.source:
            raise ValueError("Package contents differ")
    except (OSError, ValueError) as exc:
        raise DeliveryConflictError(
            "Existing upload is different or unsafe; not overwritten"
        ) from exc


def deliver_package(
    package: JobPackage, jobs_root: Path, *, timeout_seconds: float = 5
) -> DeliveryReceipt:
    """Publish one complete package on the dispatcher's local Linux filesystem."""
    if sys.platform != "linux":
        raise RuntimeError("Local FPGA delivery requires the Linux dispatcher host")
    if not math.isfinite(timeout_seconds) or not 0 < timeout_seconds <= 300:
        raise ValueError("Lock timeout must be between 0 and 300 seconds")
    manifest = DeliveryManifest.model_validate(package.manifest)
    run_id = UUID(str(package.run_id))
    if manifest.run_id != run_id:
        raise ValueError("Package run ID does not match manifest")
    source = SubmissionCreate(source_code=package.source.decode("utf-8")).source_code.encode(
        "utf-8"
    )
    package = JobPackage(run_id, manifest.model_dump(mode="json"), source)
    if not jobs_root.is_absolute():
        raise ValueError("Jobs root must be absolute")
    require_directory(jobs_root)
    root = jobs_root.resolve(strict=True)
    if root == Path("/"):
        raise ValueError("Jobs root must be dedicated to FPGA jobs")
    incoming = root / "incoming"
    require_directory(incoming)
    runs = root / "runs"
    runs.mkdir(mode=0o700, exist_ok=True)
    require_directory(runs)
    if incoming.stat().st_dev != runs.stat().st_dev:
        raise ValueError("Dispatcher incoming and runs must share a filesystem")
    locks = runs / ".locks"
    locks.mkdir(mode=0o700, exist_ok=True)
    require_directory(locks)
    destination = incoming / str(run_id)
    with delivery_lock(locks / str(run_id), timeout_seconds):
        if os.path.lexists(runs / str(run_id)) or os.path.lexists(runs / f".{run_id}.pending"):
            raise AlreadyRegisteredError(
                "Run exists at dispatcher; query its state before retrying"
            )
        if os.path.lexists(destination):
            verify_existing_upload(destination, package)
            return DeliveryReceipt(run_id, destination, "existing_upload")
        staging = Path(tempfile.mkdtemp(prefix=f".upload-{run_id}-", dir=incoming))
        try:
            prepared = export_package(package, staging)
            prepared.rename(destination)
        finally:
            shutil.rmtree(staging)
    return DeliveryReceipt(run_id, destination, "uploaded")


def main():
    parser = argparse.ArgumentParser(description="Deliver a queued solution to local FPGA incoming")
    parser.add_argument("--run-id", type=UUID, required=True)
    parser.add_argument("--bindings", type=Path, required=True)
    parser.add_argument("--jobs-root", type=Path, required=True)
    parser.add_argument("--lock-timeout", type=float, default=5)
    args = parser.parse_args()
    bindings = read_bindings(args.bindings)
    engine = create_database_engine(get_settings())
    try:
        with Session(engine) as db:
            package = prepare_package(db, args.run_id, bindings)
        receipt = deliver_package(package, args.jobs_root, timeout_seconds=args.lock_timeout)
        print(json.dumps({"run_id": str(receipt.run_id), "disposition": receipt.disposition}))
        print("No job was submitted. Backend run remains queued.")
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
