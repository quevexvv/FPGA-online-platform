from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url

backend_dir = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=backend_dir / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "FPGA Online Platform API"
    app_env: Literal["development", "test", "production"] = "development"
    database_url: str = "sqlite:///./fpga-local.sqlite3"
    cors_origins: list[str] = ["http://localhost:5173", "http://127.0.0.1:5173"]

    session_ttl_seconds: int = Field(default=86400, ge=60, le=604800)

    @model_validator(mode="after")
    def validate_production_database(self):
        if self.app_env == "production" and self.database_url.startswith("sqlite"):
            raise ValueError("SQLite is only available for development and tests")
        return self

    @field_validator("database_url")
    @classmethod
    def validate_database_url(cls, value: str) -> str:
        url = make_url(value)
        if url.drivername not in {"postgresql+psycopg", "sqlite"}:
            raise ValueError("DATABASE_URL must use postgresql+psycopg or sqlite")
        if not url.database or (url.drivername == "sqlite" and url.database == ":memory:"):
            raise ValueError("DATABASE_URL must specify a database")
        return value


@lru_cache
def get_settings() -> Settings:
    return Settings()
