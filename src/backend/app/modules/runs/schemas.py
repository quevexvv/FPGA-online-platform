from datetime import datetime, timezone
from typing import Annotated, Literal
from uuid import UUID

from pydantic import (
    AfterValidator,
    BaseModel,
    ConfigDict,
    Field,
    StrictBool,
    model_validator,
)

Mode = Literal["hardware", "mock"]
Stage = Literal[
    "dispatch", "validating", "locking", "building", "programming", "testing", "finalizing"
]
Outcome = Literal[
    "passed", "mismatch", "build_error", "board_error", "invalid_input", "busy", "internal_error"
]
Count = Annotated[int, Field(strict=True, ge=0)]


def aware_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        raise ValueError("Timestamp must include a timezone")
    return value.astimezone(timezone.utc)


Timestamp = Annotated[datetime, AfterValidator(aware_utc)]


class ContractModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Summary(ContractModel):
    planned: Count
    executed: Count
    passed: Count
    failed: Count

    @model_validator(mode="after")
    def check_counts(self):
        if self.executed > self.planned or self.passed + self.failed != self.executed:
            raise ValueError("Inconsistent summary counts")
        return self


class Observation(ContractModel):
    vector_index: Count
    din: Annotated[str, Field(strict=True, pattern=r"^0x[0-3][0-9a-f]{2}$")]
    steps: Count
    dout: Annotated[str, Field(strict=True, pattern=r"^0x[0-3][0-9a-f]{4}$")]
    expected_dout: Annotated[str, Field(strict=True, pattern=r"^0x[0-3][0-9a-f]{4}$")]
    mask: Annotated[str, Field(strict=True, pattern=r"^0x[0-3][0-9a-f]{4}$")]
    match: StrictBool

    @model_validator(mode="after")
    def check_match(self):
        if self.match != (
            (int(self.dout, 16) & int(self.mask, 16))
            == (int(self.expected_dout, 16) & int(self.mask, 16))
        ):
            raise ValueError("Observation match contradicts outputs")
        return self


class ExecutorError(ContractModel):
    stage: Stage
    code: str
    message: str


class ExecutorStatus(ContractModel):
    schema_version: Literal[1]
    run_id: UUID
    mode: Mode
    state: Literal["starting", "running", "finished"]
    stage: Stage
    started_at: Timestamp | None
    updated_at: Timestamp
    finished_at: Timestamp | None
    result_status: Outcome | None

    @model_validator(mode="after")
    def check_state(self):
        if self.state == "finished":
            if self.finished_at is None or self.result_status is None or self.stage != "finalizing":
                raise ValueError("Finished status requires a timestamp and outcome")
        elif self.finished_at is not None or self.result_status is not None:
            raise ValueError("An active run cannot have an outcome")
        if self.state == "starting" and (self.stage != "dispatch" or self.started_at is not None):
            raise ValueError("Starting status requires dispatch and no start time")
        if self.state == "running" and self.started_at is None:
            raise ValueError("Running status requires started_at")
        if self.started_at and self.started_at > self.updated_at:
            raise ValueError("updated_at must not precede started_at")
        if self.finished_at and (
            self.finished_at > self.updated_at
            or (self.started_at and self.finished_at < self.started_at)
        ):
            raise ValueError("Invalid finish timestamp")
        return self


class ExecutorResult(ContractModel):
    schema_version: Literal[1]
    run_id: UUID
    mode: Mode
    status: Outcome
    hardware_verified: StrictBool
    started_at: Timestamp | None
    finished_at: Timestamp
    summary: Summary
    observations: list[Observation]
    error: ExecutorError | None
    logs: list[str]

    @model_validator(mode="after")
    def check_result(self):
        summary = self.summary
        if self.started_at and self.finished_at < self.started_at:
            raise ValueError("Invalid result timestamps")
        indices = [item.vector_index for item in self.observations]
        if len(set(indices)) != len(indices) or len(indices) != summary.executed:
            raise ValueError("Duplicate or missing observations")
        if sum(item.match for item in self.observations) != summary.passed:
            raise ValueError("Observations contradict summary")
        if self.status in ("passed", "mismatch"):
            if self.started_at is None or summary.executed != summary.planned or self.error:
                raise ValueError("Completed tests require all observations and no error")
            if (self.status == "passed") != (summary.failed == 0):
                raise ValueError("Outcome contradicts failed count")
            if self.mode == "hardware" and not self.hardware_verified:
                raise ValueError("Completed hardware tests must be verified")
        elif self.error is None:
            raise ValueError("Failed execution requires an error")
        if self.hardware_verified and (
            self.mode != "hardware"
            or self.status not in ("passed", "mismatch")
            or self.started_at is None
        ):
            raise ValueError("Hardware verification requires a complete hardware run")
        return self


class PublicError(BaseModel):
    code: Outcome
    message: str


class RunPublic(BaseModel):
    submission_id: UUID
    run_id: UUID | None
    state: Literal["not_started", "queued", "running", "finished"]
    stage: Stage | None
    mode: Mode | None
    result_status: Outcome | None
    hardware_verified: bool
    queued_at: datetime | None
    started_at: datetime | None
    updated_at: datetime | None
    finished_at: datetime | None
    elapsed_seconds: float
    poll_after_seconds: int | None
    summary: Summary | None
    tests: list[Observation]
    error: PublicError | None
