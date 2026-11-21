import argparse
import logging
import time
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import or_, select
from sqlalchemy.engine import Engine
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import create_database_engine
from app.integrations.fpga.client import DispatcherClient, DispatchError
from app.integrations.fpga.delivery import delivery_lock
from app.integrations.fpga.package import LabBindings, read_bindings
from app.integrations.fpga.runner import advance_run, positive_seconds
from app.modules.runs.models import Run
from app.modules.submissions.models import Submission

logger = logging.getLogger(__name__)


def queue_step(engine: Engine, client: DispatcherClient, bindings: LabBindings):
    with delivery_lock(client.jobs_root / ".backend-queue.lock", 0):
        with Session(engine) as db, db.begin():
            active = Run.status_snapshot["state"].as_string().is_not(None)
            claimed = Run.queue_claimed_at.is_not(None)
            run = db.scalar(
                select(Run)
                .join(Submission, Submission.id == Run.submission_id)
                .where(
                    Run.mode == "hardware",
                    Run.result_snapshot["status"].as_string().is_(None),
                    or_(claimed, active, Submission.lab_id.in_(bindings.labs)),
                )
                .order_by(claimed.desc(), active.desc(), Run.created_at, Run.id)
                .limit(1)
            )
            if run is None:
                return None
            if run.queue_claimed_at is None:
                run.queue_claimed_at = datetime.now(timezone.utc)
            run_id = run.id
        try:
            return run_id, advance_run(engine, client, bindings, run_id)
        except (DispatchError, ValueError, OSError, SQLAlchemyError):
            logger.exception("Could not advance run %s", run_id)
            raise


def main():
    parser = argparse.ArgumentParser(description="Process the queue for one local FPGA board")
    parser.add_argument("--bindings", type=Path, required=True)
    parser.add_argument("--jobs-root", type=Path, required=True)
    parser.add_argument("--dispatcher", type=Path, required=True)
    parser.add_argument("--run-config", type=Path)
    parser.add_argument("--poll-interval", type=positive_seconds, default=3)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    bindings = read_bindings(args.bindings)
    client = DispatcherClient(args.dispatcher, args.jobs_root, run_config=args.run_config)
    engine = create_database_engine(get_settings())
    try:
        while True:
            try:
                step = queue_step(engine, client, bindings)
                if step and step[1] == "finished":
                    logger.info("Finished run %s", step[0])
                    continue
            except (DispatchError, OSError, ValueError, SQLAlchemyError) as exc:
                logger.warning("Queue will retry: %s", type(exc).__name__)
            time.sleep(args.poll_interval)
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
