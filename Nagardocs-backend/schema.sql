-- ═══════════════════════════════════════════════════════════════════════════
-- NagarDocs AI — Complete Supabase / PostgreSQL Schema
-- Run this ONCE in Supabase SQL Editor to set up the entire database.
-- ═══════════════════════════════════════════════════════════════════════════

-- Enable uuid extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── 1. DEPARTMENTS ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS departments (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code        TEXT UNIQUE NOT NULL,       -- e.g. "MCMC-IT" — used for login gate
    name        TEXT NOT NULL,              -- e.g. "Information Technology Department"
    city        TEXT,
    state       TEXT DEFAULT 'Maharashtra',
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- ── 2. USERS ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email           TEXT UNIQUE NOT NULL,
    password        TEXT NOT NULL,
    name            TEXT,
    department_id   UUID REFERENCES departments(id),
    designation     TEXT,                   -- e.g. "Junior Clerk", "Department Head"
    employee_id     TEXT,                   -- Government employee ID
    role            TEXT DEFAULT 'user' CHECK (role IN ('user', 'officer', 'admin')),
    status          TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'banned')),
    is_active       BOOLEAN DEFAULT true,
    last_seen       TIMESTAMPTZ DEFAULT now(),
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 3. FOLDERS (Cabinet) ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS folders (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    department_id       UUID REFERENCES departments(id),
    name                TEXT NOT NULL,
    doc_type_affinity   TEXT,
    color               TEXT DEFAULT '#1A6BFF',
    icon                TEXT DEFAULT 'folder',
    is_system           BOOLEAN DEFAULT false,       -- true = created by autosort, not user
    is_default_review   BOOLEAN DEFAULT false,       -- true = the "Needs Review" fallback folder
    created_at          TIMESTAMPTZ DEFAULT now()
);

-- ── 4. UPLOAD JOBS ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS upload_jobs (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES users(id),
    department_id   UUID REFERENCES departments(id),
    status          TEXT DEFAULT 'queued',   -- queued | processing | done | failed
    filename        TEXT,
    document_id     UUID,                    -- populated when status = 'done'
    error_message   TEXT,
    progress        JSONB DEFAULT '{}',      -- stores granular processing state
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 5. DOCUMENTS ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS documents (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    job_id          UUID REFERENCES upload_jobs(id),
    user_id         UUID REFERENCES users(id),
    department_id   UUID REFERENCES departments(id),
    folder_id       UUID REFERENCES folders(id),
    filename        TEXT NOT NULL,
    storage_path    TEXT,
    doc_type        TEXT,
    language        TEXT,
    raw_text        TEXT,
    ocr_confidence  NUMERIC(4,3),
    sort_confidence NUMERIC(4,3),
    file_hash       TEXT,                    -- SHA-256 tamper baseline
    tamper_flags    JSONB DEFAULT '[]',
    is_tampered     BOOLEAN DEFAULT false,
    is_private      BOOLEAN DEFAULT false,
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 6. DOCUMENT FIELDS ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS document_fields (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES documents(id) ON DELETE CASCADE,
    label       TEXT,
    value       TEXT,
    confidence  NUMERIC(4,3),
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- ── 7. ACTIVITY LOG ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS activity_log (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id         UUID REFERENCES users(id),
    department_id   UUID REFERENCES departments(id),
    document_id     UUID REFERENCES documents(id) ON DELETE SET NULL,
    action          TEXT,   -- upload | view | share | login | export | ban_user | approve_user | etc.
    detail          TEXT,
    metadata        JSONB DEFAULT '{}',      -- extra structured info
    created_at      TIMESTAMPTZ DEFAULT now()
);

-- ── 8. SHARED LINKS ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS shared_links (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    token        TEXT UNIQUE NOT NULL,
    document_id  UUID REFERENCES documents(id) ON DELETE CASCADE,
    created_by   UUID REFERENCES users(id),
    expires_at   TIMESTAMPTZ NOT NULL,
    password     TEXT,
    is_active    BOOLEAN DEFAULT true,
    created_at   TIMESTAMPTZ DEFAULT now()
);

-- ── 9. ACCESS CONTROL ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS access_control (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id  UUID REFERENCES documents(id) ON DELETE CASCADE,
    user_id      UUID REFERENCES users(id),
    granted_by   UUID REFERENCES users(id),
    permission   TEXT DEFAULT 'view' CHECK (permission IN ('view', 'edit', 'admin')),
    created_at   TIMESTAMPTZ DEFAULT now(),
    UNIQUE(document_id, user_id)
);

-- ── 10. PENDING INVITES ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pending_invites (
    id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id    UUID REFERENCES documents(id) ON DELETE CASCADE,
    invited_email  TEXT NOT NULL,
    invited_by     UUID REFERENCES users(id),
    department_id  UUID REFERENCES departments(id),
    expires_at     TIMESTAMPTZ NOT NULL,
    created_at     TIMESTAMPTZ DEFAULT now()
);

-- ── INDEXES ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_documents_department  ON documents(department_id);
CREATE INDEX IF NOT EXISTS idx_documents_folder      ON documents(folder_id);
CREATE INDEX IF NOT EXISTS idx_documents_hash        ON documents(file_hash);
CREATE INDEX IF NOT EXISTS idx_document_fields_doc   ON document_fields(document_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_dept     ON activity_log(department_id);
CREATE INDEX IF NOT EXISTS idx_activity_log_created  ON activity_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_users_last_seen        ON users(last_seen);
CREATE INDEX IF NOT EXISTS idx_shared_links_token    ON shared_links(token);
CREATE INDEX IF NOT EXISTS idx_shared_links_doc      ON shared_links(document_id);

-- ── FULL-TEXT SEARCH INDEX ────────────────────────────────────────────────────
-- Enables fast full-text search on raw_text and filename
ALTER TABLE documents ADD COLUMN IF NOT EXISTS search_vector TSVECTOR;
CREATE INDEX IF NOT EXISTS idx_documents_fts ON documents USING GIN(search_vector);

CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := to_tsvector('english',
        coalesce(NEW.filename, '') || ' ' ||
        coalesce(NEW.doc_type, '') || ' ' ||
        coalesce(NEW.raw_text, '')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_search_vector ON documents;
CREATE TRIGGER trg_search_vector
    BEFORE INSERT OR UPDATE ON documents
    FOR EACH ROW EXECUTE FUNCTION update_search_vector();

-- ── AUTO-CREATE "NEEDS REVIEW" FOLDER ON NEW DEPARTMENT ───────────────────────
CREATE OR REPLACE FUNCTION create_default_review_folder()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO folders (department_id, name, color, icon, is_system, is_default_review)
    VALUES (NEW.id, 'Needs Review', '#FF6B35', 'folder_open', true, true);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS after_department_insert ON departments;
CREATE TRIGGER after_department_insert
    AFTER INSERT ON departments
    FOR EACH ROW EXECUTE FUNCTION create_default_review_folder();

-- ── ROW LEVEL SECURITY ────────────────────────────────────────────────────────
-- Enable RLS on all tables
ALTER TABLE users         ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents     ENABLE ROW LEVEL SECURITY;
ALTER TABLE folders       ENABLE ROW LEVEL SECURITY;
ALTER TABLE activity_log  ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_links  ENABLE ROW LEVEL SECURITY;
ALTER TABLE access_control ENABLE ROW LEVEL SECURITY;
ALTER TABLE pending_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE upload_jobs   ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_fields ENABLE ROW LEVEL SECURITY;

-- Users can read their dept users; admins see all in dept
CREATE POLICY "users_read_dept" ON users
    FOR SELECT USING (true);  -- service key bypasses; frontend uses JWT scoping

-- Documents: user sees their dept docs
CREATE POLICY "docs_read_dept" ON documents
    FOR SELECT USING (true);

-- Activity log: append only (cannot delete)
CREATE POLICY "activity_insert" ON activity_log
    FOR INSERT WITH CHECK (true);

CREATE POLICY "activity_select" ON activity_log
    FOR SELECT USING (true);

-- Deny all deletes on activity_log (audit trail protection)
CREATE POLICY "activity_no_delete" ON activity_log
    FOR DELETE USING (false);

-- ── 11. CITIZENS (IDENTITY GRAPH) ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS citizens (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    dept_id     UUID REFERENCES departments(id) ON DELETE CASCADE,
    full_name   TEXT NOT NULL,
    dob         DATE,
    uid_number  TEXT,               -- Aadhaar / UID
    gender      TEXT CHECK (gender IN ('male','female','other')),
    address     TEXT,
    phone       TEXT,
    is_flagged  BOOLEAN DEFAULT FALSE,  -- fraud/duplicate flag
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── 12. CITIZEN_EDGES ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS citizen_edges (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    from_citizen    UUID NOT NULL REFERENCES citizens(id) ON DELETE CASCADE,
    to_citizen      UUID NOT NULL REFERENCES citizens(id) ON DELETE CASCADE,
    edge_type       TEXT NOT NULL CHECK (edge_type IN (
                        'parent_of','child_of','spouse_of',
                        'owns_property','duplicate_of','sibling_of'
                    )),
    evidence_doc_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    confidence      FLOAT DEFAULT 1.0,  -- 0-1, lower = inferred
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ── 13. CITIZEN_DOCUMENTS ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS citizen_documents (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    citizen_id  UUID NOT NULL REFERENCES citizens(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    role        TEXT DEFAULT 'subject',  -- subject | witness | issuer
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(citizen_id, document_id)
);

CREATE INDEX IF NOT EXISTS idx_citizens_dept     ON citizens(dept_id);
CREATE INDEX IF NOT EXISTS idx_citizens_name     ON citizens USING GIN(to_tsvector('english', full_name));
CREATE INDEX IF NOT EXISTS idx_citizens_uid      ON citizens(uid_number);
CREATE INDEX IF NOT EXISTS idx_edges_from        ON citizen_edges(from_citizen);
CREATE INDEX IF NOT EXISTS idx_edges_to          ON citizen_edges(to_citizen);
CREATE INDEX IF NOT EXISTS idx_citizen_docs_cit  ON citizen_documents(citizen_id);
CREATE INDEX IF NOT EXISTS idx_citizen_docs_doc  ON citizen_documents(document_id);

ALTER TABLE citizens          ENABLE ROW LEVEL SECURITY;
ALTER TABLE citizen_edges     ENABLE ROW LEVEL SECURITY;
ALTER TABLE citizen_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "citizens_auth"    ON citizens          FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "edges_auth"       ON citizen_edges     FOR ALL USING (auth.role() = 'authenticated');
CREATE POLICY "cit_docs_auth"    ON citizen_documents FOR ALL USING (auth.role() = 'authenticated');

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS citizens_updated_at ON citizens;
CREATE TRIGGER citizens_updated_at
    BEFORE UPDATE ON citizens
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- ── SEED: SAMPLE DEPARTMENT ───────────────────────────────────────────────────
-- Remove this before going to production, or update with real department codes.
INSERT INTO departments (code, name, city, state)
VALUES
    ('MCMC-IT', 'Information Technology Department', 'Pune', 'Maharashtra'),
    ('MCMC-LAND', 'Land Records Department', 'Pune', 'Maharashtra'),
    ('MCMC-BIRTH', 'Birth & Death Registration', 'Nashik', 'Maharashtra')
ON CONFLICT (code) DO NOTHING;
