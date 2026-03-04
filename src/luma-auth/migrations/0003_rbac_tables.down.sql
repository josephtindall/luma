-- Rollback 0003: drop RBAC tables in dependency order.

DROP TABLE IF EXISTS auth.resource_permissions CASCADE;
DROP TABLE IF EXISTS auth.role_policies CASCADE;
DROP TABLE IF EXISTS auth.policy_statements CASCADE;
DROP TABLE IF EXISTS auth.policies CASCADE;
DROP TABLE IF EXISTS auth.roles CASCADE;
