from datetime import datetime, timedelta
from typing import Optional

import bcrypt
import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

from app.core.config import settings

# 🔐 Token extractor
oauth2_scheme = HTTPBearer()


# ─────────────────────────────────────────────
# 🔑 PASSWORD HANDLING
# ─────────────────────────────────────────────

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(plain.encode(), hashed.encode())
    except Exception:
        return False


# ─────────────────────────────────────────────
# 🔐 JWT TOKEN CREATION
# ─────────────────────────────────────────────

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()

    expire = datetime.utcnow() + (
        expires_delta or timedelta(minutes=settings.access_token_expire_minutes)
    )

    to_encode.update({"exp": expire})

    return jwt.encode(
        to_encode,
        settings.jwt_secret,
        algorithm=settings.jwt_algorithm,
    )


# ─────────────────────────────────────────────
# 🔐 CURRENT USER (FIXED VERSION)
# ─────────────────────────────────────────────

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(oauth2_scheme),
) -> dict:
    token = credentials.credentials

    try:
        # ✅ Decode YOUR JWT (not Supabase)
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=[settings.jwt_algorithm],
        )

        user_id = payload.get("sub")
        email = payload.get("email")
        role = payload.get("role", "user")
        department_id = payload.get("department_id")

        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token",
            )

        # ✅ Fetch full user details from DB to get Name, Designation, and fallback department_id
        from app.core.database import get_supabase_sync
        supabase = get_supabase_sync()
        db_user_res = supabase.table("users").select("name, designation, status, department_id").eq("id", user_id).execute()
        
        db_name = None
        if db_user_res.data:
            db_name = db_user_res.data[0].get("name")
            if not department_id:
                department_id = db_user_res.data[0].get("department_id")
        
        # Fallback to email prefix if name is empty
        display_name = db_name or email.split("@")[0].title()

        return {
            "id": user_id,
            "email": email,
            "role": role,
            "department_id": department_id,
            "name": display_name,
        }

    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
        )

    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )


# ─────────────────────────────────────────────
# 🔐 ADMIN CHECK
# ─────────────────────────────────────────────

async def get_current_admin(
    user: dict = Depends(get_current_user),
) -> dict:
    if user.get("role") != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin access required for this action.",
        )
    return user