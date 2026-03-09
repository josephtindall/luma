# RBAC Design — luma-auth + Luma

## Overview

RBAC spans both repos but is owned entirely by luma-auth. Luma never makes local permission decisions — it calls luma-auth's authz endpoint. The permission model can evolve in luma-auth without Luma changing any business logic.

---

## The Four Permission Dimensions

Evaluated in strict order. **Explicit deny at any level always wins and stops evaluation immediately.**

| Priority | Dimension | Owner |
|----------|-----------|-------|
| 1 — most specific | Resource-level explicit permission | luma-auth DB |
| 2 | Vault role policy | luma-auth DB |
| 3 | Instance role policy | luma-auth DB |
| 4 — least specific | Feature flag | luma-auth instance table |
| — | Default | DENY |

### Evaluation Algorithm

```
1. Is this feature enabled on this instance?
   NO → DENY

2. Does an explicit resource-level DENY exist for this user on this resource?
   YES → DENY

3. Does an explicit resource-level ALLOW exist?
   YES → ALLOW

4. Resolve effective Vault role (own + all inherited roles, depth-first)
   Any attached policy DENY this action? YES → DENY
   Any attached policy ALLOW this action? YES → ALLOW

5. Resolve effective instance role (own + inherited)
   Any attached policy DENY? YES → DENY
   Any attached policy ALLOW? YES → ALLOW

6. DEFAULT → DENY
```

---

## Built-In Roles

### Instance-Level (luma-auth)

| Role ID | Name | Key Powers |
|---------|------|-----------|
| `builtin:instance-owner` | Owner | All permissions. Cannot be removed without ownership transfer. One per instance. |
| `builtin:instance-member` | Member | Access Vaults they belong to. Manage own account and sessions only. |

### Vault-Level (Luma)

| Role ID | Name | Key Powers |
|---------|------|-----------|
| `builtin:vault-admin` | Vault Admin | All content actions. Manage Vault members and settings. |
| `builtin:vault-editor` | Editor | Create, edit, delete content. Cannot manage Vault membership. |
| `builtin:vault-viewer` | Viewer | Read-only. No create, edit, or delete. |

---

## Role Inheritance

Custom roles declare a parent and inherit all its permissions. Children can add or explicitly deny inherited permissions. Max depth: 5 levels. Circular inheritance rejected at creation.

```json
{
  "id": "custom:sops-editor",
  "name": "SOPs Editor",
  "parent": "builtin:vault-editor",
  "policies": ["policy:publish-flows"]
}
```

---

## Action Taxonomy

Every permission check uses one of these canonical strings. No other strings are valid anywhere in either codebase.

| Domain | Actions |
|--------|---------|
| `page` | `read`, `create`, `edit`, `delete`, `archive`, `version`, `restore-version`, `share`, `transclude` |
| `task` | `read`, `create`, `edit`, `delete`, `assign`, `close`, `comment` |
| `flow` | `read`, `create`, `edit`, `delete`, `publish`, `execute`, `comment` |
| `vault` | `read`, `create`, `edit`, `delete`, `archive`, `manage-members`, `manage-roles` |
| `user` | `read`, `invite`, `edit`, `delete`, `lock`, `unlock`, `revoke-sessions` |
| `audit` | `read-own`, `read-all` |
| `instance` | `read`, `configure`, `backup`, `restore` |
| `notification` | `read`, `configure-own`, `configure-all` |
| `invitation` | `create`, `revoke`, `list` |

---

## Database Schema — luma-auth

```sql
CREATE TABLE auth.roles (
    id             TEXT PRIMARY KEY,
    name           TEXT        NOT NULL,
    description    TEXT,
    scope          TEXT        NOT NULL,  -- instance | vault
    is_builtin     BOOLEAN     NOT NULL DEFAULT false,
    parent_role_id TEXT        REFERENCES auth.roles(id),
    created_by     UUID,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO auth.roles (id, name, scope, is_builtin) VALUES
    ('builtin:instance-owner',  'Owner',      'instance', true),
    ('builtin:instance-member', 'Member',     'instance', true),
    ('builtin:vault-admin',     'Vault Admin','vault',    true),
    ('builtin:vault-editor',    'Editor',     'vault',    true),
    ('builtin:vault-viewer',    'Viewer',     'vault',    true);

CREATE TABLE auth.policies (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT NOT NULL UNIQUE,
    description TEXT,
    is_builtin  BOOLEAN NOT NULL DEFAULT false,
    created_by  UUID,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE auth.policy_statements (
    id             UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    policy_id      UUID    NOT NULL REFERENCES auth.policies(id) ON DELETE CASCADE,
    effect         TEXT    NOT NULL,  -- allow | deny
    actions        TEXT[]  NOT NULL,
    resource_types TEXT[]  NOT NULL,
    conditions     JSONB   NOT NULL DEFAULT '[]',
    position       INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE auth.role_policies (
    role_id   TEXT NOT NULL REFERENCES auth.roles(id)    ON DELETE CASCADE,
    policy_id UUID NOT NULL REFERENCES auth.policies(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, policy_id)
);

CREATE TABLE auth.resource_permissions (
    id            UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type TEXT    NOT NULL,
    resource_id   TEXT    NOT NULL,
    subject_type  TEXT    NOT NULL,  -- user | role
    subject_id    TEXT    NOT NULL,
    effect        TEXT    NOT NULL,  -- allow | deny
    actions       TEXT[]  NOT NULL,
    granted_by    UUID    NOT NULL,
    expires_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_resource_perms ON
    auth.resource_permissions(resource_type, resource_id, subject_type, subject_id);
```

---

## luma-auth Authz API

```
POST /api/auth/authz/check

Request:
{
  "user_id":       "uuid",
  "action":        "page:edit",
  "resource_type": "page",
  "resource_id":   "TIvsUANKJC",
  "vault_id":      "uuid"
}

Response: { "allowed": true }
      or: { "allowed": false, "reason": "vault_role_deny" }
```

Permission checks cached in Redis with 5-minute TTL. Cache invalidated on any role or vault membership change for that user.

---

## Personal Vault Isolation Rule

The Owner instance role does NOT grant read access to another user's Personal Vault. Enforced at the policy data level — `builtin:instance-owner` policies contain no content-read actions scoped to other users' Personal Vaults. This is enforced by data, not convention.

---

## Luma Usage Pattern

```go
// Every protected handler — one line, no inline role checks
if !h.authz.RequireCan(r.Context(), w, "page:edit", authz.Resource{
    Type:    "page",
    ID:      shortID,
    VaultID: page.VaultID,
}) {
    return
}
```

No handler ever checks `user.Role == "owner"` directly.
