import argparse
import json
import math
import sys
import time
from pathlib import Path
from uuid import UUID

from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session
from sqlalchemy.orm.exc import StaleDataError

from app.core.config import get_settings
from app.db.session import create_database_engine
from app.integrations.fpga.client import DispatcherClient, DispatchError
from app.integrations.fpga.delivery import AlreadyRegisteredError, deliver_package
from app.integrations.fpga.package import LabBindings, prepare_package, read_bindings
from app.modules.runs.models import Run
from app.modules.runs.service import configure_public_vectors, record_executor_snapshot


def advance_run(
    engine: Engine,
    client: DispatcherClient,
    bindings: LabBindings,
    run_id: UUID,
    public_indices: list[int] | None = None,
) -> str:
    with Session(engine) as db, db.begin():
        run = db.get(Run, run_id)
        if run is None:
            raise ValueError("Unknown backend run")
        if run.result_snapshot is not None:
            return "finished"
        if public_indices is not None:
            configure_public_vectors(db, run_id, public_indices)
        mode = run.mode
        package = prepare_package(db, run_id, bindings) if run.status_snapshot is None else None
    if package is not None:
        try:
            deliver_package(package, client.jobs_root)
        except AlreadyRegisteredError:
            pass
        client.submit(run_id, mode)
    return sync_run(engine, client, run_id)


def sync_run(engine: Engine, client: DispatcherClient, run_id: UUID) -> str:
    with Session(engine) as db:
        run = db.get(Run, run_id)
        if run is None:
            raise ValueError("Unknown backend run")
        if run.result_snapshot is not None:
            return "finished"
        mode = run.mode
    status = client.status(run_id, mode)
    result = client.result(run_id, mode) if status.state == "finished" else None
    with Session(engine) as db, db.begin():
        record_executor_snapshot(
            db,
            run_id,
            status.model_dump(mode="json"),
            result.model_dump(mode="json") if result else None,
        )
    return "finished" if result else "running"


def positive_seconds(value: str) -> float:
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("Expected a positive finite duration")
    return number


def main() -> int:
    parser = argparse.ArgumentParser(description="Dispatch and follow one saved FPGA run on Linux")
    parser.add_argument("--run-id", type=UUID, required=True)
    parser.add_argument("--bindings", type=Path, required=True)
    parser.add_argument("--jobs-root", type=Path, required=True)
    parser.add_argument("--dispatcher", type=Path, required=True)
    parser.add_argument("--run-config", type=Path)
    parser.add_argument("--launch", choices=("systemd", "manual"), default="systemd")
    parser.add_argument("--public-vector-index", type=int, action="append")
    parser.add_argument("--command-timeout", type=positive_seconds, default=30)
    parser.add_argument("--poll-interval", type=positive_seconds, default=3)
    parser.add_argument("--max-wait", type=positive_seconds, default=900)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    bindings = read_bindings(args.bindings)
    client = DispatcherClient(
        args.dispatcher,
        args.jobs_root,
        timeout_seconds=args.command_timeout,
        launch=args.launch,
        run_config=args.run_config,
    )
    engine = create_database_engine(get_settings())
    deadline = time.monotonic() + args.max_wait
    try:
        while True:
            try:
                state = advance_run(engine, client, bindings, args.run_id, args.public_vector_index)
                print(json.dumps({"run_id": str(args.run_id), "state": state}), flush=True)
                if state == "finished" or args.once:
                    return 0
            except (DispatchError, OSError, ValueError, StaleDataError) as exc:
                print(f"Run not updated ({type(exc).__name__}); retry the same ID", file=sys.stderr)
                if args.once:
                    return 1
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                print(
                    "Wait limit reached; executor is not cancelled. Resume with the same ID.",
                    file=sys.stderr,
                )
                return 2
            time.sleep(min(args.poll_interval, remaining))
    finally:
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
