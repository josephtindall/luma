-- 0010_vault_groups.sql
-- Group membership for vaults.

-- Group membership table — links groups (from luma-auth) to vaults with a role.
CREATE TABLE luma.vault_group_members (
    vault_id   UUID        NOT NULL REFERENCES luma.vaults(id) ON DELETE CASCADE,
    group_id   TEXT        NOT NULL,
    role_id    TEXT        NOT NULL,
    added_by   TEXT,
    added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (vault_id, group_id)
);
CREATE INDEX idx_vault_group_members_group ON luma.vault_group_members(group_id);
