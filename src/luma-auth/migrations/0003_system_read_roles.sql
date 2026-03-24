-- ─── Member Access Role ────────────────────────────────────────────────────────
-- Single role assigned to the "Users" group so every instance member has:
--   • vault:read — see vaults
--   • user:read, group:read — see users and groups
--   • page/task/flow editor permissions — create and edit content
--
-- is_system = true: cannot be modified or deleted through the admin UI.
-- UUID is deterministic so this migration is fully idempotent.

INSERT INTO
    auth.custom_roles (
        id,
        name,
        description,
        is_system
    )
VALUES (
        '00000000-0000-0000-0000-000000000002',
        'General Access',
        'Default permissions for all instance members: read vaults/users/groups and create/edit content',
        true
    ) ON CONFLICT (id) DO NOTHING;

-- Permissions
INSERT INTO
    auth.custom_role_permissions (role_id, action, effect)
VALUES
    -- Page editor
    (
        '00000000-0000-0000-0000-000000000002',
        'page:read',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'page:create',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'page:edit',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'page:delete',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'page:archive',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'page:version',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'page:restore-version',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'page:transclude',
        'allow'
    ),
    -- Task editor
    (
        '00000000-0000-0000-0000-000000000002',
        'task:read',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'task:create',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'task:edit',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'task:delete',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'task:assign',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'task:close',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'task:comment',
        'allow'
    ),
    -- Flow editor
    (
        '00000000-0000-0000-0000-000000000002',
        'flow:read',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'flow:create',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'flow:edit',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'flow:delete',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'flow:execute',
        'allow'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'flow:comment',
        'allow'
    ) ON CONFLICT (role_id, action) DO NOTHING;

-- Assign to the "Users" system group (00000000-0000-0000-0000-000000000003).
INSERT INTO
    auth.group_custom_roles (group_id, role_id)
VALUES (
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000002'
    ) ON CONFLICT (group_id, role_id) DO NOTHING;