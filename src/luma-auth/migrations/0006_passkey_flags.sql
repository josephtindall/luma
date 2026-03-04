-- Add backup_eligible and backup_state columns to auth.passkeys.
-- These flags are required by the WebAuthn spec (BE/BS bits) and are
-- validated by the go-webauthn library during login assertion.
ALTER TABLE auth.passkeys
ADD COLUMN backup_eligible BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN backup_state BOOLEAN NOT NULL DEFAULT FALSE;