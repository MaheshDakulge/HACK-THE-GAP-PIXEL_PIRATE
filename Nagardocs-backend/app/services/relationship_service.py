# app/services/relationship_service.py
#
# THE BRAIN — after every document is processed by GPT, this service:
#   1. Extracts citizen info from the document fields
#   2. Finds or creates citizen nodes
#   3. Detects family relationships from document type + fields
#   4. Creates edges in citizen_edges table
#   5. Flags duplicates

import re
import json
import openai
from uuid import UUID
from typing import Optional
from app.utils.logger import logger


# ── Fuzzy name similarity (no external deps) ─────────────────
def _name_similarity(a: str, b: str) -> float:
    """Simple token overlap similarity, 0.0–1.0"""
    a_tokens = set(a.lower().split())
    b_tokens = set(b.lower().split())
    if not a_tokens or not b_tokens:
        return 0.0
    overlap = len(a_tokens & b_tokens)
    return overlap / max(len(a_tokens), len(b_tokens))


def _find_field(fields: list, *labels) -> Optional[str]:
    """Find extracted field value by label (case-insensitive)"""
    for f in fields:
        for label in labels:
            if label.lower() in f.get("label", "").lower():
                return f.get("value", "").strip()
    return None


# ── Main entry point — called from upload.py after OCR+GPT ───
async def process_relationships(
    db,
    document_id: str,
    dept_id: str,
    doc_type: str,
    extracted_fields: list,  # [{label, value, confidence}]
) -> dict:
    """
    Called right after document is saved to DB.
    Returns {citizens_created, edges_created, duplicate_found}
    """
    result = {"citizens_created": 0, "edges_created": 0, "duplicate_found": False}
    doc_type_lower = doc_type.lower()

    try:
        # ── BIRTH CERTIFICATE ─────────────────────────────────
        if "birth" in doc_type_lower:
            child_name = _find_field(extracted_fields, "name", "child name", "full name")
            father_name = _find_field(extracted_fields, "father", "father's name")
            mother_name = _find_field(extracted_fields, "mother", "mother's name")
            dob_str = _find_field(extracted_fields, "date of birth", "dob", "birth date")

            if child_name:
                child_id = await _find_or_create_citizen(db, dept_id, child_name, dob_str, document_id)
                result["citizens_created"] += 1

                if father_id := await _find_or_create_citizen(db, dept_id, father_name, None, document_id):
                    await _create_edge(db, father_id, child_id, "parent_of", document_id)
                    result["edges_created"] += 1

                if mother_id := await _find_or_create_citizen(db, dept_id, mother_name, None, document_id):
                    await _create_edge(db, mother_id, child_id, "parent_of", document_id)
                    result["edges_created"] += 1

        # ── AADHAAR / ID CARD ─────────────────────────────────
        elif any(x in doc_type_lower for x in ["aadhaar", "id card", "voter"]):
            name = _find_field(extracted_fields, "name", "full name")
            dob_str = _find_field(extracted_fields, "dob", "date of birth", "year of birth")
            uid = _find_field(extracted_fields, "aadhaar", "uid", "voter id", "id number")

            if name:
                citizen_id = await _find_or_create_citizen(db, dept_id, name, dob_str, document_id, uid_number=uid)
                result["citizens_created"] += 1

                # Duplicate check
                dup = await _check_duplicate(db, dept_id, name, dob_str, citizen_id)
                if dup:
                    await _create_edge(db, citizen_id, dup, "duplicate_of", document_id, confidence=0.85)
                    await db.table("citizens").update({"is_flagged": True}).eq("id", str(citizen_id)).execute()
                    result["duplicate_found"] = True

        # ── PROPERTY RECORD / 7-12 EXTRACT ───────────────────
        elif any(x in doc_type_lower for x in ["property", "7/12", "7-12", "land"]):
            owner_name = _find_field(extracted_fields, "owner", "owner name", "khatedar")
            survey = _find_field(extracted_fields, "survey", "survey no", "gut no")

            if owner_name:
                owner_id = await _find_or_create_citizen(db, dept_id, owner_name, None, document_id)
                result["citizens_created"] += 1

                # Self-referential "owns_property" edge — we use a special property node pattern:
                # create a second "citizen" entry representing the property itself
                # For hackathon: just store it as a doc link
                await _link_document_to_citizen(db, owner_id, document_id)

        # ── MARKSHEET ─────────────────────────────────────────
        elif any(x in doc_type_lower for x in ["marksheet", "mark sheet", "result"]):
            student_name = _find_field(extracted_fields, "name", "student name", "candidate name")
            dob_str = _find_field(extracted_fields, "dob", "date of birth")

            if student_name:
                citizen_id = await _find_or_create_citizen(db, dept_id, student_name, dob_str, document_id)
                result["citizens_created"] += 1

        # ── RATION CARD ───────────────────────────────────────
        elif "ration" in doc_type_lower:
            head_name = _find_field(extracted_fields, "head", "family head", "name")
            members_raw = _find_field(extracted_fields, "members", "family members")

            if head_name:
                head_id = await _find_or_create_citizen(db, dept_id, head_name, None, document_id)
                result["citizens_created"] += 1

                # Parse comma-separated member names if present
                if members_raw:
                    for mem in members_raw.split(","):
                        mem = mem.strip()
                        if mem and mem.lower() != head_name.lower():
                            mem_id = await _find_or_create_citizen(db, dept_id, mem, None, document_id)
                            await _create_edge(db, head_id, mem_id, "sibling_of", document_id, confidence=0.7)
                            result["edges_created"] += 1

    except Exception as e:
        logger.error(f"relationship_service error for doc {document_id}: {e}")

    return result


# ── HELPER: find existing citizen or create new one ───────────
async def _find_or_create_citizen(
    db, dept_id: str, name: Optional[str], dob_str: Optional[str],
    document_id: str, uid_number: Optional[str] = None
) -> Optional[str]:
    if not name or len(name.strip()) < 2:
        return None

    name = name.strip()

    # Search existing citizens in this dept
    existing = db.table("citizens").select("id,full_name").eq("dept_id", dept_id).execute()

    for row in (existing.data or []):
        sim = _name_similarity(row["full_name"], name)
        if sim >= 0.85:
            # Found match — link document and return existing ID
            await _link_document_to_citizen(db, row["id"], document_id)
            return row["id"]

    # Create new citizen
    payload = {"dept_id": dept_id, "full_name": name}
    if dob_str:
        # Try to parse date
        try:
            from dateutil import parser as dp
            payload["dob"] = dp.parse(dob_str, dayfirst=True).date().isoformat()
        except Exception:
            pass
    if uid_number:
        payload["uid_number"] = uid_number

    new_row = db.table("citizens").insert(payload).execute()
    if new_row.data:
        new_id = new_row.data[0]["id"]
        await _link_document_to_citizen(db, new_id, document_id)
        return new_id

    return None


# ── HELPER: create edge (avoid duplicates) ────────────────────
async def _create_edge(
    db, from_id: str, to_id: str, edge_type: str,
    document_id: str, confidence: float = 1.0
):
    # Check if edge already exists
    check = db.table("citizen_edges")\
        .select("id")\
        .eq("from_citizen", from_id)\
        .eq("to_citizen", to_id)\
        .eq("edge_type", edge_type)\
        .execute()

    if not check.data:
        db.table("citizen_edges").insert({
            "from_citizen": from_id,
            "to_citizen": to_id,
            "edge_type": edge_type,
            "evidence_doc_id": document_id,
            "confidence": confidence
        }).execute()


# ── HELPER: link document to citizen ─────────────────────────
async def _link_document_to_citizen(db, citizen_id: str, document_id: str):
    try:
        db.table("citizen_documents").upsert({
            "citizen_id": citizen_id,
            "document_id": document_id,
            "role": "subject"
        }, on_conflict="citizen_id,document_id").execute()
    except Exception:
        pass


# ── HELPER: duplicate check ───────────────────────────────────
async def _check_duplicate(
    db, dept_id: str, name: str, dob_str: Optional[str], exclude_id: str
) -> Optional[str]:
    """Returns citizen_id if a duplicate is found, else None"""
    existing = db.table("citizens")\
        .select("id,full_name,dob")\
        .eq("dept_id", dept_id)\
        .neq("id", exclude_id)\
        .execute()

    for row in (existing.data or []):
        sim = _name_similarity(row["full_name"], name)
        if sim >= 0.80:
            # If DOB also matches, very high confidence duplicate
            if dob_str and row.get("dob"):
                try:
                    from dateutil import parser as dp
                    d1 = dp.parse(dob_str, dayfirst=True).date()
                    d2 = dp.parse(row["dob"]).date()
                    if d1 == d2:
                        return row["id"]
                except Exception:
                    pass
            elif sim >= 0.92:
                # Very similar name with no DOB — still flag
                return row["id"]

    return None
