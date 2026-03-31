from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, BackgroundTasks
from typing import Optional, Annotated, List

from app.core.database import get_supabase, get_supabase_sync
from app.core.security import get_current_user
from app.schemas.upload_schema import UploadJobResponse

from app.services.ocr_service import OCRService
from app.services.tamper_service import TamperService
from app.services.autosort_service import AutoSortService
from app.services.activity_service import activity_service
from app.services.relationship_service import process_relationships

router = APIRouter(prefix="/upload", tags=["upload"])

ocr_service      = OCRService()
tamper_service   = TamperService()
autosort_service = AutoSortService()


# ── Step progress helper ───────────────────────────────────────────────────────
_TOTAL_STEPS = 5

def _update_step(supabase, job_id: str, step: int):
    """Store real processing step in the DB so the status endpoint reflects it."""
    supabase.table("upload_jobs").update({
        "step":         step,
        "progress_pct": round(step / _TOTAL_STEPS, 2),
    }).eq("id", job_id).execute()


# ── Background processing ──────────────────────────────────────────────────────
import asyncio

def _process_document(
    job_id:        str,
    user_id:       str,
    department_id: str,
    file_bytes:    bytes,
    filename:      str,
    language_hint: str,
    doc_type_hint: str,
):
    """Runs in a thread via FastAPI BackgroundTasks — must be synchronous."""
    asyncio.run(_process_document_async(
        job_id, user_id, department_id, file_bytes, filename, language_hint, doc_type_hint
    ))


async def _process_document_async(
    job_id:        str,
    user_id:       str,
    department_id: str,
    file_bytes:    bytes,
    filename:      str,
    language_hint: str,
    doc_type_hint: str,
):
    supabase = get_supabase_sync()

    try:
        supabase.table("upload_jobs").update({
            "status": "processing", "step": 0, "progress_pct": 0.0
        }).eq("id", job_id).execute()

        # Step 1 — Hash + duplicate check
        _update_step(supabase, job_id, 1)
        file_hash = tamper_service.compute_hash(file_bytes)
        dup_check = tamper_service.check_duplicate(file_hash)

        # Step 2 — Storage upload
        _update_step(supabase, job_id, 2)
        storage_path = f"documents/{department_id}/{job_id}/{filename}"
        try:
            supabase.storage.from_("nagardocs").upload(storage_path, file_bytes)
        except Exception:
            print("⚠️ Storage upload skipped (bucket not ready)")

        # Step 3 — OCR / AI extraction
        _update_step(supabase, job_id, 3)
        extracted = await ocr_service.process_document(
            file_bytes=file_bytes,
            filename=filename,
            language_hint=language_hint,
            doc_type_hint=doc_type_hint,
        )

        # Step 4 — Tamper detection
        _update_step(supabase, job_id, 4)
        tamper_flags = extracted.get("tamper_flags", [])

        # ✅ SHORT-CIRCUIT: exact duplicate → reuse existing document
        if dup_check["is_duplicate"]:
            existing_doc_id = dup_check["duplicate_of"]
            supabase.table("upload_jobs").update({
                "status":       "done",
                "document_id":  existing_doc_id,
                "step":         5,
                "progress_pct": 1.0,
                "error_message": f"Duplicate of existing document ID: {existing_doc_id}",
            }).eq("id", job_id).execute()
            print(f"⚠️ Duplicate detected — reusing document {existing_doc_id}")
            return

        is_tampered = len(tamper_flags) > 0

        # Step 5 — Auto-sort into cabinet folder
        # Step 5 — Assign to Pending Classification Holding Area
        _update_step(supabase, job_id, 5)
        folder_id = await autosort_service._get_or_create_folder(
            department_id, "Review Extracted Data", supabase
        )
        # Store the AI's suggestion securely so we can use it upon Confirmation
        suggested_folder = extracted.get("suggested_folder", "Needs Review")
        extracted.setdefault("fields", []).append({
            "label": "system_suggested_folder",
            "value": suggested_folder,
            "confidence": 0.99
        })
        sort_confidence = 0.50 # Hardcoded temporarily since it's waiting for manual review

        # Persist document
        doc_data = {
            "job_id":          job_id,
            "user_id":         user_id,
            "folder_id":       folder_id,
            "filename":        filename,
            "storage_path":    storage_path,
            "doc_type":        extracted.get("doc_type"),
            "language":        extracted.get("language"),
            "ocr_confidence":  extracted.get("confidence"),
            "sort_confidence": sort_confidence,
            "file_hash":       file_hash,
            "tamper_flags":    tamper_flags,
            "is_tampered":     is_tampered,
        }
        if department_id:
            doc_data["department_id"] = department_id
            
        doc_resp = supabase.table("documents").insert(doc_data).execute()

        doc_id = doc_resp.data[0]["id"]

        # Bulk-insert extracted fields
        fields_to_insert = [
            {
                "document_id": doc_id,
                "label":       field.get("label"),
                "value":       field.get("value"),
                "confidence":  field.get("confidence"),
            }
            for field in extracted.get("fields", [])
        ]
        if fields_to_insert:
            supabase.table("document_fields").insert(fields_to_insert).execute()

        # STEP 8.5 — Identity Graph: detect citizens + relationships
        try:
            rel_result = await process_relationships(
                db=supabase,
                document_id=str(doc_id),
                dept_id=str(department_id) if department_id else None,
                doc_type=extracted.get("doc_type", ""),
                extracted_fields=extracted.get("fields", [])
            )
            print(f"Graph: citizens={rel_result['citizens_created']} edges={rel_result['edges_created']} duplicate={rel_result['duplicate_found']}")
            
            # Store relationship result in upload_jobs progress for Flutter to read
            supabase.table("upload_jobs").update({
                "progress": {
                    "citizens_created": rel_result["citizens_created"],
                    "edges_created": rel_result["edges_created"],
                    "duplicate_found": rel_result["duplicate_found"]
                }
            }).eq("id", job_id).execute()
        except Exception as e:
            print(f"Relationship processing failed (non-fatal): {e}")

        activity_service.log_upload(user_id, department_id, doc_id, filename)

        # Mark done
        supabase.table("upload_jobs").update({
            "status":       "done",
            "document_id":  doc_id,
            "step":         5,
            "progress_pct": 1.0,
        }).eq("id", job_id).execute()

    except Exception as exc:
        supabase.table("upload_jobs").update({
            "status":        "failed",
            "error_message": str(exc),
        }).eq("id", job_id).execute()
        print(f"❌ Job failed: {exc}")


# ── Upload endpoint ────────────────────────────────────────────────────────────
@router.post("", response_model=UploadJobResponse, status_code=202)
async def upload_document(
    background_tasks: BackgroundTasks,
    file:             Annotated[UploadFile, File(...)],
    language_hint:    Optional[str] = Form(default="eng"),
    doc_type_hint:    Optional[str] = Form(default=""),
    supabase=Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    file_bytes = await file.read()
    if not file_bytes:
        raise HTTPException(400, "Empty file")

    upload_job_data = {
        "user_id":       user["id"],
        "status":        "queued",
        "filename":      file.filename,
        "step":          0,
        "progress_pct":  0.0,
    }
    if user.get("department_id"):
        upload_job_data["department_id"] = user["department_id"]

    result = supabase.table("upload_jobs").insert(upload_job_data).execute()

    job_id = result.data[0]["id"]

    background_tasks.add_task(
        _process_document,
        job_id,
        user["id"],
        user["department_id"],
        file_bytes,
        file.filename,
        language_hint,
        doc_type_hint,
    )

    return result.data[0]


# ── Active Jobs endpoint ───────────────────────────────────────────────────────
@router.get("/jobs/active", response_model=List[UploadJobResponse])
async def get_active_jobs(
    supabase=Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    result = (
        supabase.table("upload_jobs")
        .select("id,status,filename,step,progress_pct,error_message,document_id,created_at")
        .eq("user_id", user["id"])
        .in_("status", ["queued", "processing"])
        .order("created_at", desc=True)
        .execute()
    )
    return result.data or []


# ── Status endpoint ────────────────────────────────────────────────────────────
@router.get("/status/{job_id}")
async def get_status(
    job_id: str,
    supabase=Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    result = (
        supabase.table("upload_jobs")
        .select("id,status,step,progress_pct,document_id,error_message")
        .eq("id", job_id)
        .eq("user_id", user["id"])
        .execute()
    )
    if not result.data:
        raise HTTPException(404, "Job not found")

    job = result.data[0]

    # Embed full document+fields when done so Flutter needs only one call
    extracted_data = None
    if job["status"] == "done" and job.get("document_id"):
        doc_result = (
            supabase.table("documents")
            .select("*, document_fields(*)")
            .eq("id", job["document_id"])
            .execute()
        )
        if doc_result.data:
            extracted_data = doc_result.data[0]

    return {**job, "extracted_data": extracted_data}