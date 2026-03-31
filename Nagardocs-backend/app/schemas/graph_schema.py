# app/schemas/graph_schema.py
# Pydantic models for the Identity Graph feature

from pydantic import BaseModel, Field
from typing import Optional, List
from uuid import UUID
from datetime import date, datetime


# ── Citizen ──────────────────────────────────────────────────
class CitizenCreate(BaseModel):
    dept_id: UUID
    full_name: str
    dob: Optional[date] = None
    uid_number: Optional[str] = None
    gender: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None


class CitizenResponse(BaseModel):
    id: UUID
    dept_id: UUID
    full_name: str
    dob: Optional[date] = None
    uid_number: Optional[str] = None
    gender: Optional[str] = None
    address: Optional[str] = None
    phone: Optional[str] = None
    is_flagged: bool
    created_at: datetime


# ── Edge ─────────────────────────────────────────────────────
class EdgeCreate(BaseModel):
    from_citizen: UUID
    to_citizen: UUID
    edge_type: str          # parent_of | spouse_of | owns_property | duplicate_of | sibling_of
    evidence_doc_id: Optional[UUID] = None
    confidence: float = Field(default=1.0, ge=0.0, le=1.0)


class EdgeResponse(BaseModel):
    id: UUID
    from_citizen: UUID
    to_citizen: UUID
    edge_type: str
    evidence_doc_id: Optional[UUID]
    confidence: float
    created_at: datetime


# ── Graph response (full graph for one department) ────────────
class GraphNodeResponse(BaseModel):
    id: UUID
    full_name: str
    dob: Optional[date]
    uid_number: Optional[str]
    is_flagged: bool
    doc_count: int
    docs: List[dict]        # [{type, value, confidence, is_tampered}]


class GraphResponse(BaseModel):
    nodes: List[GraphNodeResponse]
    edges: List[EdgeResponse]


# ── Citizen document link ─────────────────────────────────────
class CitizenDocumentCreate(BaseModel):
    citizen_id: UUID
    document_id: UUID
    role: str = "subject"


class DuplicateCheckResponse(BaseModel):
    is_duplicate: bool
    matched_citizen_id: Optional[UUID]
    matched_name: Optional[str]
    similarity_score: float
    reason: str
