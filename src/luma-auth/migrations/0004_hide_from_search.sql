-- Add hide_from_search flag to users and groups.
-- When true, non-admin directory search endpoints will exclude the user/group.

ALTER TABLE auth.users
    ADD COLUMN IF NOT EXISTS hide_from_search BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE auth.groups
    ADD COLUMN IF NOT EXISTS hide_from_search BOOLEAN NOT NULL DEFAULT false;
