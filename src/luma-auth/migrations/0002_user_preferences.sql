-- Migration 0002: user preferences
-- One row per user, always created with defaults in the same transaction
-- as the auth.users row — it is never absent.

CREATE TABLE auth.user_preferences
(
    user_id          UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
    theme            TEXT        NOT NULL DEFAULT 'system', -- system | light | dark
    language         TEXT        NOT NULL DEFAULT 'en',     -- BCP-47
    timezone         TEXT        NOT NULL DEFAULT 'UTC',    -- IANA
    date_format      TEXT        NOT NULL DEFAULT 'YYYY-MM-DD',
    time_format      TEXT        NOT NULL DEFAULT '24h',    -- 12h | 24h
    notify_on_login  BOOLEAN     NOT NULL DEFAULT true,
    notify_on_revoke BOOLEAN     NOT NULL DEFAULT true,
    compact_mode     BOOLEAN     NOT NULL DEFAULT false,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
