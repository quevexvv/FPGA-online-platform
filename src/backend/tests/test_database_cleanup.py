from unittest.mock import MagicMock

import conftest
import pytest


@pytest.mark.parametrize("failure_stage", ["create_schema", "create_engine", "migration"])
def test_database_fixture_cleans_up_when_setup_fails(monkeypatch, failure_stage):
    monkeypatch.setenv("TEST_DATABASE_URL", "postgresql+psycopg://test:test@localhost/test")
    admin_engine = MagicMock()
    engine = MagicMock()
    failure = RuntimeError("Simulated setup failure")
    if failure_stage == "create_schema":
        admin_engine.begin.side_effect = failure
    engines = [admin_engine, failure if failure_stage == "create_engine" else engine]
    monkeypatch.setattr(conftest, "create_engine", MagicMock(side_effect=engines))
    monkeypatch.setattr(conftest.event, "listens_for", lambda *args: lambda fn: fn)
    upgrade = MagicMock(side_effect=failure)
    monkeypatch.setattr(conftest.command, "upgrade", upgrade)

    fixture = conftest.database_engine.__wrapped__()
    with pytest.raises(RuntimeError, match="Simulated setup failure"):
        next(fixture)

    admin_engine.dispose.assert_called_once_with()
    if failure_stage == "migration":
        upgrade.assert_called_once()
        engine.dispose.assert_called_once_with()
    else:
        engine.dispose.assert_not_called()
    if failure_stage != "create_schema":
        statements = admin_engine.begin.return_value.__enter__.return_value.exec_driver_sql
        create_sql, drop_sql = [call.args[0] for call in statements.call_args_list]
        assert create_sql.startswith('CREATE SCHEMA "test_')
        assert drop_sql == create_sql.replace("CREATE SCHEMA", "DROP SCHEMA") + " CASCADE"
