DELETE FROM auth.custom_role_permissions
WHERE role_id = '00000000-0000-0000-0000-000000000002'
  AND action IN ('user:read', 'group:read');
