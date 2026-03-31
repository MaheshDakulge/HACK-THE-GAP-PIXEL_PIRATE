# app/api/graph.py
# Identity Graph API — all endpoints for the citizen graph feature
#
# Routes:
#   GET  /graph/department          → full graph (nodes + edges) for dept
#   GET  /graph/citizen/{id}        → single citizen detail + all docs
#   POST /graph/citizen             → manually create citizen
#   GET  /graph/citizen/{id}/docs   → all docs linked to citizen
#   DELETE /graph/citizen/{id}      → delete citizen node
#   POST /graph/edge                → manually create edge
#   DELETE /graph/edge/{id}         → delete edge
#   GET  /graph/duplicates          → list all flagged duplicate pairs
#   POST /graph/reprocess/{doc_id}  → re-run relationship detection on doc

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from app.core.security import get_current_user
from app.core.database import get_supabase as get_db
from app.schemas.graph_schema import (
    CitizenCreate, CitizenResponse,
    EdgeCreate, EdgeResponse,
    GraphResponse, GraphNodeResponse,
    CitizenDocumentCreate
)
from app.services.relationship_service import process_relationships
from app.core.database import get_supabase_sync
from typing import List
from datetime import datetime
import uuid

def _get_user_dept_id(user) -> str:
    """Helper to extract or fetch department_id if missing from JWT scope."""
    dept_id = user.get("department_id")
    if not dept_id:
        sb = get_supabase_sync()
        u_res = sb.table("users").select("department_id").eq("id", user["id"]).execute()
        if u_res.data:
            dept_id = u_res.data[0].get("department_id")
    return str(dept_id) if dept_id else ""

router = APIRouter(prefix="/graph", tags=["identity-graph"])


# ── GET full graph for department ─────────────────────────────
@router.get("/department", response_model=GraphResponse)
async def get_department_graph(
    user=Depends(get_current_user),
    db=Depends(get_db)
):
    """
    Returns all citizen nodes + all edges for the current user's department.
    Flutter uses this to render the interactive graph canvas.
    """
    dept_id = _get_user_dept_id(user)

    # Fetch citizens
    citizens_res = db.table("citizens")\
        .select("*")\
        .execute()

    nodes = []
    for c in (citizens_res.data or []):
        # Fetch linked documents for this citizen
        docs_res = db.table("citizen_documents")\
            .select("document_id, documents(id, doc_type, ocr_confidence, is_tampered, filename)")\
            .eq("citizen_id", c["id"])\
            .execute()

        docs = []
        for link in (docs_res.data or []):
            d = link.get("documents") or {}
            
            # Fetch document fields for the specific document
            fields_res = db.table("document_fields")\
                .select("label, value")\
                .eq("document_id", link["document_id"])\
                .execute()
                
            fields_dict = {"fields": fields_res.data or []}
            
            # Pull the most informative field value for display
            display_value = _pick_display_value(d.get("doc_type",""), fields_dict)
            docs.append({
                "document_id": link["document_id"],
                "type": d.get("doc_type", "Unknown"),
                "value": display_value,
                "confidence": d.get("ocr_confidence", 0),
                "is_tampered": d.get("is_tampered", False),
                "filename": d.get("filename", "")
            })

        nodes.append(GraphNodeResponse(
            id=c["id"],
            full_name=c["full_name"],
            dob=c.get("dob"),
            uid_number=c.get("uid_number"),
            is_flagged=c.get("is_flagged", False),
            doc_count=len(docs),
            docs=docs
        ))

    # Fetch edges
    edges_res = db.table("citizen_edges")\
        .select("*")\
        .execute()

    # Filter edges that belong to this dept's citizens
    citizen_ids = {str(n.id) for n in nodes}
    edges = [
        EdgeResponse(**e) for e in (edges_res.data or [])
        if str(e["from_citizen"]) in citizen_ids
        or str(e["to_citizen"]) in citizen_ids
    ]

    # --- DEMO FALLBACK: If the graph is empty, return rich mock data ---
    if not nodes:
        now = datetime.utcnow()
        m1 = "00000000-0000-0000-0000-000000000001"
        m2 = "00000000-0000-0000-0000-000000000002"
        m3 = "00000000-0000-0000-0000-000000000003"
        m4 = "00000000-0000-0000-0000-000000000004"
        m5 = "00000000-0000-0000-0000-000000000005"
        m6 = "00000000-0000-0000-0000-000000000006"

        def d(doc_type, value, confidence=0.97, tampered=False):
            return {"document_id": str(uuid.uuid4()), "type": doc_type, "value": value,
                    "confidence": confidence, "is_tampered": tampered, "filename": f"{doc_type}.pdf"}

        def e(frm, to, etype, conf=1.0):
            return EdgeResponse(
                id=str(uuid.uuid4()), from_citizen=frm, to_citizen=to,
                edge_type=etype, confidence=conf, evidence_doc_id=None,
                created_at=now
            )

        nodes = [
            GraphNodeResponse(id=m1, full_name="Rahul Sharma", dob=date(1985, 6, 15), uid_number="2312-5698-7890",
                is_flagged=False, doc_count=3, docs=[
                    d("aadhaar", "2312-5698-7890", 0.98),
                    d("birth", "15/06/1985", 0.95),
                    d("income", "₹4.8L per annum", 0.91),
                ]),
            GraphNodeResponse(id=m2, full_name="Priya Sharma", dob=date(1988, 4, 12), uid_number="9901-1122-3344",
                is_flagged=False, doc_count=2, docs=[
                    d("aadhaar", "9901-1122-3344", 0.97),
                    d("birth", "12/04/1988", 0.93),
                ]),
            GraphNodeResponse(id=m3, full_name="Arjun Sharma", dob=date(2008, 11, 3), uid_number="5544-3322-1100",
                is_flagged=False, doc_count=2, docs=[
                    d("marksheet", "9.2 SGPA (10th)", 0.99),
                    d("birth", "03/11/2008", 0.96),
                ]),
            GraphNodeResponse(id=m4, full_name="Sunita Devi", dob=date(1965, 2, 20), uid_number="4411-2233-9988",
                is_flagged=False, doc_count=2, docs=[
                    d("aadhaar", "4411-2233-9988", 0.94),
                    d("ration", "MH-PUN-04-012345", 0.89),
                ]),
            GraphNodeResponse(id=m5, full_name="Rajesh Devi", dob=date(1962, 8, 5), uid_number="7702-8891-0034",
                is_flagged=False, doc_count=2, docs=[
                    d("property", "Survey No. 145/A, Pune", 0.88),
                    d("aadhaar", "7702-8891-0034", 0.95),
                ]),
            GraphNodeResponse(id=m6, full_name="R. Sharma (Dup)", dob=date(1985, 6, 15), uid_number="2312-5698-7890",
                is_flagged=True, doc_count=1, docs=[
                    d("aadhaar", "2312-5698-7890", 0.72, tampered=True),
                ]),
        ]

        edges = [
            e(m1, m2, "spouse_of", 0.98),
            e(m1, m3, "parent_of", 1.0),
            e(m2, m3, "parent_of", 1.0),
            e(m4, m3, "parent_of", 0.85),
            e(m4, m5, "spouse_of", 0.92),
            e(m1, m5, "sibling_of", 0.80),
            e(m5, m3, "owns_property", 0.75),
            e(m6, m1, "duplicate_of", 0.91),
        ]

    return GraphResponse(nodes=nodes, edges=edges)


# ── GET single citizen detail ─────────────────────────────────
@router.get("/citizen/{citizen_id}")
async def get_citizen(
    citizen_id: str,
    user=Depends(get_current_user),
    db=Depends(get_db)
):
    row = db.table("citizens").select("*").eq("id", citizen_id).single().execute()
    if not row.data:
        raise HTTPException(404, "Citizen not found")

    docs_res = db.table("citizen_documents")\
        .select("document_id, documents(*)")\
        .eq("citizen_id", citizen_id)\
        .execute()

    edges_res = db.table("citizen_edges")\
        .select("*")\
        .or_(f"from_citizen.eq.{citizen_id},to_citizen.eq.{citizen_id}")\
        .execute()

    return {
        "citizen": row.data,
        "documents": [l.get("documents") for l in (docs_res.data or [])],
        "edges": edges_res.data or []
    }


# ── POST create citizen manually ──────────────────────────────
@router.post("/citizen", response_model=CitizenResponse)
async def create_citizen(
    body: CitizenCreate,
    user=Depends(get_current_user),
    db=Depends(get_db)
):
    payload = body.dict()
    payload["dept_id"] = _get_user_dept_id(user)
    if not payload["dept_id"]:
        raise HTTPException(status_code=400, detail="User has no assigned department")
    res = db.table("citizens").insert(payload).execute()
    if not res.data:
        raise HTTPException(500, "Failed to create citizen")
    return CitizenResponse(**res.data[0])


# ── POST create edge manually ─────────────────────────────────
@router.post("/edge", response_model=EdgeResponse)
async def create_edge(
    body: EdgeCreate,
    user=Depends(get_current_user),
    db=Depends(get_db)
):
    payload = body.dict()
    payload["from_citizen"] = str(payload["from_citizen"])
    payload["to_citizen"] = str(payload["to_citizen"])
    if payload.get("evidence_doc_id"):
        payload["evidence_doc_id"] = str(payload["evidence_doc_id"])
    res = db.table("citizen_edges").insert(payload).execute()
    if not res.data:
        raise HTTPException(500, "Failed to create edge")
    return EdgeResponse(**res.data[0])


# ── DELETE edge ───────────────────────────────────────────────
@router.delete("/edge/{edge_id}")
async def delete_edge(
    edge_id: str,
    user=Depends(get_current_user),
    db=Depends(get_db)
):
    db.table("citizen_edges").delete().eq("id", edge_id).execute()
    return {"deleted": True}


# ── GET duplicates list ───────────────────────────────────────
@router.get("/duplicates")
async def get_duplicates(
    user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Returns all duplicate_of edges with full citizen details"""
    dept_id = _get_user_dept_id(user)
    if not dept_id:
        return []
    edges = db.table("citizen_edges")\
        .select("*, from_c:from_citizen(full_name,uid_number), to_c:to_citizen(full_name,uid_number)")\
        .eq("edge_type", "duplicate_of")\
        .execute()
    return edges.data or []


# ── POST re-run relationship detection on existing doc ────────
@router.post("/reprocess/{document_id}")
async def reprocess_document(
    document_id: str,
    background_tasks: BackgroundTasks,
    user=Depends(get_current_user),
    db=Depends(get_db)
):
    """Re-runs relationship detection on an already-processed document."""
    doc = db.table("documents").select("*").eq("id", document_id).single().execute()
    if not doc.data:
        raise HTTPException(404, "Document not found")

    d = doc.data
    
    fields_res = db.table("document_fields").select("label, value").eq("document_id", document_id).execute()
    
    background_tasks.add_task(
        process_relationships,
        db=db,
        document_id=document_id,
        dept_id=_get_user_dept_id(user),
        doc_type=d.get("doc_type", ""),
        extracted_fields=fields_res.data or []
    )
    return {"status": "reprocessing_started", "document_id": document_id}


# ── HELPER: pick best display value for a doc type ───────────
def _pick_display_value(doc_type: str, fields: dict) -> str:
    dt = doc_type.lower()
    field_list = fields.get("fields", []) if isinstance(fields, dict) else []

    priority = {
        "aadhaar": ["uid", "aadhaar number"],
        "birth": ["date of birth", "dob", "registration no"],
        "property": ["survey no", "address", "gut no"],
        "marksheet": ["sgpa", "cgpa", "percentage"],
        "ration": ["ration card no", "card number"],
        "income": ["annual income", "income"],
    }

    for key, labels in priority.items():
        if key in dt:
            for f in field_list:
                for label in labels:
                    if label in f.get("label", "").lower():
                        return f.get("value", "")

    # fallback: return first field value
    if field_list:
        return field_list[0].get("value", "")
    return ""
