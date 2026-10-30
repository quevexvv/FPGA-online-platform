from secrets import compare_digest
from typing import Annotated

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response
from sqlalchemy.orm import Session

from app.core.security import csrf_token, token_digest
from app.db.session import get_db
from app.modules.auth import service
from app.modules.auth.models import AuthSession
from app.modules.auth.repository import revoke_session
from app.modules.auth.schemas import Credentials, CsrfResult, LoginResult, Registration, UserPublic
from app.modules.users.models import User

router = APIRouter(prefix="/auth", tags=["Authentication"])
Db = Annotated[Session, Depends(get_db)]
COOKIE_NAME = "fpga_session"


def check_origin(request: Request) -> None:
    origin = request.headers.get("origin")
    allowed = request.app.state.settings.cors_origins
    if origin is not None and origin not in allowed and origin != str(request.base_url).rstrip("/"):
        raise HTTPException(status_code=403, detail="Origin is not allowed")


def get_current_session(request: Request, db: Db) -> tuple[AuthSession, User]:
    return service.current_session(db, request.cookies.get(COOKIE_NAME))


def get_current_user(
    authenticated: Annotated[tuple[AuthSession, User], Depends(get_current_session)],
) -> User:
    return authenticated[1]


def require_csrf(
    request: Request,
    authenticated: Annotated[tuple[AuthSession, User], Depends(get_current_session)],
    csrf: Annotated[str | None, Header(alias="X-CSRF-Token")] = None,
) -> None:
    check_origin(request)
    if not csrf or not compare_digest(token_digest(csrf), authenticated[0].csrf_hash):
        raise HTTPException(status_code=403, detail="Invalid CSRF token")


@router.post(
    "/register", response_model=UserPublic, status_code=201, dependencies=[Depends(check_origin)]
)
def register(data: Registration, db: Db):
    return service.register(db, data)


@router.post("/login", response_model=LoginResult, dependencies=[Depends(check_origin)])
def login(data: Credentials, request: Request, response: Response, db: Db):
    settings = request.app.state.settings
    user, token, csrf = service.login(
        db, data, request.cookies.get(COOKIE_NAME), settings.session_ttl_seconds
    )
    response.set_cookie(
        COOKIE_NAME,
        token,
        max_age=settings.session_ttl_seconds,
        httponly=True,
        secure=settings.app_env == "production",
        samesite="lax",
        path="/",
    )
    return LoginResult(user=UserPublic.model_validate(user), csrf_token=csrf)


@router.get("/me", response_model=UserPublic)
def me(user: Annotated[User, Depends(get_current_user)]):
    return user


@router.get("/csrf", response_model=CsrfResult, dependencies=[Depends(check_origin)])
def recover_csrf(
    request: Request,
    authenticated: Annotated[tuple[AuthSession, User], Depends(get_current_session)],
):
    return CsrfResult(csrf_token=csrf_token(request.cookies[COOKIE_NAME]))


@router.post("/logout", status_code=204, dependencies=[Depends(require_csrf)])
def logout(request: Request, db: Db):
    revoke_session(db, request.cookies.get(COOKIE_NAME))
    db.commit()
    response = Response(status_code=204)
    response.delete_cookie(
        COOKIE_NAME,
        path="/",
        httponly=True,
        secure=request.app.state.settings.app_env == "production",
        samesite="lax",
    )
    return response
