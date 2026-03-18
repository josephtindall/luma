-- Remove group assignments first (FK references custom_roles).
DELETE FROM auth.group_custom_roles
WHERE
    group_id = '00000000-0000-0000-0000-000000000003'
    AND role_id IN (
        '00000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000004'
    );

-- Deleting the roles cascades to custom_role_permissions.
DELETE FROM auth.custom_roles
WHERE
    id IN (
        '00000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000003',
        '00000000-0000-0000-0000-000000000004'
    );
