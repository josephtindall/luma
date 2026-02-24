# Luma — Collaborative Workspace

## What This Repo Is

Luma is a self-hosted collaborative workspace providing Pages (block-based documents), Tasks (action tracking), and Flows (conditional branching playbooks), all organized into Vaults. Authentication and identity are handled entirely by the Haven sidecar — Luma owns content, Haven owns identity.

## Design Documents

Read the relevant document before writing any code for a feature. These are authoritative.

| Document | Covers |
|----------|--------|
| `docs/luma-overview.md` | Architecture, service map, tech stack, build phase order |
| `docs/haven-design.md` | How Luma connects to Haven at runtime |
| `docs/rbac-design.md` | Permission model, action taxonomy, authz API calls |
| `docs/vaults-design.md` | Vault types, membership, Personal Vault isolation |
| `docs/urls-design.md` | URL scheme, short ID generation, routing |
| `docs/mentions-design.md` | @ mention registry, dropdown, cross-referencing |
| `docs/pages-design.md` | Block editor, transclusion, revision history |
| `docs/tasks-design.md` | Task lifecycle, status, comments, age tracking |
| `docs/flows-design.md` | Graph model, steps, branching, reader execution |
| `docs/notifications-design.md` | Event types, delivery, per-user preferences |

## Repository Structure

```
luma/
  cmd/server/main.go           # wire deps, start server — zero business logic
  internal/
    pages/
      model.go, service.go, repository.go, handler.go
      postgres/repository.go
    tasks/
      model.go, service.go, repository.go, handler.go
      postgres/repository.go
    flows/
      model.go, service.go, repository.go, handler.go
      postgres/repository.go
    vaults/
      model.go, service.go, repository.go, handler.go
      postgres/repository.go
    mentions/
      registry.go              # shared mention registry
      service.go
    notifications/
      model.go, service.go, dispatcher.go
    search/
      service.go               # cross-feature Cmd+K search
    haven/
      client.go                # HTTP client for all Haven API calls
      middleware.go            # validates Bearer token via Haven on every request
  pkg/
    authz/
      authz.go                 # calls Haven /api/haven/authz/check
    shortid/
      shortid.go               # YouTube-style short ID generation
    editor/
      blocks.dart              # block type definitions — shared across features
    errors/errors.go
    config/config.go
  docs/                        # all ten design documents
  migrations/
    0001_vaults.sql
    0002_short_ids.sql
    0003_pages.sql
    0004_tasks.sql
    0005_flows.sql
    0006_mentions.sql
    0007_notifications.sql
    0008_watches.sql
  luma-web/                    # Flutter web application
  luma-mobile/                 # Flutter iOS + Android
  docker-compose.yml
  docker-compose.dev.yml
  Dockerfile
  .env.example
```

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Backend | Go 1.23+ |
| Web UI | Flutter Web |
| Mobile | Flutter — Android first, then iOS |
| Editor | appflowy_editor — pure Flutter, all platforms |
| Database | PostgreSQL 16 — `luma` schema |
| Cache / Queue | Redis |
| WebSocket | gorilla/websocket |
| IAM | Haven sidecar (separate container) |

## Go Architecture Rules — Non-Negotiable

**Structure:**
- `cmd/server/main.go` wires dependencies, starts server — zero business logic
- Business logic in `internal/{feature}/service.go` only
- Handlers parse requests, call service, write responses — nothing else
- `pkg/` contains reusable code with no internal imports

**Dependency Injection:**
- Constructor injection via `New()` everywhere
- No global variables, no `init()` doing meaningful work
- Concrete implementations wired only in `cmd/server/main.go`

**Interfaces:**
- Every cross-package dependency uses an interface
- Repository interfaces in the feature package, implementations in `postgres/`

**Errors:**
- Always returned, never swallowed
- Always wrapped: `fmt.Errorf("context: %w", err)`
- Sentinel errors in `pkg/errors/errors.go`

**Context:**
- `context.Context` first parameter of every DB/network/filesystem function
- Never stored in a struct

## Haven Integration — Critical

Every authenticated Luma request requires two Haven calls. Both must happen. Neither can be skipped.

```go
// Step 1: Validate the token on every authenticated request
// internal/haven/middleware.go — applied to all protected routes
identity, err := m.client.ValidateToken(r.Context(), token)

// Step 2: Check permission before every protected action
// pkg/authz/authz.go — called from every handler that touches content
if !h.authz.RequireCan(r.Context(), w, "page:edit", authz.Resource{
    Type:    "page",
    ID:      shortID,
    VaultID: page.VaultID,
}) {
    return  // RequireCan already wrote 403
}
```

**No handler ever checks `user.Role == "owner"` or any role string directly. All permission checks go through `authz.RequireCan()`.** This is the single most important rule in the codebase.

## Permission Action Strings

Use only these canonical strings in `authz.RequireCan()` calls:

```
page:read    page:create    page:edit    page:delete    page:archive
page:version page:restore-version       page:share     page:transclude

task:read    task:create    task:edit    task:delete    task:assign
task:close   task:comment

flow:read    flow:create    flow:edit    flow:delete    flow:publish
flow:execute flow:comment

vault:read   vault:create   vault:edit   vault:delete   vault:archive
vault:manage-members        vault:manage-roles

user:read    user:invite    user:edit    user:lock      user:unlock
```

## Flutter Architecture Rules

- `appflowy_editor` is the only editor component — the same widget is used for Pages content, Task descriptions, Task comments, Flow step content, and Flow step comments. Never duplicate it.
- Block type definitions in `pkg/editor/blocks.dart` — imported everywhere, defined once
- One shared `AuthInterceptor` on the HTTP client handles token refresh transparently
- `OfflineProvider` wraps all API calls — serves SQLite cache when Haven is unreachable
- The `@` mention dropdown is one shared widget used identically in all three features
- Column layouts collapse to single-column stacked on mobile automatically

## Short ID Rules

Every Page, Task, and Flow gets a short ID at creation. Short IDs are globally unique across all resource types.

```go
// Always use pkg/shortid/shortid.go
shortID, err := shortid.Generate()
// Check luma.short_ids for collision before inserting
// Max 3 attempts, then return error
```

Never manually construct or hardcode short IDs. Never reuse a short ID after a resource is archived.

## Database Conventions

- All tables in the `luma` schema — the DB user has no access to `haven` schema
- UUIDs for all primary keys: `gen_random_uuid()`
- All timestamps: `TIMESTAMPTZ NOT NULL DEFAULT NOW()`
- Soft deletes: `is_archived BOOLEAN NOT NULL DEFAULT false` + `archived_at TIMESTAMPTZ`
- No hard deletes on user content — ever
- Migrations numbered sequentially: `0001_description.sql`
- Run migrations at startup before the server accepts connections

## Build Phase Order

| Phase | What Gets Built | Gate |
|-------|----------------|------|
| 0 | Haven v1.0 | Must be in daily use 7 days before Phase 1 starts |
| 1 | Vaults + Haven integration | Haven v1.0 complete |
| 2 | Pages — editor, transclusion, revisions | Vaults working |
| 3 | Tasks — full lifecycle, comments | Vaults + Pages working |
| 4 | Flows — steps, branching, execution | Pages editor + Tasks working |
| 5 | Notifications | Pages + Tasks + Flows all working |
| 6 | Global search (Cmd+K) | All three features stable |
| 7 | Mobile — Android then iOS | Web version stable and in daily use |

**Do not start a phase until the previous phase is in actual daily use.**

## Commands

```bash
# Start full stack (postgres + redis + haven + luma)
docker compose up

# Start development (live reload)
docker compose -f docker-compose.dev.yml up

# Run Go tests (always use race detector)
go test -race ./...

# Run Flutter web
cd luma-web && flutter run -d chrome

# Run Flutter mobile
cd luma-mobile && flutter run

# Flutter tests
cd luma-web && flutter test

# Apply migrations
go run ./cmd/migrate up

# Lint Go
golangci-lint run ./...

# Lint Flutter
cd luma-web && flutter analyze

# Build Docker image
docker build -t luma:dev .
```

## Offline Behavior

Luma is usable offline in read-only mode. The `OfflineProvider` caches all content in local SQLite on load. When the server is unreachable:
- Show a persistent banner: "You're offline — viewing cached content"
- All edit controls are disabled — not hidden, disabled with a tooltip explaining why
- No write operations are queued for later sync — changes require an active connection
- Navigation to uncached content shows: "This content isn't available offline"

## Key Invariants

These must always be true. If any test could falsify one of these, that test must exist:

1. A Page, Task, or Flow short ID is globally unique across all three types
2. A user can never see another user's Personal Vault content without an explicit resource permission grant
3. Every content write operation has a corresponding audit event
4. Every permission check goes through `authz.RequireCan()` — zero direct role checks in handlers
5. Archived content is never returned in default list queries — requires explicit `include_archived=true`
6. Circular transclusions are rejected server-side before saving
7. A Flow must always have exactly one Step with `is_start = true`
