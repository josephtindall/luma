-- Migration 0003: RBAC tables
-- Roles, policies, policy statements, role–policy bindings, and
-- resource-level explicit permissions.
-- Built-in roles and their seed policies are inserted here.

-- ─── Roles ───────────────────────────────────────────────────────────────────

CREATE TABLE haven.roles
(
    id             TEXT PRIMARY KEY,     -- e.g. 'builtin:instance-owner'
    name           TEXT        NOT NULL,
    description    TEXT,
    scope          TEXT        NOT NULL, -- instance | vault
    is_builtin     BOOLEAN     NOT NULL DEFAULT false,
    parent_role_id TEXT REFERENCES haven.roles (id),
    created_by     UUID,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT role_scope_values CHECK (scope IN ('instance', 'vault'))
);

INSERT INTO haven.roles (id, name, scope, is_builtin)
VALUES ('builtin:instance-owner', 'Owner', 'instance', true),
       ('builtin:instance-member', 'Member', 'instance', true),
       ('builtin:vault-admin', 'Vault Admin', 'vault', true),
       ('builtin:vault-editor', 'Editor', 'vault', true),
       ('builtin:vault-viewer', 'Viewer', 'vault', true);

-- ─── Policies ────────────────────────────────────────────────────────────────

CREATE TABLE haven.policies
(
    id          UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL UNIQUE,
    description TEXT,
    is_builtin  BOOLEAN     NOT NULL DEFAULT false,
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Policy Statements ───────────────────────────────────────────────────────
-- effect: 'allow' | 'deny'
-- actions: canonical action strings, e.g. '{page:edit,page:read}'
-- resource_types: e.g. '{page,task}'
-- conditions: future extensibility (always '[]' for now)

CREATE TABLE haven.policy_statements
(
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id      UUID    NOT NULL REFERENCES haven.policies (id) ON DELETE CASCADE,
    effect         TEXT    NOT NULL,
    actions        TEXT[]      NOT NULL,
    resource_types TEXT[]      NOT NULL,
    conditions     JSONB   NOT NULL DEFAULT '[]',
    position       INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT statement_effect_values CHECK (effect IN ('allow', 'deny'))
);

-- ─── Role–Policy Bindings ─────────────────────────────────────────────────────

CREATE TABLE haven.role_policies
(
    role_id   TEXT NOT NULL REFERENCES haven.roles (id) ON DELETE CASCADE,
    policy_id UUID NOT NULL REFERENCES haven.policies (id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, policy_id)
);

-- ─── Resource-Level Explicit Permissions ─────────────────────────────────────
-- Most-specific dimension: overrides vault and instance role policies.
-- subject_type: 'user' | 'role'

CREATE TABLE haven.resource_permissions
(
    id            UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    resource_type TEXT        NOT NULL,
    resource_id   TEXT        NOT NULL,
    subject_type  TEXT        NOT NULL,
    subject_id    TEXT        NOT NULL,
    effect        TEXT        NOT NULL,
    actions       TEXT[]      NOT NULL,
    granted_by    UUID        NOT NULL,
    expires_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT rp_effect_values CHECK (effect IN ('allow', 'deny')),
    CONSTRAINT rp_subject_type_values CHECK (subject_type IN ('user', 'role'))
);

CREATE INDEX idx_resource_perms ON
    haven.resource_permissions (resource_type, resource_id, subject_type, subject_id);

-- ─── Seed: built-in policies ─────────────────────────────────────────────────
-- Owner: allow all actions on all resource types.
-- Member: allow reading own audit log; own account management.
-- Vault roles: scoped content actions — policies attached at vault-membership time.

INSERT INTO haven.policies (id, name, description, is_builtin)
VALUES ('00000000-0000-0000-0000-000000000001', 'owner-all', 'Allows all actions on all resources', true),
       ('00000000-0000-0000-0000-000000000002', 'member-base', 'Base permissions for instance members', true),
       ('00000000-0000-0000-0000-000000000003', 'vault-admin-all', 'All content and membership actions in a vault',
        true),
       ('00000000-0000-0000-0000-000000000004', 'vault-editor', 'Create, edit, delete content in a vault', true),
       ('00000000-0000-0000-0000-000000000005', 'vault-viewer', 'Read-only access to vault content', true);

INSERT INTO haven.policy_statements (policy_id, effect, actions, resource_types)
VALUES
    -- owner-all: wildcard via explicit list of every canonical action
    ('00000000-0000-0000-0000-000000000001', 'allow',
     ARRAY['page:read', 'page:create', 'page:edit', 'page:delete', 'page:archive',
     'page:version', 'page:restore-version', 'page:share', 'page:transclude',
     'task:read', 'task:create', 'task:edit', 'task:delete', 'task:assign',
     'task:close', 'task:comment',
     'flow:read', 'flow:create', 'flow:edit', 'flow:delete', 'flow:publish',
     'flow:execute', 'flow:comment',
     'vault:read', 'vault:create', 'vault:edit', 'vault:delete', 'vault:archive',
     'vault:manage-members', 'vault:manage-roles',
     'user:read', 'user:invite', 'user:edit', 'user:delete', 'user:lock',
     'user:unlock', 'user:revoke-sessions',
     'audit:read-own', 'audit:read-all',
     'instance:read', 'instance:configure', 'instance:backup', 'instance:restore',
     'notification:read', 'notification:configure-own', 'notification:configure-all',
     'invitation:create', 'invitation:revoke', 'invitation:list'],
     ARRAY['page', 'task', 'flow', 'vault', 'user', 'audit', 'instance', 'notification', 'invitation']),

    -- member-base: own audit log + own account
    ('00000000-0000-0000-0000-000000000002', 'allow',
     ARRAY['audit:read-own', 'user:read', 'notification:read', 'notification:configure-own'],
     ARRAY['audit', 'user', 'notification']),

    -- vault-admin-all
    ('00000000-0000-0000-0000-000000000003', 'allow',
     ARRAY['page:read', 'page:create', 'page:edit', 'page:delete', 'page:archive',
     'page:version', 'page:restore-version', 'page:share', 'page:transclude',
     'task:read', 'task:create', 'task:edit', 'task:delete', 'task:assign',
     'task:close', 'task:comment',
     'flow:read', 'flow:create', 'flow:edit', 'flow:delete', 'flow:publish',
     'flow:execute', 'flow:comment',
     'vault:read', 'vault:edit', 'vault:manage-members', 'vault:manage-roles'],
     ARRAY['page', 'task', 'flow', 'vault']),

    -- vault-editor
    ('00000000-0000-0000-0000-000000000004', 'allow',
     ARRAY['page:read', 'page:create', 'page:edit', 'page:delete', 'page:archive',
     'page:version', 'page:restore-version', 'page:transclude',
     'task:read', 'task:create', 'task:edit', 'task:delete', 'task:assign',
     'task:close', 'task:comment',
     'flow:read', 'flow:create', 'flow:edit', 'flow:delete', 'flow:execute',
     'flow:comment',
     'vault:read'],
     ARRAY['page', 'task', 'flow', 'vault']),

    -- vault-viewer
    ('00000000-0000-0000-0000-000000000005', 'allow',
     ARRAY['page:read', 'task:read', 'flow:read', 'vault:read'],
     ARRAY['page', 'task', 'flow', 'vault']);

INSERT INTO haven.role_policies (role_id, policy_id)
VALUES ('builtin:instance-owner', '00000000-0000-0000-0000-000000000001'),
       ('builtin:instance-member', '00000000-0000-0000-0000-000000000002'),
       ('builtin:vault-admin', '00000000-0000-0000-0000-000000000003'),
       ('builtin:vault-editor', '00000000-0000-0000-0000-000000000004'),
       ('builtin:vault-viewer', '00000000-0000-0000-0000-000000000005');
