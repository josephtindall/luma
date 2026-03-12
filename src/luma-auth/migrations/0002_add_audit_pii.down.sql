-- Remove audit:read-pii from the instance owner policy
UPDATE auth.policy_statements
SET
    actions = array_remove (actions, 'audit:read-pii')
WHERE
    policy_id = '00000000-0000-0000-0000-000000000001';

-- Remove audit:read-pii from the Full Control system custom role
DELETE FROM auth.custom_role_permissions
WHERE
    role_id = '00000000-0000-0000-0000-000000000001'
    AND action = 'audit:read-pii';