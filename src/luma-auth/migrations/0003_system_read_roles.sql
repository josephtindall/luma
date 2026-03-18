-- ─── System Read Roles ────────────────────────────────────────────────────────
-- Three read-only system roles assigned to the "Users" group so every
-- instance member can read vaults, users, and groups by default.
--
-- is_system = true: cannot be modified or deleted through the admin UI.
-- UUIDs are deterministic so this migration is fully idempotent.

INSERT INTO
    auth.custom_roles (id, name, description, is_system)
VALUES
    (
        '00000000-0000-0000-0000-000000000002',
        'Vaults Read',
        'Read-only access to vaults',
        true
    ),
    (
        '00000000-0000-0000-0000-000000000003',
        'Users Read',
        'Read-only access to users',
        true
    ),
    (
        '00000000-0000-0000-0000-000000000004',
        'Groups Read',
        'Read-only access to groups',
        true
    ) ON CONFLICT (id) DO NOTHING;

-- Permissions: one allow on the relevant read action per role.
INSERT INTO
    auth.custom_role_permissions (role_id, action, effect)
VALUES
    ('00000000-0000-0000-0000-000000000002', 'vault:read', 'allow'),
    ('00000000-0000-0000-0000-000000000003', 'user:read', 'allow'),
    ('00000000-0000-0000-0000-000000000004', 'group:read', 'allow') ON CONFLICT (role_id, action) DO NOTHING;

-- Assign all three roles to the "Users" system group
-- (00000000-0000-0000-0000-000000000003).
INSERT INTO
    auth.group_custom_roles (group_id, role_id)
VALUES
    (
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000002'
    ),
    (
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000003'
    ),
    (
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000004'
    ) ON CONFLICT (group_id, role_id) DO NOTHING;
