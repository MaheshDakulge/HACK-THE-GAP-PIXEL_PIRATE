from fastapi import APIRouter, Depends, HTTPException, status
from typing import List, Optional
from pydantic import BaseModel

from app.core.database import get_supabase, SupabaseClient
from app.core.security import get_current_user
from app.schemas.cabinet_schema import (
    FolderCreate, FolderUpdate, FolderResponse,
    DocumentResponse,
)
from app.services.autosort_service import AutoSortService
from app.services.activity_service import activity_service

router = APIRouter(prefix="/cabinet", tags=["cabinet"])
autosort_service = AutoSortService()


# ── Folders — CRUD ─────────────────────────────────────────────────────────────

@router.get("/folders", response_model=List[FolderResponse])
async def list_folders(
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    if not user.get("department_id"):
        # Return categorized synthetic folders for personal documents
        try:
            doc_res = supabase.table("documents").select("id, doc_type").eq("user_id", user["id"]).execute()
            docs = doc_res.data or []
        except Exception:
            docs = []

        from app.services.autosort_service import DOC_TYPE_TO_FOLDER
        
        category_counts = {}
        for doc in docs:
            dt = (doc.get("doc_type") or "").lower().strip()
            folder_name = "Other"
            for k, f_name in DOC_TYPE_TO_FOLDER.items():
                if k in dt:
                    folder_name = f_name
                    break
            category_counts[folder_name] = category_counts.get(folder_name, 0) + 1

        folders = []
        for cat, count in category_counts.items():
            folders.append({
                "id": f"personal_{cat}",
                "department_id": "",
                "created_at": "2024-01-01T00:00:00Z",
                "name": cat,
                "doc_type_affinity": "all",
                "color": "#1a73e8" if cat != "Other" else "#9e9e9e",
                "icon": "folder" if cat != "Other" else "folder_open",
                "is_system": True,
                "is_default_review": False,
                "document_count": count
            })
            
        if not folders:
            # Fallback for entirely new users so their screen isn't completely empty
            folders.append({
                "id": "unassigned",
                "department_id": "",
                "created_at": "2024-01-01T00:00:00Z",
                "name": "My Uploads",
                "doc_type_affinity": "all",
                "color": "#1a73e8",
                "icon": "folder_shared",
                "is_system": True,
                "is_default_review": False,
                "document_count": 0
            })
            
        return folders
    result = (
        supabase.table("folders")
        .select("*, documents(count)")
        .eq("department_id", user["department_id"])
        .order("created_at", desc=False)
        .execute()
    )
    return result.data


@router.post("/folders", response_model=FolderResponse, status_code=status.HTTP_201_CREATED)
async def create_folder(
    payload: FolderCreate,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    result = supabase.table("folders").insert({
        "department_id":     user["department_id"],
        "name":              payload.name,
        "doc_type_affinity": payload.doc_type_affinity,
        "color":             payload.color,
        "icon":              payload.icon,
    }).execute()
    return result.data[0]


@router.put("/folders/{folder_id}", response_model=FolderResponse)
async def update_folder(
    folder_id: str,
    payload: FolderUpdate,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    existing = (
        supabase.table("folders")
        .select("id")
        .eq("id", folder_id)
        .eq("department_id", user["department_id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Folder not found.")

    update_data = payload.model_dump(exclude_none=True)
    result = (
        supabase.table("folders")
        .update(update_data)
        .eq("id", folder_id)
        .execute()
    )
    return result.data[0]


@router.delete("/folders/{folder_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_folder(
    folder_id: str,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    existing = (
        supabase.table("folders")
        .select("id, is_system")
        .eq("id", folder_id)
        .eq("department_id", user["department_id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Folder not found.")

    # FIXED: block deletion of auto-created system folders (e.g. "Needs Review")
    if existing.data[0].get("is_system"):
        raise HTTPException(status_code=403, detail="System folders cannot be deleted.")

    # Move orphaned docs to "Needs Review" before deleting
    needs_review = (
        supabase.table("folders")
        .select("id")
        .eq("department_id", user["department_id"])
        .eq("is_default_review", True)
        .execute()
    )
    if needs_review.data:
        supabase.table("documents").update({
            "folder_id": needs_review.data[0]["id"]
        }).eq("folder_id", folder_id).execute()

    supabase.table("folders").delete().eq("id", folder_id).execute()


# ── Documents across all folders (Recent) ──────────────────────────────────────

@router.get("/documents", response_model=List[DocumentResponse])
async def list_recent_documents(
    limit: int = 5,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    query = (
        supabase.table("documents")
        .select("*, document_fields(*), users(name, designation)")
    )
    # Fallback: users without a department see their own documents
    if user.get("department_id"):
        query = query.eq("department_id", user["department_id"])
        if user.get("role") != "admin":
            query = query.or_(f"is_private.eq.false,user_id.eq.{user['id']}")
    else:
        query = query.eq("user_id", user["id"])

    result = query.order("created_at", desc=True).limit(limit).execute()
    docs = result.data or []
    for doc in docs:
        if not doc.get("users"):
            doc["users"] = {"name": user["name"], "designation": ""}
        elif not doc["users"].get("name"):
            doc["users"]["name"] = user["name"]

    return docs


# ── Documents inside a folder ──────────────────────────────────────────────────

@router.get("/{folder_id}/documents", response_model=List[DocumentResponse])
async def list_folder_documents(
    folder_id: str,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    if folder_id == "unassigned" or folder_id.startswith("personal_"):
        # Handle the synthetic folders for legacy/unassigned users
        query = (
            supabase.table("documents")
            .select("*, document_fields(*), users(name, designation)")
            .eq("user_id", user["id"])
        )
        result = query.order("created_at", desc=True).execute()
        docs = result.data or []
        
        if folder_id.startswith("personal_"):
            cat_name = folder_id.split("personal_", 1)[1]
            from app.services.autosort_service import DOC_TYPE_TO_FOLDER
            filtered_docs = []
            for doc in docs:
                dt = (doc.get("doc_type") or "").lower().strip()
                match = "Other"
                for k, f_name in DOC_TYPE_TO_FOLDER.items():
                    if k in dt:
                        match = f_name
                        break
                if match == cat_name:
                    filtered_docs.append(doc)
            docs = filtered_docs

        for doc in docs:
            if not doc.get("users"):
                doc["users"] = {"name": user["name"], "designation": ""}
            elif not doc["users"].get("name"):
                doc["users"]["name"] = user["name"]
        return docs

    folder = (
        supabase.table("folders")
        .select("id")
        .eq("id", folder_id)
        .eq("department_id", user["department_id"])
        .execute()
    )
    if not folder.data:
        raise HTTPException(status_code=404, detail="Folder not found.")

    query = (
        supabase.table("documents")
        .select("*, document_fields(*), users(name, designation)")
        .eq("folder_id", folder_id)
    )
    if user.get("role") != "admin":
        query = query.or_(f"is_private.eq.false,user_id.eq.{user['id']}")

    result = query.order("created_at", desc=True).execute()
    docs = result.data or []
    for doc in docs:
        if not doc.get("users"):
            doc["users"] = {"name": user["name"], "designation": ""}
        elif not doc["users"].get("name"):
            doc["users"]["name"] = user["name"]

    return docs


@router.get("/documents/{doc_id}")
async def get_document(
    doc_id: str,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    # Fetch by user_id if department_id is missing (legacy / unassigned users)
    query = (
        supabase.table("documents")
        .select("*, document_fields(*), users(name, designation)")
        .eq("id", doc_id)
    )
    if user.get("department_id"):
        query = query.eq("department_id", user["department_id"])
    else:
        query = query.eq("user_id", user["id"])

    result = query.execute()
    if not result.data:
        raise HTTPException(status_code=404, detail="Document not found.")
    return result.data[0]


@router.delete("/documents/{doc_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_document(
    doc_id: str,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    print("DELETE DOC ID:", doc_id)
    print("USER ID:", user.get("id") if user else "None")

    if not doc_id or doc_id == "None":
        raise HTTPException(status_code=400, detail="Invalid document ID")

    if not user or not user.get("id"):
        raise HTTPException(status_code=401, detail="Unauthorized")

    try:
        # Cascade delete fields
        supabase.table("document_fields").delete().eq("document_id", doc_id).execute()
    except Exception:
        pass

    # Delete the document
    query = supabase.table("documents").delete().eq("id", doc_id)
    
    # Regular users can only delete their own documents. Admins can delete within their department.
    if user.get("role") != "admin":
        query = query.eq("user_id", user["id"])
    elif user.get("department_id"):
        query = query.eq("department_id", user["department_id"])

    res = query.execute()

    # If it's a regular user and nothing was deleted, it means it wasn't theirs.
    # Supabase HTTP REST doesn't easily throw an error for 0 rows deleted, 
    # but the action is safe regardless.
    return {"message": "Deleted successfully"}


@router.put("/documents/{doc_id}/move")
async def move_document(
    doc_id: str,
    target_folder: str,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    doc = (
        supabase.table("documents")
        .select("id")
        .eq("id", doc_id)
        .eq("department_id", user["department_id"])
        .execute()
    )
    if not doc.data:
        raise HTTPException(status_code=404, detail="Document not found.")

    folder = (
        supabase.table("folders")
        .select("id")
        .eq("id", target_folder)
        .eq("department_id", user["department_id"])
        .execute()
    )
    if not folder.data:
        raise HTTPException(status_code=404, detail="Target folder not found.")

    result = (
        supabase.table("documents")
        .update({"folder_id": target_folder})
        .eq("id", doc_id)
        .execute()
    )
    activity_service.log(user["id"], user["department_id"], "move",
                         f"Moved document {doc_id} to folder {target_folder}", doc_id)
    return result.data[0]


# ── Manual review ─────────────────────────────────────────────────────────────

class DocumentReviewUpdate(BaseModel):
    doc_type:   Optional[str]  = None
    is_private: Optional[bool] = None

class FieldUpdateItem(BaseModel):
    id:    Optional[str] = None
    label: str
    value: str

@router.put("/documents/{doc_id}")
async def update_document(
    doc_id: str,
    payload: DocumentReviewUpdate,
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    doc = supabase.table("documents").select("user_id").eq("id", doc_id).execute()
    if not doc.data:
        raise HTTPException(404, "Document not found.")
    if user.get("role") != "admin" and doc.data[0]["user_id"] != user["id"]:
        raise HTTPException(403, "Not authorized to modify this document.")

    update_data = payload.model_dump(exclude_unset=True)
    if not update_data:
        return {"status": "no changes"}

    res = supabase.table("documents").update(update_data).eq("id", doc_id).execute()
    return res.data[0]


@router.put("/documents/{doc_id}/fields")
async def update_document_fields(
    doc_id: str,
    fields: List[FieldUpdateItem],
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    doc = supabase.table("documents").select("user_id, doc_type").eq("id", doc_id).execute()
    if not doc.data:
        raise HTTPException(404, "Document not found.")
    if user.get("role") != "admin" and doc.data[0]["user_id"] != user["id"]:
        raise HTTPException(403, "Not authorized to modify this document.")

    # Fetch old fields to preserve system suggestions and trigger classification
    old_fields_res = supabase.table("document_fields").select("*").eq("document_id", doc_id).execute()
    old_fields = old_fields_res.data or []
    
    system_suggested_folder = None
    for f in old_fields:
        if f.get("label") == "system_suggested_folder":
            system_suggested_folder = f.get("value")

    # Clear existing visible fields (we keep system ones logic internal if needed)
    supabase.table("document_fields").delete().eq("document_id", doc_id).execute()

    inserts = [
        {"document_id": doc_id, "label": f.label, "value": f.value, "confidence": 1.0}
        for f in fields
        if not f.label.startswith("system_") # prevent user overriding system fields
    ]
    
    if system_suggested_folder:
        inserts.append({
            "document_id": doc_id,
            "label": "system_suggested_folder",
            "value": system_suggested_folder,
            "confidence": 1.0
        })

    if inserts:
        supabase.table("document_fields").insert(inserts).execute()

    # ---- Trigger Deferred Auto-Classification ----
    from app.services.autosort_service import AutoSortService
    autosort_service = AutoSortService()
    
    # We need the doc_type of the document
    doc_type = doc.data[0].get("doc_type", "")
    folder_id, sort_confidence = await autosort_service.classify(
        doc_type=doc_type,
        fields=[i for i in inserts if not i["label"].startswith("system_")],
        department_id=user["department_id"],
        suggested_folder_name=system_suggested_folder,
        supabase=supabase,
    )
    
    if folder_id:
        supabase.table("documents").update({
            "folder_id": folder_id,
            "sort_confidence": sort_confidence
        }).eq("id", doc_id).execute()

    return {"status": "fields updated and document auto-classified successfully"}


# ── Auto-Sort ─────────────────────────────────────────────────────────────────

@router.post("/autosort")
async def run_autosort(
    supabase: SupabaseClient = Depends(get_supabase),
    user: dict = Depends(get_current_user),
):
    review_folder = (
        supabase.table("folders")
        .select("id")
        .eq("department_id", user["department_id"])
        .eq("is_default_review", True)
        .execute()
    )
    if not review_folder.data:
        return {"sorted": 0, "still_pending": 0, "message": "No review folder found."}

    review_folder_id = review_folder.data[0]["id"]

    unsorted = (
        supabase.table("documents")
        .select("*, document_fields(*)")
        .eq("folder_id", review_folder_id)
        .execute()
    )
    if not unsorted.data:
        return {"sorted": 0, "still_pending": 0}

    sorted_count  = 0
    pending_count = 0

    for doc in unsorted.data:
        folder_id, confidence = await autosort_service.classify(
            doc_type=doc.get("doc_type", ""),
            fields=doc.get("document_fields", []),
            department_id=user["department_id"],
            supabase=supabase,
        )
        if folder_id and folder_id != review_folder_id:
            supabase.table("documents").update({
                "folder_id":       folder_id,
                "sort_confidence": confidence,
            }).eq("id", doc["id"]).execute()
            sorted_count += 1
        else:
            pending_count += 1

    return {"sorted": sorted_count, "still_pending": pending_count}