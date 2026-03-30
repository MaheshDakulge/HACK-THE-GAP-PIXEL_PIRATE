from pydantic import BaseModel
from typing import Optional, List, Any

class FolderCreate(BaseModel):
    name: str
    doc_type_affinity: Optional[str] = None
    color: Optional[str] = None
    icon: Optional[str] = None

class FolderUpdate(BaseModel):
    name: Optional[str] = None
    doc_type_affinity: Optional[str] = None
    color: Optional[str] = None
    icon: Optional[str] = None

class FolderResponse(BaseModel):
    id: str
    department_id: str
    name: str
    doc_type_affinity: Optional[str] = None
    color: Optional[str] = None
    icon: Optional[str] = None
    is_system: bool = False
    is_default_review: bool = False
    created_at: Optional[str] = None
    document_count: Optional[int] = None
    documents: Optional[List[Any]] = None

class DocumentFieldResponse(BaseModel):
    id: Optional[str] = None
    label: str
    value: str
    confidence: Optional[float] = None

class DocumentResponse(BaseModel):
    id: str
    filename: str
    doc_type: Optional[str] = None
    language: Optional[str] = None
    ocr_confidence: Optional[float] = None
    sort_confidence: Optional[float] = None
    is_private: bool = False
    is_tampered: bool = False
    tamper_flags: Optional[List[Any]] = None
    storage_path: Optional[str] = None
    created_at: Optional[str] = None
    document_fields: Optional[List[DocumentFieldResponse]] = None

class DocumentMoveRequest(BaseModel):
    target_folder: str
