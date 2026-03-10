-- Migration 0013: Add group:manage and role:manage to Full Control role
--
-- These permissions gate access to the Groups and Roles admin screens.
-- Without them, Super Admins (and any user with the Full Control role)
-- cannot see or use those tabs even though they have the role assigned.

INSERT INTO auth.custom_role_permissions (role_id, action, effect)
VALUES
  ('00000000-0000-0000-0000-000000000001', 'group:manage', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'role:manage',  'allow_cascade')
ON CONFLICT (role_id, action) DO NOTHING;
