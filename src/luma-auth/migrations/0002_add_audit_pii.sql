-- Add audit:read-pii to the instance owner policy
UPDATE auth.policy_statements
SET
    actions = array_append (actions, 'audit:read-pii')
WHERE
    policy_id = '00000000-0000-0000-0000-000000000001'
    AND NOT(
        'audit:read-pii' = ANY (actions)
    );

-- Add audit:read-pii to the Full Control system custom role
INSERT INTO
    auth.custom_role_permissions (role_id, action, effect)
VALUES (
        '00000000-0000-0000-0000-000000000001',
        'audit:read-pii',
        'allow_cascade'
    ) ON CONFLICT (role_id, action) DO NOTHING;