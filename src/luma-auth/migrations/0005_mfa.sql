-- Migration 0005: MFA (TOTP + Passkeys)

-- ─── MFA enabled flag on users ──────────────────────────────────────────────
ALTER TABLE auth.users ADD COLUMN mfa_enabled BOOLEAN NOT NULL DEFAULT false;

-- ─── TOTP secrets ───────────────────────────────────────────────────────────
-- One active secret per user. The secret column holds the raw 20-byte TOTP seed.

CREATE TABLE auth.totp_secrets (
    user_id     UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    secret      BYTEA       NOT NULL,
    verified    BOOLEAN     NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ─── MFA challenges ────────────────────────────────────────────────────────
-- Short-lived tokens proving "password OK, awaiting 2FA."

CREATE TABLE auth.mfa_challenges (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    device_id    UUID        NOT NULL REFERENCES auth.devices(id) ON DELETE CASCADE,
    token_hash   TEXT        NOT NULL UNIQUE,
    expires_at   TIMESTAMPTZ NOT NULL,
    consumed_at  TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_mfa_challenges_user ON auth.mfa_challenges(user_id);

-- ─── Passkey credentials ───────────────────────────────────────────────────

CREATE TABLE auth.passkeys (
    id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    credential_id BYTEA       NOT NULL UNIQUE,
    public_key    BYTEA       NOT NULL,
    sign_count    BIGINT      NOT NULL DEFAULT 0,
    name          TEXT        NOT NULL,
    aaguid        BYTEA,
    transports    TEXT[],
    last_used_at  TIMESTAMPTZ,
    revoked_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_passkeys_user ON auth.passkeys(user_id);
