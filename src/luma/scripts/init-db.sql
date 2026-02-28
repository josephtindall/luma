-- Create the luma schema and restrict the luma_user to it.
-- Haven has its own database/user — no cross-schema access.
CREATE SCHEMA IF NOT EXISTS luma;
GRANT ALL ON SCHEMA luma TO luma_user;
ALTER ROLE luma_user SET search_path TO luma;
