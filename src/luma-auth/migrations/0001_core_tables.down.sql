-- Rollback 0001: drop all core tables and the auth schema.
-- WARNING: destroys all data.

DROP TABLE IF EXISTS auth.audit_log CASCADE;
DROP TABLE IF EXISTS auth.refresh_tokens CASCADE;
DROP TABLE IF EXISTS auth.devices CASCADE;
DROP TABLE IF EXISTS auth.users CASCADE;
DROP TABLE IF EXISTS auth.instance CASCADE;
DROP SCHEMA IF EXISTS auth CASCADE;
