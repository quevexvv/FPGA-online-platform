from datetime import datetime, timedelta, timezone

from fastapi import HTTPException
from sqlalchemy import delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.security import (
    csrf_token,
    hash_password,
    new_token,
    password_hasher,
    token_digest,
    verify_password,
)
from app.modules.auth.models import AuthSession
from app.modules.auth.repository import find_session, find_user, revoke_session
from app.modules.auth.schemas import Credentials, Registration
from app.modules.users.models import User, UserRole


def register(db: Session, data: Registration) -> User:
    if find_user(db, str(data.email)) is not None:
        raise HTTPException(status_code=409, detail="Email is already registered")
    user = User(
        email=str(data.email),
        full_name=data.full_name,
        password_hash=hash_password(data.password.get_secret_value()),
        role=UserRole.student.value,
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        if find_user(db, str(data.email)) is not None:
            raise HTTPException(status_code=409, detail="Email is already registered") from None
        raise
    db.refresh(user)
    return user


def login(db: Session, data: Credentials, old_token: str | None, ttl: int):
    user = find_user(db, str(data.email))
    password = data.password.get_secret_value()
    valid = verify_password(password, user.password_hash if user else None)
    if not valid or user is None or not user.is_active:
        raise HTTPException(status_code=401, detail="Invalid email or password")
    if password_hasher.check_needs_rehash(user.password_hash):
        user.password_hash = hash_password(password)
    now = datetime.now(timezone.utc)
    db.execute(delete(AuthSession).where(AuthSession.expires_at <= now))
    revoke_session(db, old_token)
    token = new_token()
    csrf = csrf_token(token)
    db.add(
        AuthSession(
            token_hash=token_digest(token),
            user_id=user.id,
            csrf_hash=token_digest(csrf),
            expires_at=now + timedelta(seconds=ttl),
        )
    )
    db.commit()
    return user, token, csrf


def current_session(db: Session, token: str | None) -> tuple[AuthSession, User]:
    session = find_session(db, token)
    if session is not None:
        expires = session.expires_at
        if expires.tzinfo is None:
            expires = expires.replace(tzinfo=timezone.utc)
        if expires > datetime.now(timezone.utc):
            user = db.get(User, session.user_id)
            if user is not None and user.is_active:
                return session, user
        db.delete(session)
        db.commit()
    raise HTTPException(status_code=401, detail="Authentication required")
