-- =============================================================================
-- 0007: Add descriptions to system groups/roles + admin:access to Full Control
-- =============================================================================

-- ── Descriptions for system groups ───────────────────────────────────────────

UPDATE auth.groups
SET description = 'Members of this group have full control over the instance.'
WHERE id = '00000000-0000-0000-0000-000000000002'; -- Super Admins

UPDATE auth.groups
SET description = 'All users of the instance are automatically added to this group.'
WHERE id = '00000000-0000-0000-0000-000000000003'; -- Users

-- ── Description for Full Control system role ─────────────────────────────────

UPDATE auth.custom_roles
SET description = 'All permissions are cascade-enabled for this role.'
WHERE id = '00000000-0000-0000-0000-000000000001'; -- Full Control

-- ── Add admin:access permission to Full Control role ─────────────────────────

INSERT INTO auth.custom_role_permissions (role_id, action, effect)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'admin:access',
    'allow_cascade'
) ON CONFLICT (role_id, action) DO NOTHING;
