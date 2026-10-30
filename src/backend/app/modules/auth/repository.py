from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core.security import token_digest
from app.modules.auth.models import AuthSession
from app.modules.users.models import User


def find_user(db: Session, email: str) -> User | None:
    return db.scalar(select(User).where(func.lower(User.email) == email))


def find_session(db: Session, token: str | None) -> AuthSession | None:
    return db.get(AuthSession, token_digest(token)) if token else None


def revoke_session(db: Session, token: str | None) -> None:
    if token:
        db.execute(delete(AuthSession).where(AuthSession.token_hash == token_digest(token)))
