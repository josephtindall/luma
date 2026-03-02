-- Migration 0006: Multi-TOTP support
-- Allows multiple authenticator apps per user, each with a nickname.

-- Drop the old single-secret-per-user constraint.
ALTER TABLE auth.totp_secrets DROP CONSTRAINT totp_secrets_pkey;

-- Add UUID primary key and user-chosen nickname.
ALTER TABLE auth.totp_secrets ADD COLUMN id UUID NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE auth.totp_secrets ADD COLUMN name TEXT NOT NULL DEFAULT 'Authenticator';
ALTER TABLE auth.totp_secrets ADD PRIMARY KEY (id);

-- Index for lookups by user.
CREATE INDEX idx_totp_secrets_user ON auth.totp_secrets(user_id);
