-- 0001_vaults.sql
-- Phase 1: Vaults + short ID registry

CREATE SCHEMA IF NOT EXISTS luma;

-- Short ID registry — globally unique across pages, tasks, flows.
CREATE TABLE luma.short_ids (
    short_id      TEXT        PRIMARY KEY,
    resource_type TEXT        NOT NULL,
    resource_id   UUID        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Vaults — top-level organizational containers.
CREATE TABLE luma.vaults (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL,
    slug        TEXT        NOT NULL UNIQUE,
    type        TEXT        NOT NULL DEFAULT 'shared',
    owner_id    TEXT        NOT NULL,
    description TEXT,
    icon        TEXT,
    color       TEXT,
    is_archived BOOLEAN     NOT NULL DEFAULT false,
    archived_at TIMESTAMPTZ,
    archived_by TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT vault_type_values CHECK (type IN ('personal', 'shared'))
);
CREATE INDEX idx_vaults_owner ON luma.vaults(owner_id);

-- Vault membership — links Haven users to vaults with a role.
CREATE TABLE luma.vault_members (
    vault_id   UUID NOT NULL REFERENCES luma.vaults(id) ON DELETE CASCADE,
    user_id    TEXT NOT NULL,
    role_id    TEXT NOT NULL,
    added_by   TEXT,
    added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (vault_id, user_id)
);
CREATE INDEX idx_vault_members_user ON luma.vault_members(user_id);
