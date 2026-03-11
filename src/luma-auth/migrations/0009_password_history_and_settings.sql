-- Password history for reuse prevention
CREATE TABLE IF NOT EXISTS auth.password_history (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  hash       TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX ON auth.password_history (user_id, created_at DESC);

-- Instance-level password policy
ALTER TABLE auth.instance
  ADD COLUMN IF NOT EXISTS password_min_length        INT     NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS password_require_uppercase BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS password_require_lowercase BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS password_require_numbers   BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS password_require_symbols   BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS password_history_count     INT     NOT NULL DEFAULT 0;
