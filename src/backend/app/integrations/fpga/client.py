import json
import math
import os
import selectors
import signal
import subprocess
import time
from pathlib import Path
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict

from app.integrations.fpga.delivery import read_regular_file, require_directory
from app.modules.runs.schemas import ExecutorResult, ExecutorStatus, Mode

MAX_RESPONSE_BYTES = 4 * 1024 * 1024


class DispatchError(RuntimeError):
    pass


class SubmitReceipt(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: Literal[1]
    run_id: UUID
    disposition: Literal["accepted", "existing"]


class DispatcherClient:
    def __init__(
        self,
        executable: Path,
        jobs_root: Path,
        *,
        timeout_seconds: float = 30,
        launch: Literal["systemd", "manual"] = "systemd",
        run_config: Path | None = None,
    ):
        if not executable.is_absolute() or not executable.is_file():
            raise ValueError("Dispatcher must be an existing absolute executable path")
        if not os.access(executable, os.X_OK):
            raise ValueError("Dispatcher is not executable")
        if not jobs_root.is_absolute() or jobs_root == Path("/"):
            raise ValueError("Jobs root must be an absolute dedicated directory")
        require_directory(jobs_root)
        require_directory(jobs_root / "incoming")
        if launch not in ("systemd", "manual"):
            raise ValueError("Invalid launch mode")
        if not math.isfinite(timeout_seconds) or not 0 < timeout_seconds <= 300:
            raise ValueError("Command timeout must be between 0 and 300 seconds")
        if run_config is not None and (not run_config.is_absolute() or not run_config.is_file()):
            raise ValueError("Run config must be an existing absolute file")
        self.executable = executable
        self.jobs_root = jobs_root.resolve(strict=True)
        self.timeout_seconds = timeout_seconds
        self.environment = {
            **os.environ,
            "FPGA_JOBS_ROOT": str(self.jobs_root),
            "FPGA_DISPATCH_LAUNCH": launch,
            "FPGA_RUN_CONFIG": str(run_config) if run_config else "",
        }

    def _command(self, arguments: list[str]) -> dict:
        buffers = {"out": bytearray(), "err": bytearray()}
        deadline = time.monotonic() + self.timeout_seconds
        with subprocess.Popen(
            [str(self.executable), *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=self.environment,
            shell=False,
            start_new_session=True,
        ) as process:
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ, "out")
                    selector.register(process.stderr, selectors.EVENT_READ, "err")
                    while selector.get_map():
                        remaining = deadline - time.monotonic()
                        if remaining <= 0:
                            raise DispatchError(
                                "Dispatcher command timed out; retry the same run ID"
                            )
                        for key, _ in selector.select(remaining):
                            data = os.read(key.fileobj.fileno(), 65536)
                            if not data:
                                selector.unregister(key.fileobj)
                                continue
                            buffers[key.data].extend(data)
                            if sum(map(len, buffers.values())) > MAX_RESPONSE_BYTES:
                                raise DispatchError("Dispatcher response exceeds 4 MiB")
                try:
                    code = process.wait(timeout=max(0, deadline - time.monotonic()))
                except subprocess.TimeoutExpired:
                    raise DispatchError(
                        "Dispatcher command timed out; retry the same run ID"
                    ) from None
                if code != 0:
                    raise DispatchError(f"Dispatcher command failed with exit code {code}")
            finally:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
        try:
            data = json.loads(buffers["out"])
        except (ValueError, UnicodeError):
            raise DispatchError("Dispatcher returned invalid JSON") from None
        if not isinstance(data, dict):
            raise DispatchError("Dispatcher response must be a JSON object")
        return data

    def submit(self, run_id: UUID, mode: Mode) -> SubmitReceipt:
        run_id = UUID(str(run_id))
        if mode not in ("hardware", "mock"):
            raise ValueError("Invalid registered run mode")
        receipt = SubmitReceipt.model_validate(
            self._command(["submit", "--run-id", str(run_id), "--mode", mode])
        )
        if receipt.run_id != run_id:
            raise DispatchError("Dispatcher returned a different run ID")
        return receipt

    def status(self, run_id: UUID, mode: Mode) -> ExecutorStatus:
        run_id = UUID(str(run_id))
        status = ExecutorStatus.model_validate(self._command(["status", "--run-id", str(run_id)]))
        if status.run_id != run_id or status.mode != mode:
            raise DispatchError("Dispatcher status identity does not match the backend")
        return status

    def result(self, run_id: UUID, mode: Mode) -> ExecutorResult:
        run_id = UUID(str(run_id))
        runs = self.jobs_root / "runs"
        run = runs / str(run_id)
        output = run / "output"
        for directory in (runs, run, output):
            require_directory(directory)
        result = ExecutorResult.model_validate_json(
            read_regular_file(output / "result.json", MAX_RESPONSE_BYTES)
        )
        if result.run_id != run_id or result.mode != mode:
            raise DispatchError("Dispatcher result identity does not match the backend")
        return result
