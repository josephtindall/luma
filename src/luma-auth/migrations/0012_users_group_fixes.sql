-- Migration 0012: "Users" system group + fix member-base policy

-- Remove 'user:read' from the member-base policy statement.
-- This was incorrectly granting all authenticated members visibility into
-- the admin panel. Only users with explicit admin permissions should see it.
UPDATE auth.policy_statements
SET actions = array_remove(actions, 'user:read')
WHERE policy_id = '00000000-0000-0000-0000-000000000002';

-- Also update the resource_types array to match (remove 'user' since no user: actions remain).
UPDATE auth.policy_statements
SET resource_types = array_remove(resource_types, 'user')
WHERE policy_id = '00000000-0000-0000-0000-000000000002';

-- Add no_member_control: when true, membership is managed automatically by the
-- system and cannot be added or removed by admins.
ALTER TABLE auth.groups
  ADD COLUMN IF NOT EXISTS no_member_control BOOLEAN NOT NULL DEFAULT false;

-- Seed the "Users" system group.
-- Every user is enrolled in this group automatically on creation.
INSERT INTO auth.groups (id, name, is_system, no_member_control)
VALUES ('00000000-0000-0000-0000-000000000003', 'Users', true, true)
ON CONFLICT (id) DO NOTHING;

-- Enroll all existing users into the Users group.
INSERT INTO auth.group_members (group_id, member_type, member_id)
SELECT '00000000-0000-0000-0000-000000000003', 'user', id
FROM auth.users
ON CONFLICT DO NOTHING;
