from fastapi import APIRouter, HTTPException, status

from app.core.security import (
    hash_password,
    verify_password,
    create_access_token,
)

from app.services.supabase_service import (
    create_user,
    get_user_by_email,
)
from app.services.activity_service import activity_service
from app.core.database import get_supabase_sync

from app.schemas.auth_schema import (
    SignupRequest,
    LoginRequest,
    TokenResponse,
    MessageResponse,
)

router = APIRouter(prefix="/auth", tags=["auth"])


# ─────────────────────────────────────────────
# 📝 SIGNUP
# ─────────────────────────────────────────────

@router.post(
    "/signup",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
)
async def signup(data: SignupRequest):

    # 🔍 check existing user
    existing = get_user_by_email(str(data.email))

    if existing:
        raise HTTPException(
            status_code=400,
            detail="An account with this email already exists.",
        )

    # 🧱 prepare user data
    user_data = {
        "email": str(data.email),
        "password": hash_password(data.password),
        **({"name": data.name} if data.name else {}),
        **({"department_id": data.department_id} if data.department_id else {}),
        **({"designation": data.designation} if data.designation else {}),
        **({"employee_id": data.employee_id} if data.employee_id else {}),
    }

    # 💾 insert user
    create_user(user_data)

    return {
        "message": "Account created successfully. Waiting for admin approval."
    }


# ─────────────────────────────────────────────
# 🔐 LOGIN
# ─────────────────────────────────────────────

@router.post("/login", response_model=TokenResponse)
async def login(data: LoginRequest):

    # 🔍 fetch user
    users = get_user_by_email(str(data.email))

    if not users:
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password.",
        )

    user = users[0]

    # 🔐 verify password
    if not verify_password(data.password, user["password"]):
        raise HTTPException(
            status_code=401,
            detail="Invalid email or password.",
        )

    # 🔍 user status handling
    user_status = (user.get("status") or "pending").strip().lower()

    if user_status == "banned":
        raise HTTPException(
            status_code=403,
            detail="Your account has been banned.",
        )

    if user_status == "pending":
        raise HTTPException(
            status_code=403,
            detail="Your account is pending admin approval.",
        )

    if user_status != "verified":
        raise HTTPException(
            status_code=403,
            detail="Account not approved. Contact your department admin.",
        )

    # 🔥 CORRECT TOKEN CREATION (FIXED)
    access_token = create_access_token({
        "sub": user["id"],                      # ✅ IMPORTANT FIX
        "email": user["email"],
        "role": user.get("role", "user"),
        "department_id": user.get("department_id"),
    })

    # 📝 Log login event to activity_log
    try:
        activity_service.log_login(
            user_id=user["id"],
            department_id=user.get("department_id") or "",
        )
        # Update last_seen timestamp
        supabase = get_supabase_sync()
        supabase.table("users").update({"last_seen": "now()"}).eq("id", user["id"]).execute()
    except Exception:
        pass  # Never block login due to logging failure

    return {
        "access_token": access_token,
        "token_type": "bearer",
        "role": user.get("role", "user"),
        "user_id": user["id"],
    }