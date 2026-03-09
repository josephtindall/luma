-- Migration 0008: Admin portal features
-- Adds force_password_change flag and password reset tokens table.

-- ─── Force password change flag on users ────────────────────────────────────
ALTER TABLE auth.users
  ADD COLUMN force_password_change BOOLEAN NOT NULL DEFAULT false;

-- ─── Unified password reset / force-change token table ───────────────────────
-- source = 'admin_reset': admin-generated one-time reset link
-- source = 'force_change': login-blocking forced change token
CREATE TABLE auth.password_reset_tokens (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash   TEXT        NOT NULL UNIQUE,
  source       TEXT        NOT NULL CHECK (source IN ('admin_reset', 'force_change')),
  expires_at   TIMESTAMPTZ NOT NULL,
  consumed_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_prt_token_hash ON auth.password_reset_tokens (token_hash)
  WHERE consumed_at IS NULL;
