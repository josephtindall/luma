-- Rollback 0003: drop RBAC tables in dependency order.

DROP TABLE IF EXISTS haven.resource_permissions CASCADE;
DROP TABLE IF EXISTS haven.role_policies CASCADE;
DROP TABLE IF EXISTS haven.policy_statements CASCADE;
DROP TABLE IF EXISTS haven.policies CASCADE;
DROP TABLE IF EXISTS haven.roles CASCADE;
