-- Migration 0001: core tables
-- All tables live in the auth schema.
-- The DB user has access only to this schema.

CREATE SCHEMA IF NOT EXISTS auth;

-- ─── Instance ────────────────────────────────────────────────────────────────
-- Exactly one row. setup_state drives the bootstrap state machine.

CREATE TABLE auth.instance
(
    id                     UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
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
    created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT setup_state_values CHECK (setup_state IN ('unclaimed', 'setup', 'active'))
);

-- ─── Users ───────────────────────────────────────────────────────────────────

CREATE TABLE auth.users
(
    id                    UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    email                 TEXT        NOT NULL UNIQUE,
    display_name          TEXT        NOT NULL,
    password_hash         TEXT        NOT NULL, -- Argon2id PHC string only
    instance_role_id      TEXT        NOT NULL DEFAULT 'builtin:instance-member',
    avatar_seed           TEXT,
    failed_login_attempts INT         NOT NULL DEFAULT 0,
    locked_at             TIMESTAMPTZ,
    locked_reason         TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── Devices ─────────────────────────────────────────────────────────────────

CREATE TABLE auth.devices
(
    id           UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
    name         TEXT        NOT NULL,
    platform     TEXT        NOT NULL, -- web | ios | android | agent
    fingerprint  TEXT        NOT NULL,
    user_agent   TEXT,
    last_seen_at TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT platform_values CHECK (platform IN ('web', 'ios', 'android', 'agent'))
);

CREATE INDEX idx_devices_user ON auth.devices (user_id);

-- ─── Refresh Tokens ──────────────────────────────────────────────────────────
-- Raw token NEVER stored — only the SHA-256 hash.
-- consumed_at + revoked_at support reuse detection and explicit revocation.

CREATE TABLE auth.refresh_tokens
(
    id          UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    device_id   UUID        NOT NULL REFERENCES auth.devices (id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE, -- SHA-256(raw_token), hex-encoded
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_refresh_device ON auth.refresh_tokens (device_id);

-- ─── Audit Log ───────────────────────────────────────────────────────────────
-- IMMUTABLE: the application DB user has INSERT + SELECT only.
-- No UPDATE, no DELETE — ever. Enforced at the DB grant level below.

CREATE TABLE auth.audit_log
(
    id          BIGSERIAL PRIMARY KEY,
    user_id     UUID REFERENCES auth.users (id),
    device_id   UUID REFERENCES auth.devices (id),
    event       TEXT        NOT NULL,
    ip_address  INET,
    user_agent  TEXT,
    metadata    JSONB,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_user ON auth.audit_log (user_id);
CREATE INDEX idx_audit_occurred ON auth.audit_log (occurred_at DESC);

-- Grant INSERT + SELECT only — no UPDATE, no DELETE.
-- Replace 'auth_app' with the actual application DB role name.
DO
$$
BEGIN
    IF
EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'auth_app') THEN
        GRANT
SELECT,
INSERT
ON auth.audit_log TO auth_app;
REVOKE UPDATE, DELETE ON auth.audit_log FROM auth_app;
END IF;
END
$$;
