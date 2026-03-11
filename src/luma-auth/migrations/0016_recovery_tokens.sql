-- Migration 0016: Account recovery tokens.
-- One token per user (upserted on (re)generation). The raw 64-digit code is
-- never stored — only its SHA-256 hex digest.

CREATE TABLE auth.recovery_tokens (
  user_id     UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
