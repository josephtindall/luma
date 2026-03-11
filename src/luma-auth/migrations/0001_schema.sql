-- =============================================================================
-- luma-auth schema — single consolidated migration
-- Represents the complete current state. Apply once to a fresh database.
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS auth;

-- =============================================================================
-- TABLES
-- =============================================================================

-- ─── Instance ─────────────────────────────────────────────────────────────────
-- Exactly one row. setup_state drives the bootstrap state machine.

CREATE TABLE auth.instance (
    id                     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                   TEXT        NOT NULL,
    locale                 TEXT        NOT NULL DEFAULT 'en-US',
    timezone               TEXT        NOT NULL DEFAULT 'UTC',
    setup_state            TEXT        NOT NULL DEFAULT 'unclaimed',
    setup_token_hash       TEXT,
    setup_token_expires_at TIMESTAMPTZ,
    setup_token_failures   INT         NOT NULL DEFAULT 0,
    activated_at           TIMESTAMPTZ,
    version                TEXT        NOT NULL DEFAULT '1.0.0',
    features               JSONB       NOT NULL DEFAULT '{}',
    -- Password policy
    password_min_length        INT     NOT NULL DEFAULT 8,
    password_require_uppercase BOOLEAN NOT NULL DEFAULT false,
    password_require_lowercase BOOLEAN NOT NULL DEFAULT false,
    password_require_numbers   BOOLEAN NOT NULL DEFAULT false,
    password_require_symbols   BOOLEAN NOT NULL DEFAULT false,
    password_history_count     INT     NOT NULL DEFAULT 0,
    -- Layout preference (site-wide, set by owner)
    content_width          TEXT        NOT NULL DEFAULT 'wide',
    -- UI button visibility
    show_github_button     BOOLEAN     NOT NULL DEFAULT true,
    show_donate_button     BOOLEAN     NOT NULL DEFAULT true,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT setup_state_values   CHECK (setup_state IN ('unclaimed', 'setup', 'active')),
    CONSTRAINT content_width_values CHECK (content_width IN ('narrow', 'wide', 'max'))
);

-- ─── Users ────────────────────────────────────────────────────────────────────

CREATE TABLE auth.users (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email                 TEXT        NOT NULL UNIQUE,
    display_name          TEXT        NOT NULL,
    password_hash         TEXT        NOT NULL,  -- Argon2id PHC string only
    instance_role_id      TEXT        NOT NULL DEFAULT 'builtin:instance-member',
    avatar_seed           TEXT,
    mfa_enabled           BOOLEAN     NOT NULL DEFAULT false,
    force_password_change BOOLEAN     NOT NULL DEFAULT false,
    failed_login_attempts INT         NOT NULL DEFAULT 0,
    locked_at             TIMESTAMPTZ,
    locked_reason         TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── User Preferences ────────────────────────────────────────────────────────
-- One row per user, created atomically alongside auth.users.

CREATE TABLE auth.user_preferences (
    user_id          UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    theme            TEXT        NOT NULL DEFAULT 'system',      -- system | light | dark
    language         TEXT        NOT NULL DEFAULT 'en',          -- BCP-47
    timezone         TEXT        NOT NULL DEFAULT 'UTC',         -- IANA
    date_format      TEXT        NOT NULL DEFAULT 'YYYY-MM-DD',
    time_format      TEXT        NOT NULL DEFAULT '24h',         -- 12h | 24h
    notify_on_login  BOOLEAN     NOT NULL DEFAULT true,
    notify_on_revoke BOOLEAN     NOT NULL DEFAULT true,
    compact_mode     BOOLEAN     NOT NULL DEFAULT false,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Devices ─────────────────────────────────────────────────────────────────

CREATE TABLE auth.devices (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name         TEXT        NOT NULL,
    platform     TEXT        NOT NULL,  -- web | ios | android | agent
    fingerprint  TEXT        NOT NULL,
    user_agent   TEXT,
    last_seen_at TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT platform_values CHECK (platform IN ('web', 'ios', 'android', 'agent'))
);

CREATE INDEX idx_devices_user ON auth.devices(user_id);

-- ─── Refresh Tokens ──────────────────────────────────────────────────────────
-- Raw token NEVER stored — only the SHA-256 hash.

CREATE TABLE auth.refresh_tokens (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id   UUID        NOT NULL REFERENCES auth.devices(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,  -- SHA-256(raw_token), hex-encoded
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_device ON auth.refresh_tokens(device_id);

-- ─── Audit Log ───────────────────────────────────────────────────────────────
-- IMMUTABLE: the application DB user has INSERT + SELECT only.
-- No UPDATE, no DELETE — ever. Enforced at the DB grant level below.

CREATE TABLE auth.audit_log (
    id          BIGSERIAL   PRIMARY KEY,
    user_id     UUID        REFERENCES auth.users(id),
    device_id   UUID        REFERENCES auth.devices(id),
    event       TEXT        NOT NULL,
    ip_address  INET,
    user_agent  TEXT,
    metadata    JSONB,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_user     ON auth.audit_log(user_id);
CREATE INDEX idx_audit_occurred ON auth.audit_log(occurred_at DESC);

DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auth_app') THEN
        GRANT SELECT, INSERT ON auth.audit_log TO auth_app;
        REVOKE UPDATE, DELETE  ON auth.audit_log FROM auth_app;
    END IF;
END $$;

-- ─── MFA: TOTP Secrets ───────────────────────────────────────────────────────
-- Multiple authenticator apps per user; each identified by a UUID.

CREATE TABLE auth.totp_secrets (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    secret            BYTEA       NOT NULL,
    name              TEXT        NOT NULL DEFAULT 'Authenticator',
    verified          BOOLEAN     NOT NULL DEFAULT false,
    last_used_counter BIGINT      NOT NULL DEFAULT 0,  -- replay-guard
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_totp_secrets_user ON auth.totp_secrets(user_id);

-- ─── MFA: Challenges ─────────────────────────────────────────────────────────
-- Short-lived tokens proving "password OK, awaiting second factor."

CREATE TABLE auth.mfa_challenges (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id   UUID        NOT NULL REFERENCES auth.devices(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mfa_challenges_user ON auth.mfa_challenges(user_id);

-- ─── MFA: Passkeys ───────────────────────────────────────────────────────────

CREATE TABLE auth.passkeys (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    credential_id   BYTEA       NOT NULL UNIQUE,
    public_key      BYTEA       NOT NULL,
    sign_count      BIGINT      NOT NULL DEFAULT 0,
    name            TEXT        NOT NULL,
    aaguid          BYTEA,
    transports      TEXT[],
    backup_eligible BOOLEAN     NOT NULL DEFAULT false,
    backup_state    BOOLEAN     NOT NULL DEFAULT false,
    last_used_at    TIMESTAMPTZ,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_passkeys_user ON auth.passkeys(user_id);

-- ─── MFA: Recovery Codes ─────────────────────────────────────────────────────

CREATE TABLE auth.recovery_codes (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    code_hash  TEXT        NOT NULL,
    used_at    TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recovery_codes_user ON auth.recovery_codes(user_id);

-- ─── Account Recovery Tokens ─────────────────────────────────────────────────
-- One token per user (upserted on generation). Raw 64-digit code never stored.

CREATE TABLE auth.recovery_tokens (
    user_id    UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Password Reset Tokens ───────────────────────────────────────────────────
-- source = 'admin_reset'  : admin-generated one-time link
-- source = 'force_change' : login-blocking forced reset

CREATE TABLE auth.password_reset_tokens (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    source      TEXT        NOT NULL,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT prt_source_values CHECK (source IN ('admin_reset', 'force_change'))
);

CREATE INDEX idx_prt_token_hash ON auth.password_reset_tokens(token_hash)
    WHERE consumed_at IS NULL;

-- ─── Password History ────────────────────────────────────────────────────────

CREATE TABLE auth.password_history (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    hash       TEXT        NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_password_history_user ON auth.password_history(user_id, created_at DESC);

-- ─── Invitations ─────────────────────────────────────────────────────────────

CREATE TABLE auth.invitations (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    inviter_id  UUID        NOT NULL REFERENCES auth.users(id),
    email       TEXT,
    note        TEXT,
    token_hash  TEXT        NOT NULL UNIQUE,
    status      TEXT        NOT NULL DEFAULT 'pending',
    expires_at  TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT invitation_status_values
        CHECK (status IN ('pending', 'accepted', 'expired', 'revoked'))
);

CREATE INDEX idx_invitations_inviter ON auth.invitations(inviter_id);
CREATE INDEX idx_invitations_status  ON auth.invitations(status) WHERE status = 'pending';

-- ─── RBAC: Roles ─────────────────────────────────────────────────────────────

CREATE TABLE auth.roles (
    id             TEXT        PRIMARY KEY,  -- e.g. 'builtin:instance-owner'
    name           TEXT        NOT NULL,
    description    TEXT,
    scope          TEXT        NOT NULL,     -- instance | vault
    is_builtin     BOOLEAN     NOT NULL DEFAULT false,
    parent_role_id TEXT        REFERENCES auth.roles(id),
    created_by     UUID,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT role_scope_values CHECK (scope IN ('instance', 'vault'))
);

-- ─── RBAC: Policies ──────────────────────────────────────────────────────────

CREATE TABLE auth.policies (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL UNIQUE,
    description TEXT,
    is_builtin  BOOLEAN     NOT NULL DEFAULT false,
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── RBAC: Policy Statements ─────────────────────────────────────────────────

CREATE TABLE auth.policy_statements (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id      UUID        NOT NULL REFERENCES auth.policies(id) ON DELETE CASCADE,
    effect         TEXT        NOT NULL,
    actions        TEXT[]      NOT NULL,
    resource_types TEXT[]      NOT NULL,
    conditions     JSONB       NOT NULL DEFAULT '[]',
    position       INTEGER     NOT NULL DEFAULT 0,
    CONSTRAINT statement_effect_values CHECK (effect IN ('allow', 'deny'))
);

-- ─── RBAC: Role–Policy Bindings ──────────────────────────────────────────────

CREATE TABLE auth.role_policies (
    role_id   TEXT NOT NULL REFERENCES auth.roles(id) ON DELETE CASCADE,
    policy_id UUID NOT NULL REFERENCES auth.policies(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, policy_id)
);

-- ─── RBAC: Resource-Level Explicit Permissions ───────────────────────────────

CREATE TABLE auth.resource_permissions (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type TEXT        NOT NULL,
    resource_id   TEXT        NOT NULL,
    subject_type  TEXT        NOT NULL,
    subject_id    TEXT        NOT NULL,
    effect        TEXT        NOT NULL,
    actions       TEXT[]      NOT NULL,
    granted_by    UUID        NOT NULL,
    expires_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT rp_effect_values       CHECK (effect IN ('allow', 'deny')),
    CONSTRAINT rp_subject_type_values CHECK (subject_type IN ('user', 'role'))
);

CREATE INDEX idx_resource_perms ON
    auth.resource_permissions(resource_type, resource_id, subject_type, subject_id);

-- ─── Groups ───────────────────────────────────────────────────────────────────

CREATE TABLE auth.groups (
    id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name              TEXT        NOT NULL,
    description       TEXT,
    is_system         BOOLEAN     NOT NULL DEFAULT false,
    no_member_control BOOLEAN     NOT NULL DEFAULT false,  -- true: auto-managed, no manual changes
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE auth.group_members (
    group_id    UUID        NOT NULL REFERENCES auth.groups(id) ON DELETE CASCADE,
    member_type TEXT        NOT NULL CHECK (member_type IN ('user', 'group')),
    member_id   UUID        NOT NULL,
    added_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (group_id, member_type, member_id)
);

CREATE INDEX idx_group_members_member ON auth.group_members(member_type, member_id);

-- ─── Custom Roles ─────────────────────────────────────────────────────────────

CREATE TABLE auth.custom_roles (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL UNIQUE,
    description TEXT,
    priority    INT,         -- lower number = higher priority; NULL = lowest
    is_system   BOOLEAN     NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE auth.custom_role_permissions (
    role_id UUID NOT NULL REFERENCES auth.custom_roles(id) ON DELETE CASCADE,
    action  TEXT NOT NULL,
    effect  TEXT NOT NULL CHECK (effect IN ('allow', 'allow_cascade', 'deny')),
    UNIQUE (role_id, action)
);

CREATE INDEX idx_custom_role_permissions ON auth.custom_role_permissions(role_id);

CREATE TABLE auth.user_custom_roles (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role_id UUID NOT NULL REFERENCES auth.custom_roles(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, role_id)
);

CREATE TABLE auth.group_custom_roles (
    group_id UUID NOT NULL REFERENCES auth.groups(id) ON DELETE CASCADE,
    role_id  UUID NOT NULL REFERENCES auth.custom_roles(id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, role_id)
);

-- =============================================================================
-- SEED DATA
-- =============================================================================

-- ─── Built-in Roles ───────────────────────────────────────────────────────────

INSERT INTO auth.roles (id, name, scope, is_builtin)
VALUES
    ('builtin:instance-owner',  'Owner',      'instance', true),
    ('builtin:instance-member', 'Member',     'instance', true),
    ('builtin:vault-admin',     'Vault Admin', 'vault',   true),
    ('builtin:vault-editor',    'Editor',      'vault',   true),
    ('builtin:vault-viewer',    'Viewer',      'vault',   true);

-- ─── Built-in Policies ────────────────────────────────────────────────────────

INSERT INTO auth.policies (id, name, description, is_builtin)
VALUES
    ('00000000-0000-0000-0000-000000000001', 'owner-all',
     'Allows all actions on all resources', true),
    ('00000000-0000-0000-0000-000000000002', 'member-base',
     'Base permissions for instance members', true),
    ('00000000-0000-0000-0000-000000000003', 'vault-admin-all',
     'All content and membership actions in a vault', true),
    ('00000000-0000-0000-0000-000000000004', 'vault-editor',
     'Create, edit, delete content in a vault', true),
    ('00000000-0000-0000-0000-000000000005', 'vault-viewer',
     'Read-only access to vault content', true);

INSERT INTO auth.policy_statements (policy_id, effect, actions, resource_types)
VALUES
    -- owner-all: every canonical action (includes group/role management)
    ('00000000-0000-0000-0000-000000000001', 'allow',
     ARRAY[
         'page:read', 'page:create', 'page:edit', 'page:delete', 'page:archive',
         'page:version', 'page:restore-version', 'page:share', 'page:transclude',
         'task:read', 'task:create', 'task:edit', 'task:delete', 'task:assign',
         'task:close', 'task:comment',
         'flow:read', 'flow:create', 'flow:edit', 'flow:delete', 'flow:publish',
         'flow:execute', 'flow:comment',
         'vault:read', 'vault:create', 'vault:edit', 'vault:delete', 'vault:archive',
         'vault:manage-members', 'vault:manage-roles',
         'user:read', 'user:invite', 'user:edit', 'user:delete',
         'user:lock', 'user:unlock', 'user:revoke-sessions',
         'audit:read-own', 'audit:read-all', 'audit:export-all',
         'instance:read', 'instance:configure', 'instance:backup', 'instance:restore',
         'notification:read', 'notification:configure-own', 'notification:configure-all',
         'invitation:create', 'invitation:revoke', 'invitation:list',
         'group:read', 'group:create', 'group:rename', 'group:delete',
         'group:add-member', 'group:remove-member', 'group:assign-role', 'group:unassign-role',
         'role:read', 'role:create', 'role:update', 'role:delete',
         'role:set-permission', 'role:remove-permission', 'role:assign-user', 'role:unassign-user'
     ],
     ARRAY['page', 'task', 'flow', 'vault', 'user', 'audit', 'instance',
           'notification', 'invitation', 'group', 'role']),

    -- member-base: own audit log + notification prefs only
    -- (user:read intentionally excluded — it would expose the admin panel)
    ('00000000-0000-0000-0000-000000000002', 'allow',
     ARRAY['audit:read-own', 'notification:read', 'notification:configure-own'],
     ARRAY['audit', 'notification']),

    -- vault-admin-all
    ('00000000-0000-0000-0000-000000000003', 'allow',
     ARRAY[
         'page:read', 'page:create', 'page:edit', 'page:delete', 'page:archive',
         'page:version', 'page:restore-version', 'page:share', 'page:transclude',
         'task:read', 'task:create', 'task:edit', 'task:delete', 'task:assign',
         'task:close', 'task:comment',
         'flow:read', 'flow:create', 'flow:edit', 'flow:delete', 'flow:publish',
         'flow:execute', 'flow:comment',
         'vault:read', 'vault:edit', 'vault:manage-members', 'vault:manage-roles'
     ],
     ARRAY['page', 'task', 'flow', 'vault']),

    -- vault-editor
    ('00000000-0000-0000-0000-000000000004', 'allow',
     ARRAY[
         'page:read', 'page:create', 'page:edit', 'page:delete', 'page:archive',
         'page:version', 'page:restore-version', 'page:transclude',
         'task:read', 'task:create', 'task:edit', 'task:delete', 'task:assign',
         'task:close', 'task:comment',
         'flow:read', 'flow:create', 'flow:edit', 'flow:delete',
         'flow:execute', 'flow:comment',
         'vault:read'
     ],
     ARRAY['page', 'task', 'flow', 'vault']),

    -- vault-viewer
    ('00000000-0000-0000-0000-000000000005', 'allow',
     ARRAY['page:read', 'task:read', 'flow:read', 'vault:read'],
     ARRAY['page', 'task', 'flow', 'vault']);

INSERT INTO auth.role_policies (role_id, policy_id)
VALUES
    ('builtin:instance-owner',  '00000000-0000-0000-0000-000000000001'),
    ('builtin:instance-member', '00000000-0000-0000-0000-000000000002'),
    ('builtin:vault-admin',     '00000000-0000-0000-0000-000000000003'),
    ('builtin:vault-editor',    '00000000-0000-0000-0000-000000000004'),
    ('builtin:vault-viewer',    '00000000-0000-0000-0000-000000000005');

-- ─── System Custom Role: "Full Control" ───────────────────────────────────────
-- Grants allow_cascade on every action in the permission taxonomy.
-- is_system = true: cannot be modified or deleted by anyone, including the owner.

INSERT INTO auth.custom_roles (id, name, priority, is_system)
VALUES ('00000000-0000-0000-0000-000000000001', 'Full Control', 0, true);

INSERT INTO auth.custom_role_permissions (role_id, action, effect)
VALUES
    -- Pages
    ('00000000-0000-0000-0000-000000000001', 'page:read',            'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'page:create',          'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'page:edit',            'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'page:delete',          'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'page:archive',         'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'page:version',         'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'page:restore-version', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'page:share',           'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'page:transclude',      'allow_cascade'),
    -- Tasks
    ('00000000-0000-0000-0000-000000000001', 'task:read',    'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'task:create',  'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'task:edit',    'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'task:delete',  'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'task:assign',  'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'task:close',   'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'task:comment', 'allow_cascade'),
    -- Flows
    ('00000000-0000-0000-0000-000000000001', 'flow:read',    'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'flow:create',  'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'flow:edit',    'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'flow:delete',  'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'flow:publish', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'flow:execute', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'flow:comment', 'allow_cascade'),
    -- Vaults
    ('00000000-0000-0000-0000-000000000001', 'vault:read',           'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'vault:create',         'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'vault:edit',           'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'vault:delete',         'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'vault:archive',        'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'vault:manage-members', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'vault:manage-roles',   'allow_cascade'),
    -- Users
    ('00000000-0000-0000-0000-000000000001', 'user:read',            'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'user:invite',          'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'user:edit',            'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'user:delete',          'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'user:lock',            'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'user:unlock',          'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'user:revoke-sessions', 'allow_cascade'),
    -- Audit
    ('00000000-0000-0000-0000-000000000001', 'audit:read-own',   'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'audit:read-all',   'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'audit:export-all', 'allow_cascade'),
    -- Instance
    ('00000000-0000-0000-0000-000000000001', 'instance:read',      'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'instance:configure', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'instance:backup',    'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'instance:restore',   'allow_cascade'),
    -- Notifications
    ('00000000-0000-0000-0000-000000000001', 'notification:read',          'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'notification:configure-own', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'notification:configure-all', 'allow_cascade'),
    -- Invitations
    ('00000000-0000-0000-0000-000000000001', 'invitation:create', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'invitation:revoke', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'invitation:list',   'allow_cascade'),
    -- Groups
    ('00000000-0000-0000-0000-000000000001', 'group:read',          'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'group:create',        'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'group:rename',        'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'group:delete',        'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'group:add-member',    'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'group:remove-member', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'group:assign-role',   'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'group:unassign-role', 'allow_cascade'),
    -- Custom Roles
    ('00000000-0000-0000-0000-000000000001', 'role:read',              'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'role:create',            'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'role:update',            'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'role:delete',            'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'role:set-permission',    'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'role:remove-permission', 'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'role:assign-user',       'allow_cascade'),
    ('00000000-0000-0000-0000-000000000001', 'role:unassign-user',     'allow_cascade');

-- ─── System Groups ────────────────────────────────────────────────────────────

-- "Super Admins": membership managed by admins; receives Full Control role.
-- The group itself cannot be deleted (is_system = true), but membership is editable.
INSERT INTO auth.groups (id, name, is_system, no_member_control)
VALUES ('00000000-0000-0000-0000-000000000002', 'Super Admins', true, false);

INSERT INTO auth.group_custom_roles (group_id, role_id)
VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001');

-- "Users": every user is enrolled automatically on creation.
-- no_member_control = true: membership is system-managed, not editable by admins.
INSERT INTO auth.groups (id, name, is_system, no_member_control)
VALUES ('00000000-0000-0000-0000-000000000003', 'Users', true, true);
