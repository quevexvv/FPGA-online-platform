import os
import re
import stat

from app.integrations.fpga.delivery import require_directory

LIMIT = 16 * 1024
PATH = re.compile(r"""(?<!\w)(?:[A-Za-z]:[\\/]|/)[^\s"'<>]+""")
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")


def tail(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
            raise ValueError("Expected a regular log file")
        start = max(0, info.st_size - LIMIT)
        stream.seek(start)
        data = stream.read(LIMIT)
    if start:
        data = data.partition(b"\n")[2]
    value = ANSI.sub("", data.decode("utf-8", errors="replace"))
    value = "".join(c for c in value if c.isprintable() or c in "\n\t")
    return ("[…]\n" if start else "") + PATH.sub("[path]", value)


def read_public_logs(jobs_root, run_id):
    directory = jobs_root
    logs = {}
    try:
        for part in ("runs", str(run_id), "output", "logs"):
            directory = directory / part
            require_directory(directory)
    except (OSError, ValueError):
        return logs
    for key, filename in (("build", "build.log"), ("program", "program.log")):
        try:
            logs[key] = tail(directory / filename)
        except (OSError, ValueError):
            continue
    return logs
