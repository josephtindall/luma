-- 0002_pages.sql
-- Phase 2: Pages — block-based documents with revision history and transclusion

CREATE TABLE luma.pages (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    short_id    TEXT        NOT NULL UNIQUE,
    vault_id    UUID        NOT NULL REFERENCES luma.vaults(id),
    title       TEXT        NOT NULL DEFAULT 'Untitled',
    content     JSONB       NOT NULL DEFAULT '{"blocks": []}',
    created_by  TEXT        NOT NULL,
    updated_by  TEXT        NOT NULL,
    is_archived BOOLEAN     NOT NULL DEFAULT false,
    archived_at TIMESTAMPTZ,
    archived_by TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_pages_vault    ON luma.pages(vault_id);
CREATE INDEX idx_pages_short_id ON luma.pages(short_id);
CREATE INDEX idx_pages_title    ON luma.pages USING gin(to_tsvector('english', title));
CREATE INDEX idx_pages_content  ON luma.pages USING gin(content);

-- Tracks which pages embed which other pages.
-- Replaced atomically on every full content save.
CREATE TABLE luma.transclusion_refs (
    containing_page_id UUID NOT NULL REFERENCES luma.pages(id) ON DELETE CASCADE,
    source_page_id     UUID NOT NULL REFERENCES luma.pages(id) ON DELETE CASCADE,
    PRIMARY KEY (containing_page_id, source_page_id)
);
CREATE INDEX idx_transclusion_refs_source ON luma.transclusion_refs(source_page_id);

CREATE TABLE luma.page_revisions (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    page_id    UUID        NOT NULL REFERENCES luma.pages(id) ON DELETE CASCADE,
    content    JSONB       NOT NULL,
    created_by TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_manual  BOOLEAN     NOT NULL DEFAULT false,
    label      TEXT
);
CREATE INDEX idx_revisions_page ON luma.page_revisions(page_id, created_at DESC);
