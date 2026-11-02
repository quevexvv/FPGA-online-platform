import os
from collections.abc import Generator
from pathlib import Path
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.pool import NullPool

os.environ.setdefault("DATABASE_URL", "postgresql+psycopg://test:test@127.0.0.1:65432/fpga_test")


@pytest.fixture
def database_engine() -> Generator[Engine, None, None]:
    database_url = os.environ.get("TEST_DATABASE_URL")
    if database_url is None:
        pytest.skip("TEST_DATABASE_URL is required for PostgreSQL integration tests")
    schema = "test_" + uuid4().hex
    admin_engine = create_engine(database_url, poolclass=NullPool)
    engine = None
    schema_created = False
    try:
        with admin_engine.begin() as connection:
            connection.exec_driver_sql(f'CREATE SCHEMA "{schema}"')
        schema_created = True
        engine = create_engine(database_url, poolclass=NullPool)

        @event.listens_for(engine, "connect")
        def set_search_path(connection, record) -> None:
            previous_autocommit = connection.autocommit
            try:
                connection.autocommit = True
                with connection.cursor() as cursor:
                    cursor.execute(f'SET search_path TO "{schema}"')
            finally:
                connection.autocommit = previous_autocommit

        config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
        with engine.begin() as connection:
            config.attributes["connection"] = connection
            command.upgrade(config, "head")
        yield engine
    finally:
        try:
            if engine is not None:
                engine.dispose()
        finally:
            try:
                if schema_created:
                    with admin_engine.begin() as connection:
                        connection.exec_driver_sql(f'DROP SCHEMA "{schema}" CASCADE')
            finally:
                admin_engine.dispose()
