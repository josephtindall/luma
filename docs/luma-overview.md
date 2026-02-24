# Luma — Overview & Architecture

## What Luma Is

Luma is a self-hosted collaborative workspace. It provides three primary features — Pages, Tasks, and Flows — organized into Vaults. Authentication and identity management are handled entirely by the Haven sidecar. Luma owns content; Haven owns identity.

Luma is the first consumer of Haven. Future projects fork Haven independently and connect to it the same way.

---

## Repository Structure

```
luma/
  cmd/
    server/
      main.go                  # wire deps, start HTTP server — zero business logic
  internal/
    pages/
      model.go
      service.go
      repository.go
      handler.go
      postgres/repository.go
    tasks/
      model.go, service.go, repository.go, handler.go, postgres/repository.go
    flows/
      model.go, service.go, repository.go, handler.go, postgres/repository.go
    vaults/
      model.go, service.go, repository.go, handler.go, postgres/repository.go
    mentions/
      registry.go              # shared mention registry — see mentions-design.md
      service.go
    notifications/
      model.go, service.go, dispatcher.go
    search/
      service.go               # cross-feature search, called by Cmd+K handler
    haven/
      client.go                # HTTP client wrapping all Haven API calls
      middleware.go            # validates Bearer token via Haven on every request
  pkg/
    authz/
      authz.go                 # calls Haven /api/haven/authz/check
    shortid/
      shortid.go               # YouTube-style short ID generation
    editor/
      blocks.go                # block type definitions shared across features
    errors/
      errors.go
    config/
      config.go
  api/
    openapi/luma.yaml
  migrations/
    0001_vaults.sql
    0002_pages.sql
    0003_tasks.sql
    0004_flows.sql
    0005_mentions.sql
    0006_notifications.sql
  luma-web/                    # Flutter web application
  luma-mobile/                 # Flutter iOS + Android application
  docker-compose.yml
  .env.example
  CLAUDE.md
```

---

## Service Architecture

```
HOME LAN
  │
  └─ Caddy :443 (only port exposed to LAN)
       ├─ /api/haven/*  → Haven container :8001
       ├─ /api/luma/*   → Luma container  :8002
       ├─ /ws           → Luma WebSocket  :8002
       └─ /             → Flutter web build (static)

Docker internal network (not reachable from LAN):
  haven     :8001   — IAM, auth, RBAC, audit
  luma      :8002   — pages, tasks, flows, vaults
  postgres  :5432   — shared instance, separate schemas per service
  redis     :6379   — sessions, rate limiting, notification queue, search cache
```

---

## Technology Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| Backend | Go 1.23+ | Single binary per service |
| Web UI | Flutter Web | Dart, same codebase as mobile |
| Mobile | Flutter iOS + Android | Web-first, then Android, then iOS |
| Editor | appflowy_editor | Block-based, pure Flutter, custom block types |
| Database | PostgreSQL 16 | Schema-per-service isolation |
| Cache / Queue | Redis | Notifications queue, search cache, rate limiting |
| WebSocket | Go stdlib + gorilla/websocket | Real-time notifications |
| Proxy | Caddy | TLS termination, routing |
| Containers | Docker Compose | One container per service |

---

## Haven Integration

Every authenticated Luma request goes through two Haven calls:

```go
// internal/haven/middleware.go
// Step 1: Validate the Bearer token
func (m *Middleware) Authenticate(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        token := extractBearer(r)
        identity, err := m.client.ValidateToken(r.Context(), token)
        if err != nil {
            writeUnauthorized(w)
            return
        }
        next.ServeHTTP(w, r.WithContext(withIdentity(r.Context(), identity)))
    })
}

// pkg/authz/authz.go
// Step 2: Check permission before any protected action
func (a *Authorizer) RequireCan(
    ctx context.Context,
    w http.ResponseWriter,
    action string,
    resource Resource,
) bool {
    ok, err := a.havenClient.CheckPermission(ctx, authz.CheckRequest{
        UserID:       IdentityFromContext(ctx).UserID,
        Action:       action,
        ResourceType: resource.Type,
        ResourceID:   resource.ID,
        VaultID:      resource.VaultID,
    })
    if err != nil || !ok {
        writeForbidden(w)
        return false
    }
    return true
}
```

---

## Database Schema Ownership

Luma's PostgreSQL user has access only to the `luma` schema. Haven has its own `haven` schema. No cross-schema joins ever — user data resolved by calling Haven's API.

```sql
-- luma schema contains:
luma.vaults
luma.vault_members
luma.pages
luma.page_blocks
luma.page_revisions
luma.tasks
luma.task_comments
luma.flows
luma.flow_steps
luma.flow_edges
luma.mentions
luma.notifications
luma.notification_preferences
luma.short_ids
```

---

## Short ID Generation

Every Page, Task, and Flow gets a globally unique short ID at creation time. YouTube-style: 10 characters, alphanumeric mixed case.

```go
// pkg/shortid/shortid.go
const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
const idLength = 10

func Generate() (string, error) {
    b := make([]byte, idLength)
    if _, err := rand.Read(b); err != nil {
        return "", fmt.Errorf("generating short id: %w", err)
    }
    for i := range b {
        b[i] = alphabet[int(b[i])%len(alphabet)]
    }
    return string(b), nil
}

// Stored in luma.short_ids for collision detection
// On collision (extremely rare): regenerate, max 3 attempts, then error
```

```sql
CREATE TABLE luma.short_ids (
    short_id      TEXT        PRIMARY KEY,
    resource_type TEXT        NOT NULL,  -- page | task | flow
    resource_id   UUID        NOT NULL,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

## URL Routing

See `urls-design.md` for complete specification. Summary:

```
/p/{shortId}          Pages
/t/{shortId}          Tasks
/f/{shortId}          Flows
/u/{userId}           User profiles (served by Haven)
/a/*                  Admin (Haven admin and Luma admin both use /a/)
```

Vault is never in the URL — it appears in the breadcrumb only.

---

## Go Architecture Rules

These apply to every file in this repo:

- `cmd/server/main.go` wires dependencies and starts the server — zero business logic
- All dependencies injected via constructor `New()` functions — no global state
- Every cross-package dependency crosses through an interface
- `context.Context` is first parameter of every DB/network/filesystem function — never stored in structs
- Errors always returned, always wrapped: `fmt.Errorf("context: %w", err)`
- Sentinel errors in `pkg/errors/errors.go` — handlers map these to HTTP status codes
- All config validated at startup — missing security config is a fatal error

---

## Flutter Architecture Rules

- One shared `AuthInterceptor` on the HTTP client refreshes tokens transparently
- `appflowy_editor` is the only editor component — never duplicated per feature
- Editor block type definitions live in `pkg/editor/blocks.go` and are imported by Pages, Tasks (description), and Flows (step content)
- Offline state managed centrally — `OfflineProvider` wraps all API calls and serves SQLite cache when offline
- `@` mention dropdown is one shared widget — used identically in Pages, Tasks, and Flows

---

## Environment Variables

```bash
# Required
LUMA_DB_URL=postgres://luma_user:${LUMA_DB_PASS}@postgres:5432/luma
LUMA_REDIS_URL=redis://redis:6379
LUMA_HAVEN_URL=http://haven:8001        # internal Docker network URL
LUMA_PUBLIC_URL=https://luma.local

# Optional
LUMA_LOG_LEVEL=info
LUMA_MAX_UPLOAD_MB=100
LUMA_REVISION_RETENTION_DAYS=30         # default — configurable in admin UI
```

---

## Build Phase Order

| Phase | Deliverable | Depends On |
|-------|-------------|-----------|
| 0 | Haven v1.0 complete and in daily use | Nothing |
| 1 | Vaults + RBAC integration with Haven | Haven v1.0 |
| 2 | Pages — editor, revisions, transclusion | Vaults |
| 3 | Tasks — full lifecycle with comments | Vaults, Pages (links) |
| 4 | Flows — steps, branching, execution | Pages (editor), Tasks (links) |
| 5 | Notifications — all events, all channels | Pages, Tasks, Flows |
| 6 | Global search — cross-feature Cmd+K | Pages, Tasks, Flows |
| 7 | Mobile — Android then iOS | All features stable on web |

Each phase ships only when it is in actual daily use before the next phase begins.
