# Mentions & Cross-Referencing — Design Document

## Overview

The mention system provides a unified way to reference any named entity — Pages, Tasks, Flows, or Users — from within any editor context across Luma. It is implemented as a shared Go package (`internal/mentions`) imported by all three feature services. There is no separate microservice.

---

## What Can Be Mentioned

| Entity Type | Display Format | URL |
|-------------|---------------|-----|
| Page | 📄 Page title | `/p/{shortId}` |
| Task | ✓ Task title | `/t/{shortId}` |
| Flow | ⟶ Flow title | `/f/{shortId}` |
| User | @Display Name | `/u/{userId}` |

---

## Trigger Methods

Two entry points in the editor, both produce the same dropdown:

**1. @ character** — typing `@` anywhere in an editor block opens the mention dropdown immediately. Subsequent characters filter the results. `Escape` dismisses without inserting. `Enter` or clicking a result inserts the mention.

**2. Toolbar button** — a link icon in the editor toolbar opens the same mention dropdown in a slightly larger format with a search field pre-focused. Useful on mobile where typing `@` to trigger might be less natural.

---

## Dropdown Behavior

```
@ann                              ← user is typing

┌─────────────────────────────────────┐
│  PAGES                              │
│  📄 Annual Checkup Notes            │
│  📄 Announcement Template           │
│                                     │
│  USERS                              │
│  @ Ann (Wife)                       │
│                                     │
│  TASKS                              │
│  ✓ Annual insurance review          │
└─────────────────────────────────────┘
```

- Results grouped by type: Pages, Tasks, Flows, Users
- Max 3 results per group in the dropdown, ordered by relevance then recency
- Search is fuzzy — "ann" matches "Annual", "Announcement", "Ann"
- Only returns results the current user has permission to read (filtered by luma-auth authz)
- Dropdown appears within 150ms of `@` being typed — queries Redis search cache first

---

## The Mention Registry

A shared Go package that all three feature services import. Maintains a searchable index of all mentionable entities.

```go
// internal/mentions/registry.go

type Entry struct {
    Type        string    // page | task | flow | user
    ID          string    // short ID for content, UUID for users
    DisplayText string    // current title or display name
    URL         string    // relative URL
    VaultID     *string   // nil for users
    UpdatedAt   time.Time
}

type Registry interface {
    // Called by each service when content is created, renamed, or deleted
    Register(ctx context.Context, entry Entry) error
    Unregister(ctx context.Context, resourceType, id string) error
    UpdateDisplay(ctx context.Context, resourceType, id, newDisplayText string) error

    // Called by the editor API to populate the @ dropdown
    Search(ctx context.Context, query string, userID string, limit int) ([]Entry, error)
}
```

### Registration Lifecycle

| Event | Action |
|-------|--------|
| Page created | `Register({type: "page", id: shortId, displayText: title, vaultId: ...})` |
| Page title updated | `UpdateDisplay("page", shortId, newTitle)` |
| Page archived/deleted | `Unregister("page", shortId)` |
| Task created | `Register({type: "task", ...})` |
| Task title updated | `UpdateDisplay(...)` |
| Task closed/deleted | `Unregister(...)` |
| Flow created/updated/deleted | Same pattern |
| User registered | `Register({type: "user", id: userId, displayText: displayName})` |
| User display name changed | `UpdateDisplay("user", userId, newName)` |

### Storage

Registry entries stored in Redis as a sorted set for fast prefix search, with the full entry JSON in a hash. PostgreSQL is the source of truth — Redis is rebuilt from DB on service start if empty.

```sql
CREATE TABLE luma.mention_registry (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type TEXT       NOT NULL,
    resource_id  TEXT        NOT NULL,
    display_text TEXT        NOT NULL,
    url          TEXT        NOT NULL,
    vault_id     UUID,
    is_active    BOOLEAN     NOT NULL DEFAULT true,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (resource_type, resource_id)
);
CREATE INDEX idx_mention_search ON luma.mention_registry
    USING gin(to_tsvector('english', display_text));
```

---

## How Mentions Are Stored in Block Content

A mention is stored as a leaf node in the block document JSON:

```json
{
  "type": "mention",
  "attrs": {
    "mentionType": "page",
    "id":          "TIvsUANKJC",
    "displayText": "Annual Checkup Notes",
    "url":         "/p/TIvsUANKJC"
  }
}
```

The `displayText` is stored at insertion time as a snapshot. It is also re-resolved at render time from the registry — so if the referenced page is renamed, the mention display updates on the next render without a migration.

---

## Mention Relationships Table

A separate table tracks which content contains mentions of which other content. Used for:
- "What links here" — showing all content that mentions a given Page/Task/Flow
- Cascade behavior when content is deleted
- Future notification triggers ("someone mentioned this page")

```sql
CREATE TABLE luma.mention_relationships (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    source_type     TEXT        NOT NULL,  -- page | task | flow
    source_id       TEXT        NOT NULL,  -- short ID of content containing the mention
    target_type     TEXT        NOT NULL,  -- page | task | flow | user
    target_id       TEXT        NOT NULL,  -- short ID or user UUID
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (source_type, source_id, target_type, target_id)
);
CREATE INDEX idx_mention_rel_source ON luma.mention_relationships(source_type, source_id);
CREATE INDEX idx_mention_rel_target ON luma.mention_relationships(target_type, target_id);
```

Updated whenever a document is saved — diff the previous mention set against the new mention set and insert/delete relationship rows accordingly.

---

## What Happens When Referenced Content Is Deleted

When a Page, Task, or Flow is archived or deleted:

1. `Unregister()` is called — the entry is removed from the search index
2. The entry in `luma.mention_registry` is marked `is_active = false`
3. Existing mention nodes in block content are NOT removed — they remain as orphaned references
4. At render time, orphaned mentions render as: ~~Annual Checkup Notes~~ *(deleted)* in a muted style
5. The mention relationship rows are preserved for audit purposes — only the registry entry is deactivated

This approach avoids cascading updates across potentially thousands of documents and gives readers context that something was removed rather than silently breaking the reference.

---

## Mention API Endpoint

```
GET /api/luma/mentions/search?q={query}&limit={n}
Authorization: Bearer <access_token>

Response:
{
  "results": [
    {
      "type": "page",
      "id": "TIvsUANKJC",
      "displayText": "Annual Checkup Notes",
      "url": "/p/TIvsUANKJC",
      "vaultName": "Medical"
    },
    {
      "type": "user",
      "id": "f47ac10b-...",
      "displayText": "Ann",
      "url": "/u/f47ac10b-..."
    }
  ]
}
```

Results filtered to only include entities the requesting user has `read` permission for. Permission check uses a batch luma-auth authz call to avoid N+1 round trips for a single dropdown load.
