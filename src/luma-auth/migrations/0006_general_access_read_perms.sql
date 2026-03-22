-- Add user:read and group:read to the General Access system role so all
-- instance members can look up users and groups in non-admin contexts
-- (vault member search, mention dropdowns, etc.).
INSERT INTO auth.custom_role_permissions (role_id, action, effect)
VALUES
    ('00000000-0000-0000-0000-000000000002', 'user:read',  'allow'),
    ('00000000-0000-0000-0000-000000000002', 'group:read', 'allow')
ON CONFLICT (role_id, action) DO NOTHING;
