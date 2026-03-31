from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel
from datetime import datetime, timedelta
import bcrypt

from app.core.database import get_supabase_sync
from app.core.security import hash_password, verify_password

router = APIRouter(prefix="/auth/pin", tags=["PIN Auth"])

MAX_ATTEMPTS = 5
LOCKOUT_MINUTES = 15

class PinSetRequest(BaseModel):
    user_id: str
    pin: str  # 4-digit string from app

class PinVerifyRequest(BaseModel):
    user_id: str
    pin: str


# ── Set or Reset PIN (new & existing users) ──────────────────────────────────
@router.post("/set")
async def set_pin(req: PinSetRequest):
    if not req.pin.isdigit() or len(req.pin) != 4:
        raise HTTPException(400, "PIN must be exactly 4 digits")

    hashed = hash_password(req.pin)
    
    supabase = get_supabase_sync()
    supabase.table("users").update({
        "pin_hash": hashed,
        "pin_set_at": datetime.utcnow().isoformat(),
        "pin_attempts": 0,
        "pin_locked_until": None
    }).eq("id", req.user_id).execute()

    return {"message": "PIN set successfully"}


# ── Verify PIN on Login ───────────────────────────────────────────────────────
@router.post("/verify")
async def verify_pin_endpoint(req: PinVerifyRequest):
    supabase = get_supabase_sync()
    
    res = supabase.table("users").select(
        "pin_hash, pin_attempts, pin_locked_until"
    ).eq("id", req.user_id).execute()

    if not res.data:
        raise HTTPException(404, "User not found")

    profile = res.data[0]
    if not profile or not profile.get("pin_hash"):
        raise HTTPException(404, "PIN not set for this user")

    # Check lockout
    if profile.get("pin_locked_until"):
        locked_until = datetime.fromisoformat(profile["pin_locked_until"].replace("Z", "+00:00"))
        if datetime.utcnow().astimezone() < locked_until:
            raise HTTPException(423, f"Account locked. Try after {locked_until.strftime('%H:%M')}")

    # Verify
    if not verify_password(req.pin, profile["pin_hash"]):
        new_attempts = profile.get("pin_attempts", 0) + 1
        lock_time = None
        if new_attempts >= MAX_ATTEMPTS:
            lock_time = (datetime.utcnow() + timedelta(minutes=LOCKOUT_MINUTES)).isoformat()

        supabase.table("users").update({
            "pin_attempts": new_attempts,
            "pin_locked_until": lock_time
        }).eq("id", req.user_id).execute()

        remaining = MAX_ATTEMPTS - new_attempts
        raise HTTPException(401, f"Wrong PIN. {max(remaining, 0)} attempts left")

    # Success — reset attempts
    supabase.table("users").update({
        "pin_attempts": 0,
        "pin_locked_until": None
    }).eq("id", req.user_id).execute()

    return {"message": "PIN verified", "success": True}


# ── Check if user has PIN set ─────────────────────────────────────────────────
@router.get("/status/{user_id}")
async def pin_status(user_id: str):
    supabase = get_supabase_sync()
    res = supabase.table("users").select("pin_hash").eq("id", user_id).execute()
    
    has_pin = False
    if res.data:
        has_pin = bool(res.data[0].get("pin_hash"))
        
    return {"has_pin": has_pin}
