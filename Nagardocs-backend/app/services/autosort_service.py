
from app.core.database import get_supabase_sync
from app.core.config import settings
from app.utils.logger import logger

# Keywords that map document types to folder names (order matters: more specific first)
DOC_TYPE_TO_FOLDER = {
    # Identity Documents
    "aadhaar":               "Identity Documents",
    "pan card":              "Identity Documents",
    "voter id":              "Identity Documents",
    "voter card":            "Identity Documents",
    "passport":              "Identity Documents",
    "driving licence":       "Identity Documents",
    "driving license":       "Identity Documents",
    "ration card":           "Identity Documents",

    # Property Tax
    "property tax":          "Property Tax",
    "property card":         "Property Tax",

    # Water Bills
    "water bill":            "Water Bills",
    "water tax":             "Water Bills",
    "water invoice":         "Water Bills",

    # Land Records
    "land record":           "Land Records",
    "ferfar":                "Land Records",
    "mutation":              "Land Records",
    "7/12":                  "Land Records",

    # Certificates
    "birth certificate":     "Certificates",
    "death certificate":     "Certificates",
    "caste certificate":     "Certificates",
    "income certificate":    "Certificates",
    "domicile certificate":  "Certificates",
    "non-creamy layer":      "Certificates",
    "obc certificate":       "Certificates",
    "sc certificate":        "Certificates",
    "st certificate":        "Certificates",
    "marksheet":             "Certificates",
    "mark sheet":            "Certificates",
    "degree certificate":    "Certificates",
    "bonafide certificate":  "Certificates",
    "migration certificate": "Certificates",
    "medical certificate":   "Certificates",
    "disability certificate":"Certificates",
    "fitness certificate":   "Certificates",
    "gst certificate":       "Certificates",
    "license":               "Certificates",
    "licence":               "Certificates",
    "noc":                   "Certificates",

    # Other / General
    "tax invoice":           "Other",
    "gst invoice":           "Other",
    "income tax":            "Other",
    "invoice":               "Other",
    "bill":                  "Other",
}


class AutoSortService:

    async def classify(
        self,
        doc_type: str,
        fields: list,
        department_id: str,
        supabase=None,
    ) -> tuple[str | None, float]:
        """
        Returns (folder_id, confidence_score).
        If confidence < threshold → returns the dept's 'Needs Review' folder.
        """
        if not department_id:
            return None, 0.0

        if supabase is None:
            supabase = get_supabase_sync()

        doc_type_lower = (doc_type or "").lower().strip()
        matched_folder_name = None
        confidence = 0.0

        for keyword, folder_name in DOC_TYPE_TO_FOLDER.items():
            if keyword in doc_type_lower:
                matched_folder_name = folder_name
                confidence = 0.90
                break

        if confidence < settings.autosort_confidence_threshold:
            matched_folder_name = "Needs Review"
            confidence = 0.50

        # Look up or create the folder in this department
        folder_id = await self._get_or_create_folder(
            department_id, matched_folder_name, supabase
        )
        return folder_id, confidence

    async def _get_or_create_folder(
        self, department_id: str, folder_name: str, supabase
    ) -> str | None:
        try:
            existing = (
                supabase.table("folders")
                .select("id")
                .eq("department_id", department_id)
                .eq("name", folder_name)
                .execute()
            )
            if existing.data:
                return existing.data[0]["id"]

            created = supabase.table("folders").insert({
                "department_id": department_id,
                "name":          folder_name,
                "is_system":     True,
            }).execute()
            return created.data[0]["id"] if created.data else None
        except Exception as e:
            logger.error(f"[autosort] Folder lookup failed: {e}")
            return None
