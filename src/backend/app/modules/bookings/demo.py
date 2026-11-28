"""Create an isolated SQLite demo of two bookable FPGA laboratories."""

import argparse
import json
import secrets
from pathlib import Path
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import hash_password
from app.db.session import create_database_engine
from app.integrations.fpga.package import LabBindings, LabTarget
from app.modules.auth.repository import find_user
from app.modules.bookings.models import LabPolicy
from app.modules.labs.models import Lab
from app.modules.users.models import User

LABS = (
    (
        UUID("af01b275-5d7c-40dc-90c0-3bd4c9bd773a"),
        "Передача входного слова",
        "combinational",
        "combinational-v1",
        "Передайте 10 входных битов din на младшие биты dout, старшие обнулите.",
    ),
    (
        UUID("b5f43be0-3f30-44b4-b891-721389962129"),
        "Счётчик",
        "sequential",
        "counter-v1",
        "При reset обнулите dout. На каждом положительном фронте clk прибавляйте din к dout.",
    ),
)


def prepare_demo(db: Session):
    targets = {}
    credentials = []
    template = (
        "module student_top(input wire clk, reset, input wire [9:0] din, "
        "output wire [17:0] dout);\n    // TODO: implement student_top\nendmodule\n"
    )
    for position, (lab_id, title, kind, test_set, statement) in enumerate(LABS, 1):
        lab = db.get(Lab, lab_id)
        if lab is None:
            db.add(
                Lab(
                    id=lab_id,
                    title=title,
                    kind=kind,
                    statement=statement,
                    template=template,
                    description="Приёмка на C5G",
                    interface_description="student_top(clk, reset, din[9:0], dout[17:0])",
                    is_published=True,
                    is_demo=True,
                )
            )
            db.flush()
        elif not lab.is_demo or lab.kind != kind:
            raise ValueError("Demo ID already belongs to a different laboratory")
        if not db.get(LabPolicy, lab_id):
            db.add(LabPolicy(lab_id=lab_id, position=position))
        targets[lab_id] = LabTarget(kind=kind, test_set=test_set)
    for role in ("student", "teacher"):
        email = f"fpga-demo-{role}@example.com"
        if not find_user(db, email):
            password = secrets.token_urlsafe(18)
            db.add(
                User(
                    email=email,
                    role=role,
                    full_name=f"Demo {role}",
                    password_hash=hash_password(password),
                )
            )
            credentials.append((email, password))
    return LabBindings(schema_version=1, labs=targets), credentials


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bindings", type=Path, required=True)
    args = parser.parse_args()
    settings = get_settings()
    if settings.app_env not in ("development", "test") or not settings.database_url.startswith(
        "sqlite:"
    ):
        parser.error("Use a separate local SQLite development database")
    engine = create_database_engine(settings)
    try:
        with Session(engine) as db, db.begin():
            bindings, credentials = prepare_demo(db)
            if args.bindings.exists():
                if LabBindings.model_validate_json(args.bindings.read_bytes()) != bindings:
                    raise ValueError("Choose another bindings file")
            else:
                with args.bindings.open("x") as output:
                    json.dump(bindings.model_dump(mode="json"), output, indent=2)
        for email, password in credentials:
            print(f"{email}  {password}")
        print(f"Bindings: {args.bindings.resolve()}")
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
