-- Groups
CREATE TABLE auth.groups (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Membership: users and groups as members of groups
CREATE TABLE auth.group_members (
  group_id    UUID NOT NULL REFERENCES auth.groups(id) ON DELETE CASCADE,
  member_type TEXT NOT NULL CHECK (member_type IN ('user', 'group')),
  member_id   UUID NOT NULL,
  added_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (group_id, member_type, member_id)
);
CREATE INDEX ON auth.group_members (member_type, member_id);

-- Custom roles with optional priority (lower number = higher priority; NULL = lowest)
CREATE TABLE auth.custom_roles (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL UNIQUE,
  priority   INT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Permissions on custom roles
CREATE TABLE auth.custom_role_permissions (
  role_id UUID NOT NULL REFERENCES auth.custom_roles(id) ON DELETE CASCADE,
  action  TEXT NOT NULL,
  effect  TEXT NOT NULL CHECK (effect IN ('allow', 'allow_cascade', 'deny')),
  UNIQUE (role_id, action)
);
CREATE INDEX ON auth.custom_role_permissions (role_id);

-- Custom role → user assignment
CREATE TABLE auth.user_custom_roles (
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id UUID NOT NULL REFERENCES auth.custom_roles(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, role_id)
);

-- Custom role → group assignment
CREATE TABLE auth.group_custom_roles (
  group_id UUID NOT NULL REFERENCES auth.groups(id) ON DELETE CASCADE,
  role_id  UUID NOT NULL REFERENCES auth.custom_roles(id) ON DELETE CASCADE,
  PRIMARY KEY (group_id, role_id)
);
