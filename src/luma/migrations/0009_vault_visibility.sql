-- Add is_private flag to vaults.
-- Private vaults (default) are only visible to explicit members.
-- Non-private (shared) vaults appear for all authenticated users.
ALTER TABLE luma.vaults
    ADD COLUMN is_private BOOLEAN NOT NULL DEFAULT true;
