# Vaults — Design Document

## What a Vault Is

A Vault is the top-level organizational container in Luma. Every Page, Task, and Flow belongs to exactly one Vault. Vaults are how users separate concerns — "Home", "Medical", "School", "Work" — without mixing content between contexts.

Vault is organizational context, never addressing context. It appears in the UI breadcrumb but never in the URL.

---

## Vault Types

| Type | Behavior |
|------|----------|
| `personal` | Created automatically for every user on registration. Private by default — invisible to all other users including the instance Owner. Cannot be deleted, only archived. |
| `shared` | Created explicitly by users with `vault:create` permission. Visible only to members. Members added by a Vault Admin. |

---

## Personal Vault Rules

- One Personal Vault per user, created atomically with their account — the two cannot exist independently
- Name defaults to "{Display Name}'s Space" — user can rename it
- No other user can see it exists in navigation unless explicitly granted access
- The instance Owner can see that Personal Vaults exist in the admin panel (for account management) but cannot see their contents
- Content in a Personal Vault can be explicitly shared via a resource-level permission grant (see `rbac-design.md`) without moving it out of the Vault

---

## Vault Membership and Roles

Every member of a Shared Vault has exactly one Vault-level role: Admin, Editor, or Viewer. See `rbac-design.md` for full role definitions.

The creator of a Shared Vault is automatically assigned `builtin:vault-admin`. They can assign other members as Admins. There must always be at least one Admin — the last Admin cannot be removed or downgraded until another Admin is assigned.

---

## Database Schema

```sql
CREATE TABLE luma.vaults (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL,
    slug        TEXT        NOT NULL UNIQUE,
    type        TEXT        NOT NULL DEFAULT 'shared',
    owner_id    TEXT        NOT NULL,  -- Haven user UUID
    description TEXT,
    icon        TEXT,                  -- emoji or icon identifier
    color       TEXT,                  -- hex color for vault badge in nav
    is_archived BOOLEAN     NOT NULL DEFAULT false,
    archived_at TIMESTAMPTZ,
    archived_by TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT vault_type_values CHECK (type IN ('personal', 'shared'))
);
CREATE INDEX idx_vaults_owner ON luma.vaults(owner_id);

CREATE TABLE luma.vault_members (
    vault_id   UUID NOT NULL REFERENCES luma.vaults(id) ON DELETE CASCADE,
    user_id    TEXT NOT NULL,  -- Haven user UUID
    role_id    TEXT NOT NULL,  -- Haven role ID
    added_by   TEXT,
    added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (vault_id, user_id)
);
CREATE INDEX idx_vault_members_user ON luma.vault_members(user_id);
```

---

## API Endpoints

```
GET    /api/luma/vaults                  list vaults user is a member of
POST   /api/luma/vaults                  create shared vault
GET    /api/luma/vaults/{id}             get vault details
PATCH  /api/luma/vaults/{id}             update name, description, icon, color
DELETE /api/luma/vaults/{id}             archive vault (soft delete)

GET    /api/luma/vaults/{id}/members     list members
POST   /api/luma/vaults/{id}/members     add member
PATCH  /api/luma/vaults/{id}/members/{userId}   change member role
DELETE /api/luma/vaults/{id}/members/{userId}   remove member
```

All endpoints require authentication via Haven. Vault management actions require `vault:manage-members` or `vault:manage-roles` permission checked via Haven authz.

---

## UI Behavior

### Navigation Rail

Vaults appear in the left navigation rail in two groups:

```
PERSONAL
  · My Space          ← always first, always visible

SHARED
  · Home              ← ordered by last activity descending
  · Medical
  · School
```

The Personal Vault is always visible to its owner and never appears in anyone else's navigation. Shared Vaults appear only for members.

### Vault Switcher

Content views (Pages list, Tasks board, Flows list) show a Vault filter at the top. Default view is "All Vaults" — shows content across all Vaults the user has access to. Selecting a Vault filters to that Vault only.

### Breadcrumb

Every content page shows the Vault in the breadcrumb:

```
Home  ›  Emergency Contacts
Medical  ›  Annual Checkup Notes
```

Clicking the Vault name in the breadcrumb navigates to that Vault's content list.

### Creating a Shared Vault

Modal dialog: Name (required), Description (optional), Icon (emoji picker), Color (palette of 12 options). On creation, the creator is automatically made Vault Admin and the Vault appears immediately in their navigation.

### Archiving a Vault

Archived Vaults are hidden from navigation. All content inside is preserved and searchable by Vault Admins. Content cannot be created or edited in an archived Vault. Unarchiving restores it fully. Permanent deletion is not supported — archiving is the only removal action.

---

## Vault in Content Creation

When creating a Page, Task, or Flow, the user selects which Vault it belongs to from a dropdown. The dropdown shows only Vaults where the user has `page:create`, `task:create`, or `flow:create` permission. The Personal Vault is always an option for the content owner. Default selection is the Vault currently active in the sidebar filter.

Content cannot be moved between Vaults after creation in Phase 1. The Vault assignment is set at creation and is permanent until a move feature is added in a future phase.
