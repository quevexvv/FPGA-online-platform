"""Explicit, repeatable local demo setup: python -m app.modules.labs.seed."""

from pathlib import Path
from uuid import UUID

from alembic import command
from alembic.config import Config
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import create_database_engine
from app.modules.labs.models import Lab, LabKind

DEMO_LAB_ID = UUID("346674de-1837-4d21-a234-2e61a85a5701")


def seed_demo(db: Session) -> UUID:
    """Keep existing content and publication settings unchanged on subsequent runs."""
    if db.get(Lab, DEMO_LAB_ID) is None:
        db.add(
            Lab(
                id=DEMO_LAB_ID,
                title="Демо: комбинационная логика",
                description="Тестовая лабораторная для проверки каталога и редактора.",
                statement=(
                    "Учебный пример для разработки API, не утверждённая лабораторная курса. "
                    "Реализуйте логическое И входов din[0] и din[1] на выходе dout[0]. "
                    "Остальные биты dout должны быть нулевыми. "
                    "Шаблон содержит заглушку, которую нужно заменить своим решением. "
                    "Отправка решений и проверка на плате пока не подключены."
                ),
                template=(
                    "module student_top (\n"
                    "    input wire clk,\n"
                    "    input wire reset,\n"
                    "    input wire [9:0] din,\n"
                    "    output wire [17:0] dout\n"
                    ");\n"
                    "    // TODO: replace this placeholder with your logic.\n"
                    "    assign dout = 18'b0;\n"
                    "endmodule\n"
                ),
                interface_description=(
                    "Verilog-2001; student_top(clk, reset, din[9:0], dout[17:0]). "
                    "В комбинационной схеме clk и reset не используются. "
                    "Интерфейс предварительный до проверки обёртки стенда."
                ),
                kind=LabKind.combinational,
                is_published=True,
                is_demo=True,
            )
        )
        db.commit()
    return DEMO_LAB_ID


def seed_local_demo(settings: Settings) -> UUID:
    if settings.app_env not in ("development", "test") or not settings.database_url.startswith(
        "sqlite:"
    ):
        raise ValueError("Demo seeding is only available for local SQLite development/test")
    engine = create_database_engine(settings)
    try:
        config = Config(str(Path(__file__).resolve().parents[3] / "alembic.ini"))
        with engine.begin() as connection:
            config.attributes["connection"] = connection
            command.upgrade(config, "head")
        with Session(engine) as db:
            return seed_demo(db)
    finally:
        engine.dispose()


if __name__ == "__main__":
    print(f"Demo laboratory: {seed_local_demo(get_settings())}")
