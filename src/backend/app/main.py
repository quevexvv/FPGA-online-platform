from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Annotated

from alembic import command
from alembic.config import Config
from fastapi import Depends, FastAPI, HTTPException
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.db.session import create_database_engine, create_session_factory, get_db
from app.modules.auth.router import router as auth_router
from app.modules.labs.router import router as labs_router


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()

    @asynccontextmanager
    async def lifespan(application: FastAPI) -> AsyncIterator[None]:
        engine = create_database_engine(settings)
        application.state.session_factory = create_session_factory(engine)
        try:
            if settings.database_url.startswith("sqlite:"):
                config = Config(str(Path(__file__).resolve().parents[1] / "alembic.ini"))
                with engine.begin() as connection:
                    config.attributes["connection"] = connection
                    command.upgrade(config, "head")
            yield
        finally:
            engine.dispose()

    application = FastAPI(title=settings.app_name, version="0.1.0", lifespan=lifespan)
    application.state.settings = settings
    application.include_router(auth_router)
    application.include_router(labs_router)

    @application.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        errors = [
            {key: error[key] for key in ("type", "loc", "msg") if key in error}
            for error in exc.errors()
        ]
        return JSONResponse(status_code=422, content={"detail": errors})

    @application.middleware("http")
    async def protect_auth_responses(request, call_next):
        response = await call_next(request)
        if request.url.path.startswith("/auth/"):
            response.headers["Cache-Control"] = "no-store"
        return response

    application.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Content-Type", "Authorization", "X-CSRF-Token", "Idempotency-Key"],
    )

    @application.get("/health", tags=["Health"])
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @application.get("/health/db", tags=["Health"])
    def database_health(session: Annotated[Session, Depends(get_db)]) -> dict[str, str]:
        try:
            session.execute(text("SELECT 1"))
        except SQLAlchemyError:
            raise HTTPException(status_code=503, detail="Database unavailable") from None
        return {"status": "ok", "database": "connected"}

    return application


app = create_app()
