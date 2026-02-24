# URL Design — Haven + Luma

## Design Principles

- Short and shareable — URLs should be comfortable to read aloud or copy into a message
- Vault is metadata, never addressing — moving content between Vaults never breaks a URL
- Short IDs are globally unique across all content types — no ambiguity in resolution
- Consistent prefixes — any Luma URL is immediately identifiable by its second segment

---

## URL Scheme

### Luma

| Pattern | Resource | Example |
|---------|----------|---------|
| `/p/{shortId}` | Page | `/p/TIvsUANKJC` |
| `/t/{shortId}` | Task | `/t/Rk2mBNwQpL` |
| `/f/{shortId}` | Flow | `/f/Xn9cYdHgKs` |
| `/u/{userId}` | User profile | `/u/f47ac10b` |
| `/a/*` | Admin pages | `/a/members`, `/a/audit`, `/a/vaults` |

### Haven

| Pattern | Resource |
|---------|----------|
| `/a/users` | User management |
| `/a/roles` | Role and policy management |
| `/a/audit` | Full audit log |
| `/a/invitations` | Invitation management |
| `/join` | Invitation registration page |

### Shared Conventions

- `/a/` prefix on both Haven and Luma is for admin-only pages — enforced at both the router level (requires `builtin:instance-owner` or `builtin:instance-admin` role) and the Haven authz check
- No trailing slashes
- All lowercase except the short ID segment which is mixed case

---

## Short ID Specification

### Format

10 characters, mixed-case alphanumeric. Alphabet: `ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789` (62 characters). Approximately 62^10 = 839 trillion possible values.

### Generation

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
```

### Collision Handling

Short IDs are stored in `luma.short_ids`. On generation:
1. Generate candidate ID
2. Check `luma.short_ids` for existence
3. If collision: regenerate, max 3 attempts
4. If 3 collisions: return error (logged as a critical event — this should never happen in practice)

Short IDs are globally unique across all resource types — `/p/TIvsUANKJC` and `/t/TIvsUANKJC` cannot both exist.

```sql
CREATE TABLE luma.short_ids (
    short_id      TEXT        PRIMARY KEY,
    resource_type TEXT        NOT NULL,  -- page | task | flow
    resource_id   UUID        NOT NULL UNIQUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_short_ids_resource ON luma.short_ids(resource_type, resource_id);
```

### URL Resolution

When a request arrives at `/p/TIvsUANKJC`:
1. Router matches the `/p/` prefix and extracts `TIvsUANKJC`
2. Handler queries `luma.short_ids WHERE short_id = 'TIvsUANKJC'`
3. Resolves to the `page_id` UUID
4. Loads the page and checks permission via Haven authz
5. If not found: 404. If permission denied: 403. If archived: 410 Gone.

---

## Deep Links on Mobile

Flutter handles deep links via the `go_router` package. URL patterns registered at the OS level:

```dart
// luma-mobile — router configuration
GoRouter(
  routes: [
    GoRoute(path: '/p/:shortId', builder: (ctx, state) => PageView(shortId: state.pathParameters['shortId']!)),
    GoRoute(path: '/t/:shortId', builder: (ctx, state) => TaskView(shortId: state.pathParameters['shortId']!)),
    GoRoute(path: '/f/:shortId', builder: (ctx, state) => FlowView(shortId: state.pathParameters['shortId']!)),
    GoRoute(path: '/u/:userId',  builder: (ctx, state) => UserProfileView(userId: state.pathParameters['userId']!)),
    GoRoute(path: '/join',       builder: (ctx, state) => InvitationView(token: state.uri.queryParameters['token'])),
  ],
)
```

If the app is not installed, the URL opens in the browser and resolves via the web app. No app-store redirect logic needed for a local network deployment.

---

## Mention Link Format

When the `@` mention system inserts a link (see `mentions-design.md`), it uses the short URL format. Mention links stored in block content as:

```json
{
  "type": "mention",
  "attrs": {
    "type": "page",
    "shortId": "TIvsUANKJC",
    "displayText": "Annual Checkup Notes",
    "url": "/p/TIvsUANKJC"
  }
}
```

The URL is relative — it works on any hostname the instance is served from.

---

## Admin URL Access Control

Any route under `/a/` requires the user to have `builtin:instance-owner` or `builtin:instance-member` with admin-level instance role. This is enforced at two levels:

1. **Router middleware** — checks the role from the validated Haven token before the handler runs
2. **Haven authz check** — the handler additionally calls Haven to verify the specific admin action permission

Both checks must pass. Failing either returns 403 with no information about what admin pages exist.
