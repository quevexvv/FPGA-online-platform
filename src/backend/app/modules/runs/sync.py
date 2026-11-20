import argparse
import json
from pathlib import Path
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import create_database_engine
from app.modules.auth.models import AuthSession  # noqa: F401
from app.modules.labs.models import Lab  # noqa: F401
from app.modules.runs.service import configure_public_vectors, record_executor_snapshot
from app.modules.submissions.models import Submission  # noqa: F401
from app.modules.users.models import User  # noqa: F401


def read_snapshot(path: Path) -> dict:
    with path.open("rb") as stream:
        payload = stream.read(4 * 1024 * 1024 + 1)
    if len(payload) > 4 * 1024 * 1024:
        raise ValueError("Executor JSON exceeds 4 MiB")
    data = json.loads(payload)
    if not isinstance(data, dict):
        raise ValueError("Executor snapshot must be an object")
    return data


def main():
    parser = argparse.ArgumentParser(
        description="Import a trusted executor snapshot into the backend"
    )
    parser.add_argument("--run-id", type=UUID, required=True)
    parser.add_argument("--status", type=Path, required=True)
    parser.add_argument("--result", type=Path)
    parser.add_argument("--public-vector-index", type=int, action="append")
    args = parser.parse_args()
    status = read_snapshot(args.status)
    result = read_snapshot(args.result) if args.result else None
    engine = create_database_engine(get_settings())
    try:
        with Session(engine) as db, db.begin():
            if args.public_vector_index is not None:
                configure_public_vectors(db, args.run_id, args.public_vector_index)
            changed = record_executor_snapshot(db, args.run_id, status, result)
        print("updated" if changed else "unchanged")
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
