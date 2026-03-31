from fastapi import APIRouter, Depends, HTTPException, Query
from typing import Optional, List
from pydantic import BaseModel
from datetime import datetime, timedelta, timezone

class BulkReviewPayload(BaseModel):
    document_ids: List[str]
    action: str  # "approve" | "reject"

from app.core.database import get_supabase
from app.core.security import get_current_admin

router = APIRouter(prefix="/admin", tags=["admin"])


# =========================================================
# 🟢 TAB 1: PRESENCE (ONLINE USERS)
# =========================================================
@router.get("/presence")
async def get_presence(supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    now = datetime.now(timezone.utc)
    cutoff_online = (now - timedelta(minutes=5)).isoformat()
    cutoff_away   = (now - timedelta(minutes=30)).isoformat()

    query = supabase.table("users").select("id, name, designation, last_seen, role")
    
    # ✅ Department filtering permanently removed by user command for global visibility
    users = query.execute()

    result = []

    for user_item in (users.data or []):
        last_seen = user_item.get("last_seen") or ""

        if last_seen >= cutoff_online:
            status = "online"
        elif last_seen >= cutoff_away:
            status = "away"
        else:
            status = "offline"

        result.append({**user_item, "presence_status": status})

    order = {"online": 0, "away": 1, "offline": 2}
    result.sort(key=lambda x: order[x["presence_status"]])

    return result


# =========================================================
# 📊 TAB 2: ACTIVITY FEED
# =========================================================
@router.get("/activity")
async def get_activity(
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    supabase=Depends(get_supabase), 
    admin: dict = Depends(get_current_admin)
):
    offset = (page - 1) * limit
    # Fetch raw activity logs (no joins - they fail silently with PostgREST)
    query = supabase.table("activity_log").select(
        "id, action, detail, created_at, user_id, document_id, department_id"
    )

    # ✅ Department filtering permanently removed by user command for global visibility
    result = query.order("created_at", desc=True).range(offset, offset + limit - 1).execute()
    logs = result.data or []

    if not logs:
        return []

    # Enrich with user names via separate lookup
    user_ids = list({r["user_id"] for r in logs if r.get("user_id")})
    users_map = {}
    if user_ids:
        users_result = supabase.table("users").select("id, name, designation").in_("id", user_ids).execute()
        users_map = {u["id"]: u for u in (users_result.data or [])}

    # Enrich with document filenames via separate lookup
    doc_ids = list({r["document_id"] for r in logs if r.get("document_id")})
    docs_map = {}
    if doc_ids:
        docs_result = supabase.table("documents").select("id, filename, doc_type").in_("id", doc_ids).execute()
        docs_map = {d["id"]: d for d in (docs_result.data or [])}

    # Merge enrichment into each log row
    enriched = []
    for log in logs:
        u = users_map.get(log.get("user_id"), {})
        d = docs_map.get(log.get("document_id"), {})
        enriched.append({
            **log,
            "users": {"name": u.get("name", "Unknown"), "designation": u.get("designation", "")},
            "documents": {"filename": d.get("filename", ""), "doc_type": d.get("doc_type", "")} if d else None,
        })

    return enriched


# DEBUG: returns raw activity_log rows without any filter (remove in production)
@router.get("/activity/debug")
async def debug_activity(supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    raw = supabase.table("activity_log").select("*").order("created_at", desc=True).limit(20).execute()
    return {
        "admin_dept": admin.get("department_id"),
        "total_rows": len(raw.data or []),
        "rows": raw.data or [],
    }


# =========================================================
# 🚨 TAB 3: SECURITY ALERTS
# =========================================================
@router.get("/security")
async def get_security_alerts(supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    # 🚨 Tampered documents
    tamper_query = supabase.table("documents").select(
        "id, filename, doc_type, tamper_flags, created_at, users(name)"
    ).eq("is_tampered", True)
    tampered_docs = tamper_query.order("created_at", desc=True).limit(10).execute()

    # ❌ Failed jobs
    jobs_query = supabase.table("upload_jobs").select(
        "id, filename, error_message, created_at, users(name)"
    ).eq("status", "failed")
    failed_jobs = jobs_query.order("created_at", desc=True).limit(10).execute()

    # 🛌 Stale or suspicious accounts
    now = datetime.now(timezone.utc)
    stale_cutoff = (now - timedelta(days=30)).isoformat()
    
    stale_query = supabase.table("users").select(
        "id, name, email, last_seen, status"
    ).lt("last_seen", stale_cutoff)
    stale_users = stale_query.execute()

    return {
        "tampered_documents": tampered_docs.data or [],
        "failed_jobs": failed_jobs.data or [],
        "stale_accounts": stale_users.data or [],
        "summary": {
            "tamper_count": len(tampered_docs.data or []),
            "failed_count": len(failed_jobs.data or []),
            "stale_count": len(stale_users.data or []),
        },
    }


# =========================================================
# 👑 ADMIN ACTIONS
# =========================================================
@router.post("/resolve-tamper/{doc_id}")
async def resolve_tamper_flag(doc_id: str, supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    doc = (
        supabase.table("documents")
        .select("id, filename")
        .eq("id", doc_id)
        .execute()
    )

    if not doc.data:
        raise HTTPException(404, "Document not found")

    supabase.table("documents").update({
        "is_tampered": False,
        "tamper_flags": []
    }).eq("id", doc_id).execute()

    return {"message": "Tamper flag cleared"}


@router.post("/bulk-review")
async def bulk_review(
    payload: BulkReviewPayload,
    supabase=Depends(get_supabase),
    admin: dict = Depends(get_current_admin)
):
    if not payload.document_ids:
        raise HTTPException(400, "No documents specified.")

    try:
        if payload.action == "approve":
            # Approving means completely trusting it — turning off all tamper flags natively
            # Additionally, we auto-classify the document now that it's validated
            from app.services.autosort_service import AutoSortService
            autosort_service = AutoSortService()
            
            docs_to_approve = (
                supabase.table("documents")
                .select("id, department_id, doc_type, document_fields(*)")
                .in_("id", payload.document_ids)
                .execute()
            )
            
            approved_count = 0
            for doc in (docs_to_approve.data or []):
                system_suggested_folder = None
                clean_fields = []
                for f in (doc.get("document_fields") or []):
                    if f.get("label") == "system_suggested_folder":
                        system_suggested_folder = f.get("value")
                    elif not f.get("label", "").startswith("system_"):
                        clean_fields.append(f)
                
                folder_id, sort_confidence = await autosort_service.classify(
                    doc_type=doc.get("doc_type", ""),
                    fields=clean_fields,
                    department_id=doc.get("department_id"),
                    suggested_folder_name=system_suggested_folder,
                    supabase=supabase,
                )
                
                update_payload = {"is_tampered": False, "tamper_flags": []}
                if folder_id:
                    update_payload["folder_id"] = folder_id
                    update_payload["sort_confidence"] = sort_confidence
                    
                supabase.table("documents").update(update_payload).eq("id", doc["id"]).execute()
                approved_count += 1
                
            return {"message": f"Successfully approved and categorized {approved_count} documents."}
            
        elif payload.action == "reject":
            # Rejecting means the admin deemed them invalid and removes them natively
            res = (
                supabase.table("documents")
                .delete()
                .in_("id", payload.document_ids)
                .execute()
            )
            count = len(res.data) if res.data else 0
            return {"message": f"Successfully rejected and wiped {count} documents."}
            
        else:
            raise HTTPException(400, "Action must be 'approve' or 'reject'.")
            
    except Exception as e:
        raise HTTPException(500, f"Bulk operation failed: {e}")


@router.post("/ban-user/{user_id}")
async def ban_user(user_id: str, supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    if user_id == admin["id"]:
        raise HTTPException(400, "Cannot ban yourself")

    supabase.table("users").update({"status": "banned"}).eq("id", user_id).execute()

    return {"message": "User banned"}


@router.post("/approve-user/{user_id}")
async def approve_user(user_id: str, supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    if user_id == admin["id"]:
        raise HTTPException(400, "Cannot approve yourself")

    supabase.table("users").update({"status": "verified"}).eq("id", user_id).execute()

    return {"message": "User approved"}


@router.post("/promote-user/{user_id}")
async def promote_user(user_id: str, supabase=Depends(get_supabase), admin: dict = Depends(get_current_admin)):
    if user_id == admin["id"]:
        raise HTTPException(400, "Cannot promote yourself")

    supabase.table("users").update({"role": "admin"}).eq("id", user_id).execute()

    return {"message": "User promoted to admin"}


@router.get("/users")
async def list_users(
    status: Optional[str] = Query(default=None),
    supabase=Depends(get_supabase),
    admin: dict = Depends(get_current_admin),
):
    query = supabase.table("users").select("*")
    
    if status:
        query = query.eq("status", status)

    result = query.execute()
    return result.data or []