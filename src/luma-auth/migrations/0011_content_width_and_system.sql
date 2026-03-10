-- Content width preference on the instance (applied site-wide by the owner).
ALTER TABLE auth.instance
  ADD COLUMN IF NOT EXISTS content_width TEXT NOT NULL DEFAULT 'wide'
    CHECK (content_width IN ('narrow', 'wide', 'max'));

-- System flag: system entities are seeded by this migration and are immutable.
ALTER TABLE auth.custom_roles
  ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE auth.groups
  ADD COLUMN IF NOT EXISTS is_system BOOLEAN NOT NULL DEFAULT false;

-- ── System role: "Full Control" ──────────────────────────────────────────────
-- This role grants allow_cascade on every action in the permission taxonomy.
-- It cannot be modified or deleted by anyone, including the owner.
INSERT INTO auth.custom_roles (id, name, priority, is_system)
VALUES ('00000000-0000-0000-0000-000000000001', 'Full Control', 0, true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.custom_role_permissions (role_id, action, effect)
VALUES
  -- Pages
  ('00000000-0000-0000-0000-000000000001', 'page:read',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'page:create',          'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'page:edit',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'page:delete',          'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'page:archive',         'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'page:version',         'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'page:restore-version', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'page:share',           'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'page:transclude',      'allow_cascade'),
  -- Tasks
  ('00000000-0000-0000-0000-000000000001', 'task:read',    'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'task:create',  'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'task:edit',    'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'task:delete',  'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'task:assign',  'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'task:close',   'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'task:comment', 'allow_cascade'),
  -- Flows
  ('00000000-0000-0000-0000-000000000001', 'flow:read',    'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'flow:create',  'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'flow:edit',    'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'flow:delete',  'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'flow:publish', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'flow:execute', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'flow:comment', 'allow_cascade'),
  -- Vaults
  ('00000000-0000-0000-0000-000000000001', 'vault:read',           'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'vault:create',         'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'vault:edit',           'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'vault:delete',         'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'vault:archive',        'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'vault:manage-members', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'vault:manage-roles',   'allow_cascade'),
  -- Users
  ('00000000-0000-0000-0000-000000000001', 'user:read',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'user:invite',          'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'user:edit',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'user:delete',          'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'user:lock',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'user:unlock',          'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'user:revoke-sessions', 'allow_cascade'),
  -- Audit
  ('00000000-0000-0000-0000-000000000001', 'audit:read-own', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'audit:read-all', 'allow_cascade'),
  -- Instance
  ('00000000-0000-0000-0000-000000000001', 'instance:read',      'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'instance:configure', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'instance:backup',    'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'instance:restore',   'allow_cascade'),
  -- Notifications
  ('00000000-0000-0000-0000-000000000001', 'notification:read',            'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'notification:configure-own',   'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'notification:configure-all',   'allow_cascade'),
  -- Invitations
  ('00000000-0000-0000-0000-000000000001', 'invitation:create', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'invitation:revoke', 'allow_cascade'),
  ('00000000-0000-0000-0000-000000000001', 'invitation:list',   'allow_cascade')
ON CONFLICT (role_id, action) DO NOTHING;

-- ── System group: "Super Admins" ─────────────────────────────────────────────
-- Members of this group get all permissions via the Full Control role.
-- The group cannot be deleted (is_system = true) but its membership is editable.
INSERT INTO auth.groups (id, name, is_system)
VALUES ('00000000-0000-0000-0000-000000000002', 'Super Admins', true)
ON CONFLICT (id) DO NOTHING;

-- Assign Full Control role to Super Admins.
INSERT INTO auth.group_custom_roles (group_id, role_id)
VALUES ('00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001')
ON CONFLICT DO NOTHING;
