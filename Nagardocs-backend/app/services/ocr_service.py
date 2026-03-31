
import base64
import json
import pytesseract
from PIL import Image
from io import BytesIO
from openai import OpenAI
from app.core.config import settings
from app.utils.logger import logger

try:
    import fitz  # PyMuPDF
    PYMUPDF_AVAILABLE = True
except ImportError:
    PYMUPDF_AVAILABLE = False

pytesseract.pytesseract.tesseract_cmd = settings.tesseract_cmd
client = OpenAI(api_key=settings.openai_api_key)

GPT_PROMPT = """You are a government document analysis system for Indian municipal documents.
Analyze this document image and the raw OCR text. Return a JSON object with:
{
  "doc_type": "Marksheet | Aadhaar Card | Ration Card | Land Record | Birth Certificate | Caste Certificate | Income Certificate | Other",
  "language": "Marathi | Hindi | English | Mixed",
  "confidence": 0.0 to 1.0,
  "tamper_flags": ["list of suspicious findings, or empty array"],
  "suggested_folder": "Decide the precise categorical folder for this document. Use standard professional names (e.g., 'Identity Documents', 'Property Tax', 'Certificates') or confidently INVENT a concise new category (e.g., 'Health Records', 'Invoices', 'Legal Contracts'). If entirely unclassifiable, output 'Needs Review'.",
  "fields": [
    // Dynamically extract ALL important fields present in the document.
    // ALWAYS format standard documents as follows:
    // Marksheet: {"label": "Student Name", "value": "..."}, {"label": "PRN", "value": "..."}, {"label": "SGPA", "value": "8.44"}
    // 7/12 Extract or Property Card: {"label": "Owner Name", "value": "..."}, {"label": "Survey/Plot Number", "value": "..."}, {"label": "Total Area", "value": "..."}
    // Birth Certificate: {"label": "Child Name", "value": "..."}, {"label": "Date of Birth", "value": "..."}, {"label": "Parent Name", "value": "..."}
    // Death Certificate: {"label": "Deceased Name", "value": "..."}, {"label": "Cause of Death", "value": "..."}
    // Ration Card: {"label": "Head of Family", "value": "..."}, {"label": "Card Type", "value": "BPL/APL"}
    // Income/Caste Certificate: {"label": "Applicant Name", "value": "..."}, {"label": "Certificate Number", "value": "..."}
    // Building Permit/NOC: {"label": "Builder Name", "value": "..."}, {"label": "Approval Date", "value": "..."}
    {"label": "Relevant Field Name", "value": "Extracted Value"}
  ]
}
Return ONLY the JSON object. Do not include markdown code block formatting like ```json. Return raw JSON."""


class OCRService:

    def _pdf_to_image_bytes(self, pdf_bytes: bytes) -> bytes:
        if not PYMUPDF_AVAILABLE:
            raise RuntimeError("PyMuPDF not installed — cannot process PDF")
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        page = doc[0]
        pix = page.get_pixmap(dpi=200)
        return pix.tobytes("png")

    def _extract_raw_text(self, image_bytes: bytes) -> str:
        try:
            image = Image.open(BytesIO(image_bytes))
            return pytesseract.image_to_string(image, lang=settings.ocr_languages)
        except Exception as e:
            logger.warning(f"[ocr] Tesseract failed: {e}")
            return ""

    async def process_document(
        self,
        file_bytes: bytes,
        filename: str,
        language_hint: str = "mar+hin+eng",
        doc_type_hint: str = "",
    ) -> dict:
        # Convert PDF to image if needed
        if filename.lower().endswith(".pdf"):
            image_bytes = self._pdf_to_image_bytes(file_bytes)
        else:
            image_bytes = file_bytes

        raw_text = self._extract_raw_text(image_bytes)
        b64_image = base64.b64encode(image_bytes).decode()

        try:
            response = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": f"{GPT_PROMPT}\n\nRaw OCR text:\n{raw_text[:2000]}"},
                            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{b64_image}"}},
                        ],
                    }
                ],
                max_tokens=1000,
            )
            content = response.choices[0].message.content.strip()
            if content.startswith("```"):
                content = content.split("```")[1].strip().lstrip("json").strip()
            extracted = json.loads(content)
        except Exception as e:
            logger.error(f"[ocr] GPT extraction failed: {e}")
            extracted = {
                "doc_type": doc_type_hint or "Unknown",
                "language": "Unknown",
                "confidence": 0.3,
                "tamper_flags": [],
                "suggested_folder": "Needs Review",
                "fields": [],
            }

        extracted["raw_text"] = raw_text
        return extracted
