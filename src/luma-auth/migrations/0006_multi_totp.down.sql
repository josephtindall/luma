-- Rollback 0006: revert to single TOTP secret per user.

DROP INDEX IF EXISTS auth.idx_totp_secrets_user;
ALTER TABLE auth.totp_secrets DROP CONSTRAINT totp_secrets_pkey;
ALTER TABLE auth.totp_secrets DROP COLUMN name;
ALTER TABLE auth.totp_secrets DROP COLUMN id;
ALTER TABLE auth.totp_secrets ADD PRIMARY KEY (user_id);
