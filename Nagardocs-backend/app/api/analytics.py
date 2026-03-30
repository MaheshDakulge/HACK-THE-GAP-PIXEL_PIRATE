from fastapi import APIRouter, Depends
from datetime import datetime, timedelta, timezone

from app.core.database import get_supabase
from app.core.security import get_current_user
from app.services.analytics_service import AnalyticsService

router = APIRouter(prefix="/analytics", tags=["analytics"])
analytics_service = AnalyticsService()


# ✅ EMPTY fallback (safe response)
EMPTY = {
    "total_documents": 0,
    "uploaded_today": 0,
    "processed_count": 0,
    "failed_count": 0,
    "tamper_flagged_count": 0,
    "active_users_today": 0,
    "doc_type_distribution": {},
    "daily_uploads": [],
    "top_uploaders": [],
    "folder_doc_counts": [],
    "avg_ocr_confidence": 0.0,
    "autosort_rate": 0.0,
}


# =========================================================
# 🟢 DEPARTMENT ANALYTICS
# =========================================================
@router.get("/department")
async def get_department_analytics(
    supabase=Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    dept_id = user.get("department_id")
    if not dept_id:
        import concurrent.futures
        # Personal user — scope everything to their own uploads
        docs_q = (
            supabase.table("documents")
            .select("id, doc_type, is_tampered, sort_confidence, ocr_confidence, created_at, folder_id, user_id")
            .eq("user_id", user["id"])
        )
        jobs_q = (
            supabase.table("upload_jobs")
            .select("status, created_at")
            .eq("user_id", user["id"])
        )
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            f_docs = executor.submit(docs_q.execute)
            f_jobs = executor.submit(jobs_q.execute)
            
            docs = f_docs.result()
            jobs = f_jobs.result()

        if not docs.data:
            return {**EMPTY, "cabinets_count": 0}
            
        res = analytics_service.compute_department(
            documents=docs.data,
            jobs=jobs.data or [],
            active_users=[{"id": user["id"]}],
        )
        # Count unique generated folders (+1 for 'My Uploads')
        unique_folders = len(res.get("doc_type_distribution", {}).keys())
        res["cabinets_count"] = unique_folders + 1
        return res

    import concurrent.futures

    # 1. Total exact count query
    total_query = supabase.table("documents").select("id", count="exact").eq("department_id", dept_id)
    if user.get("role") != "admin":
        total_query = total_query.or_(f"is_private.eq.false,user_id.eq.{user['id']}")

    # 2. Last 30 days Documents query (reduces payload vastly)
    thirty_days_ago = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    docs_query = (
        supabase.table("documents")
        .select("id, doc_type, is_tampered, sort_confidence, ocr_confidence, created_at, folder_id, user_id")
        .eq("department_id", dept_id)
        .gte("created_at", thirty_days_ago)
    )
    if user.get("role") != "admin":
        docs_query = docs_query.or_(f"is_private.eq.false,user_id.eq.{user['id']}")

    # 3. Last 30 days Jobs query
    jobs_query = (
        supabase.table("upload_jobs")
        .select("status, created_at")
        .eq("department_id", dept_id)
        .gte("created_at", thirty_days_ago)
    )
    if user.get("role") != "admin":
        jobs_query = jobs_query.eq("user_id", user["id"])

    # 4. Active users query
    cutoff_24h = (datetime.now(timezone.utc) - timedelta(hours=24)).isoformat()
    active_users_query = (
        supabase.table("users")
        .select("id, name")
        .eq("department_id", dept_id)
        .gte("last_seen", cutoff_24h)
    )
    if user.get("role") != "admin":
        active_users_query = active_users_query.eq("id", user["id"])

    # 5. Cabinets count query
    folders_query = supabase.table("folders").select("id", count="exact").eq("department_id", dept_id)

    # 🚀 EXECUTE ALL CONCURRENTLY (5x Speedup!)
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        f_total = executor.submit(total_query.execute)
        f_docs = executor.submit(docs_query.execute)
        f_jobs = executor.submit(jobs_query.execute)
        f_users = executor.submit(active_users_query.execute)
        f_folders = executor.submit(folders_query.execute)

        total_res = f_total.result()
        docs = f_docs.result()
        jobs = f_jobs.result()
        active_users = f_users.result()
        folders = f_folders.result()

    if not total_res.count:
        return EMPTY

    res = analytics_service.compute_department(
        documents=docs.data or [],
        jobs=jobs.data or [],
        active_users=active_users.data or [],
    )
    
    # Override computationally inferred totals with the DB exact count
    res["total_documents"] = total_res.count or 0
    res["cabinets_count"] = folders.count or 0
    return res


# =========================================================
# 🌍 GLOBAL ANALYTICS
# =========================================================
@router.get("/global")
async def get_global_analytics(
    supabase=Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    now = datetime.now(timezone.utc)

    # 🗓️ Start of today (UTC)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0).isoformat()

    # 📄 Total documents
    total = supabase.table("documents").select("id", count="exact").execute()
    total_count = total.count or 0

    # 🚨 Tampered documents
    tampered = (
        supabase.table("documents")
        .select("id", count="exact")
        .eq("is_tampered", True)
        .execute()
    )
    tamper_count = tampered.count or 0

    # 📈 Uploads today
    today_uploads = (
        supabase.table("documents")
        .select("id", count="exact")
        .gte("created_at", today_start)
        .execute()
    )
    today_count = today_uploads.count or 0

    # 👥 Active users (last 24h)
    cutoff_24h = (now - timedelta(hours=24)).isoformat()

    active = (
        supabase.table("users")
        .select("id", count="exact")
        .gte("last_seen", cutoff_24h)
        .execute()
    )
    active_count = active.count or 0

    return {
        "total_documents": total_count,
        "tamper_flagged_count": tamper_count,
        "uploaded_today": today_count,
        "active_users_today": active_count,
    }