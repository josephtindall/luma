-- Rollback 0005: MFA

DROP TABLE IF EXISTS auth.passkeys;
DROP TABLE IF EXISTS auth.mfa_challenges;
DROP TABLE IF EXISTS auth.totp_secrets;
ALTER TABLE auth.users DROP COLUMN IF EXISTS mfa_enabled;
