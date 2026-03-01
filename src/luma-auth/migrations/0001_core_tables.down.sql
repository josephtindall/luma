-- Rollback 0001: drop all core tables and the haven schema.
-- WARNING: destroys all data.

DROP TABLE IF EXISTS haven.audit_log CASCADE;
DROP TABLE IF EXISTS haven.refresh_tokens CASCADE;
DROP TABLE IF EXISTS haven.devices CASCADE;
DROP TABLE IF EXISTS haven.users CASCADE;
DROP TABLE IF EXISTS haven.instance CASCADE;
DROP SCHEMA IF EXISTS haven CASCADE;
