from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware

from app.api.auth import router as auth_router
from app.api import upload, cabinet, search, analytics, export, admin, share, pin
from app.api.graph import router as graph_router
from app.core.websocket import manager

app = FastAPI(
    title="NagarDocs AI API",
    description="Backend for scanning, OCR processing, tamper detection and cabinet management of government documents.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routers ────────────────────────────────────────────────────────────────────
app.include_router(auth_router)
app.include_router(pin.router)
app.include_router(upload.router)
app.include_router(cabinet.router)
app.include_router(search.router)
app.include_router(analytics.router)
app.include_router(export.router)
app.include_router(admin.router)
app.include_router(share.router)
app.include_router(graph_router)


# ── WebSocket (admin live presence + activity feed) ───────────────────────────
@app.websocket("/ws/{user_id}")
async def websocket_endpoint(websocket: WebSocket, user_id: str):
    await manager.connect(websocket, user_id)
    try:
        while True:
            await websocket.receive_text()   # keep connection alive; ignore pings
    except WebSocketDisconnect:
        manager.disconnect(user_id)


# ── Health check ───────────────────────────────────────────────────────────────
@app.get("/", tags=["health"])
async def health():
    return {"status": "ok", "service": "NagarDocs AI API v1"}