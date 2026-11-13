from datetime import datetime, timezone
from typing import get_args
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.runs.models import Run
from app.modules.runs.schemas import (
    ExecutorResult,
    ExecutorStatus,
    Mode,
    PublicError,
    RunPublic,
    Stage,
)
from app.modules.submissions.repository import find_owned

ERROR_MESSAGES = {
    "build_error": "Не удалось собрать решение.",
    "board_error": "Не удалось завершить проверку на плате.",
    "invalid_input": "Исполнитель отклонил входные данные.",
    "busy": "Стенд занят. Попытка завершена без проверки.",
    "internal_error": "Ошибка исполнителя проверки.",
}


def enqueue(
    db: Session,
    submission_id: UUID,
    *,
    mode: Mode = "hardware",
    public_vector_indices: tuple[int, ...] = (),
) -> Run:
    if mode not in ("hardware", "mock") or any(
        type(index) is not int or index < 0 for index in public_vector_indices
    ):
        raise ValueError("Invalid trusted run configuration")
    run = Run(
        submission_id=submission_id,
        mode=mode,
        public_vector_indices=sorted(set(public_vector_indices)),
    )
    db.add(run)
    db.flush()
    return run


def configure_public_vectors(db: Session, run_id: UUID, indices: list[int]) -> None:
    """Set visibility from trusted lab configuration, before importing any status."""
    if any(type(index) is not int or index < 0 for index in indices):
        raise ValueError("Invalid public vector index")
    run = db.get(Run, run_id)
    if run is None:
        raise ValueError("Unknown backend run")
    allowed = sorted(set(indices))
    if run.public_vector_indices == allowed:
        return
    if run.status_snapshot is not None:
        raise ValueError("Test visibility cannot change after execution starts")
    run.public_vector_indices = allowed
    db.flush()


def record_executor_snapshot(
    db: Session,
    run_id: UUID,
    status_data: dict,
    result_data: dict | None = None,
) -> bool:
    run = db.get(Run, run_id)
    if run is None:
        raise ValueError("Unknown backend run")
    status = ExecutorStatus.model_validate(status_data)
    if status.run_id != run.id or status.mode != run.mode:
        raise ValueError("Executor identity does not match the registered run")
    result = None
    if status.state == "finished":
        if result_data is None:
            raise ValueError("Finished status requires result.json; retry after reading it")
        result = ExecutorResult.model_validate(result_data)
        if (
            result.run_id != run.id
            or result.mode != run.mode
            or result.status != status.result_status
            or result.started_at != status.started_at
            or result.finished_at != status.finished_at
        ):
            raise ValueError("Result contradicts status")
    elif result_data is not None:
        raise ValueError("Result can only be attached to finished status")
    snapshot = status.model_dump(mode="json")
    report = result.model_dump(mode="json") if result else None
    if run.status_snapshot is not None:
        previous = ExecutorStatus.model_validate(run.status_snapshot)
        if run.status_snapshot == snapshot and run.result_snapshot == report:
            return False
        if previous.state == "finished":
            raise ValueError("A finished run is immutable; create a new run for a retry")
        if status.updated_at < previous.updated_at:
            raise ValueError("Stale or conflicting status update")
        states = {"starting": 0, "running": 1, "finished": 2}
        stages = get_args(Stage)
        if status.updated_at == previous.updated_at and (
            states[status.state],
            stages.index(status.stage),
        ) <= (states[previous.state], stages.index(previous.stage)):
            raise ValueError("Conflicting status within the same second")
        if previous.state == "running" and status.state == "starting":
            raise ValueError("Run state cannot move backwards")
        if previous.started_at and status.started_at != previous.started_at:
            raise ValueError("Run start time cannot change")
    run.status_snapshot = snapshot
    run.result_snapshot = report
    db.flush()
    return True


def utc(value: datetime) -> datetime:
    return (
        value.replace(tzinfo=timezone.utc)
        if value.tzinfo is None
        else value.astimezone(timezone.utc)
    )


def get_run(db: Session, user_id: UUID, submission_id: UUID) -> RunPublic:
    if find_owned(db, user_id, submission_id) is None:
        raise HTTPException(status_code=404, detail="Submission not found")
    run = db.scalar(
        select(Run)
        .where(Run.submission_id == submission_id)
        .order_by(Run.created_at.desc(), Run.id.desc())
        .limit(1)
    )
    response = RunPublic(
        submission_id=submission_id,
        run_id=None,
        state="not_started",
        stage=None,
        mode=None,
        result_status=None,
        hardware_verified=False,
        queued_at=None,
        started_at=None,
        updated_at=None,
        finished_at=None,
        elapsed_seconds=0,
        poll_after_seconds=None,
        summary=None,
        tests=[],
        error=None,
    )
    if run is None:
        return response
    response.run_id = run.id
    response.state = "queued"
    response.mode = run.mode
    response.queued_at = response.updated_at = utc(run.created_at)
    response.poll_after_seconds = 3
    if run.status_snapshot is None:
        return response
    status = ExecutorStatus.model_validate(run.status_snapshot)
    response.state = "finished" if status.state == "finished" else "running"
    response.stage = status.stage
    response.started_at = status.started_at
    response.updated_at = status.updated_at
    response.finished_at = status.finished_at
    if status.started_at:
        response.elapsed_seconds = max(
            0,
            (
                (status.finished_at or datetime.now(timezone.utc)) - status.started_at
            ).total_seconds(),
        )
    if status.state == "finished":
        result = ExecutorResult.model_validate(run.result_snapshot)
        response.result_status = result.status
        response.hardware_verified = result.hardware_verified
        response.poll_after_seconds = None
        response.summary = result.summary
        allowed = set(run.public_vector_indices)
        response.tests = [item for item in result.observations if item.vector_index in allowed]
        if result.status in ERROR_MESSAGES:
            response.error = PublicError(code=result.status, message=ERROR_MESSAGES[result.status])
    return response
