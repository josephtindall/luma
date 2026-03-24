-- Rollback: remove descriptions and admin:access from Full Control

UPDATE auth.groups SET description = NULL
WHERE id IN (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003'
);

UPDATE auth.custom_roles SET description = NULL
WHERE id = '00000000-0000-0000-0000-000000000001';

DELETE FROM auth.custom_role_permissions
WHERE role_id = '00000000-0000-0000-0000-000000000001'
  AND action = 'admin:access';
