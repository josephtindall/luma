-- Prevent TOTP code replay by tracking the last accepted time-step counter.
ALTER TABLE auth.totp_secrets ADD COLUMN last_used_counter BIGINT NOT NULL DEFAULT 0;
