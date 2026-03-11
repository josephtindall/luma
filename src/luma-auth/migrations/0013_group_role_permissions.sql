-- Migration 0013: Add granular group and role permissions to Full Control role
--
-- Each group and role operation has its own permission, following the same
-- fine-grained pattern as user:read, user:lock, user:invite, etc.

INSERT INTO auth.custom_role_permissions (role_id, action, effect)
VALUES
  -- Group management
  ('00000000-0000-0000-0000-000000000001', 'group:read',          'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'group:create',        'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'group:rename',        'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'group:delete',        'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'group:add-member',    'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'group:remove-member', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'group:assign-role',   'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'group:unassign-role', 'allow_cascade'),
  -- Custom role management
  ('00000000-0000-0000-0000-000000000001', 'role:read',              'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'role:create',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'role:update',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'role:delete',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'role:set-permission',    'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'role:remove-permission', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'role:assign-user',       'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'role:unassign-user',     'allow_cascade')
ON CONFLICT (role_id, action) DO NOTHING;
