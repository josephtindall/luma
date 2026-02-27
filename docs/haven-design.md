# Haven — Identity & Access Management

## What Haven Is

Haven is a standalone IAM sidecar service distributed as a Docker image. Any project that needs authentication adds one block to its `docker-compose.yml` and gets full identity management: registration, login, sessions, device tracking, RBAC enforcement, and a complete audit log.

Haven is not a library compiled into the consumer app. It is a running service that the consumer app calls over HTTP. Updating Haven means changing the image tag and restarting the container — no recompilation of the consumer app required.

```yaml
# Every project that uses Haven adds this to docker-compose.yml
haven:
  image: yourname/haven:latest
  restart: unless-stopped
  environment:
    HAVEN_DB_URL: postgres://haven_user:${HAVEN_DB_PASS}@postgres:5432/haven
    HAVEN_JWT_SIGNING_KEY: ${HAVEN_JWT_SIGNING_KEY}
    HAVEN_PUBLIC_URL: https://auth.yourapp.local
  networks:
    - internal
```

## Runtime Relationship with Luma

Luma calls Haven's API for three things:
1. **Token validation** — every authenticated Luma request calls `GET /api/haven/validate` with the Bearer token
2. **Permission checks** — Luma calls `POST /api/haven/authz/check` before any protected action
3. **User context** — Luma calls `GET /api/haven/users/{id}` to resolve user display info

Haven never calls Luma. The dependency is one-directional.

```
Browser/App
    │
    ▼
Luma API ──[POST /api/haven/authz/check]──► Haven API
    │                                           │
    ▼                                           ▼
Luma DB                                    Haven DB
(docs, tasks, flows)                  (users, sessions, audit)
```

---

## Bootstrap State Machine

Three states enforced at DB column, HTTP middleware, and handler level simultaneously.

| State | Description | Accessible Endpoints |
|-------|-------------|---------------------|
| `UNCLAIMED` | Fresh install, no owner | `GET /` (setup UI), `POST /api/setup/verify-token` only. All others: 503. |
| `SETUP` | Token verified, owner mid-registration. Expires 30 min if not completed. | `GET /`, `POST /api/setup/*` only. All others: 503. |
| `ACTIVE` | Owner exists, fully operational, registration closed | All routes. `POST /api/setup/*` returns 410 Gone. |

### Transitions

```
UNCLAIMED ──[valid setup token]──► SETUP ──[owner created atomically]──► ACTIVE
                                     │
                                     └──[30 min timeout]──► UNCLAIMED (new token generated)
```

No transition exists from ACTIVE. Factory reset requires: `haven-cli factory-reset --confirm-destroy-all-data`

### Setup Token Rules
- 32 cryptographically random bytes, base64url encoded
- Stored as SHA-256 hash only — raw token never persisted
- Printed to stdout on first start, reprinted on each regeneration
- Expires 2 hours from generation
- Invalidated after 3 failed attempts (new token generated immediately)
- CLI unattended path bypasses the token — shell access is equivalent proof

---

## Installation Paths

### Path A — Web UI Wizard (primary)

Five-step linear flow. Same underlying API as CLI path.

**Step 1 — Verify Ownership:** Single setup code field. Three failed attempts invalidates and regenerates.

**Step 2 — Name Your Instance:** Instance name (2–64 chars), IANA timezone, BCP-47 locale.

**Step 3 — Create Owner Account:** Full name, email, password (min 12 chars), explicit acknowledgment checkbox. Owner creation and state transition to ACTIVE happen in one database transaction — atomic, no partial state.

**Step 4 — Personal Vault:** Informational. Personal Vault created automatically. Optional: create one shared Vault now.

**Step 5 — Complete:** Direct redirect to home dashboard. Dismissible "Invite members" banner.

### Path B — CLI Unattended

```bash
# Required environment variables
HAVEN_INSTANCE_NAME="Acme Engineering"
HAVEN_OWNER_EMAIL="admin@acme.com"
HAVEN_OWNER_NAME="IT Administrator"
HAVEN_OWNER_PASSWORD="..."           # min 12 chars — use a secrets manager
HAVEN_INSTANCE_TIMEZONE="America/New_York"
HAVEN_INSTANCE_LOCALE="en-US"

# Secrets
HAVEN_JWT_SIGNING_KEY="..."          # 64 bytes hex — fatal if missing
HAVEN_DB_PASSWORD="..."
HAVEN_CA_KEY_PASSPHRASE="..."

# Optional
HAVEN_SHARED_VAULT_NAME="Team"       # creates one shared vault
HAVEN_UNATTENDED=true

# Commands
haven-cli setup --unattended         # full unattended install
haven-cli generate-secrets > .env    # generate all secrets
haven-cli validate-config            # verify before starting
haven-cli healthcheck                # exits 0 if healthy
```

Idempotent — if already ACTIVE, exits 0 with no changes.

---

## Secret Zero

| Secret | Specification |
|--------|--------------|
| JWT Signing Key | 512-bit (64 bytes) random, hex encoded. Fatal startup error if missing or < 32 bytes. Never written to database — memory only. |
| Database Password | 256-bit random. Connection string only. |
| Internal CA Private Key | ECDSA P-384. Passphrase-protected. Stored at `/etc/haven/ca/`. Issues TLS leaf certs. |
| Instance Master Key | Derived from JWT signing key via HKDF, label `"haven-master-key-v1"`. Root for Phase 2 encryption key derivation. Never stored — always re-derived. |

### JWT Signing Key Rotation (zero-downtime)
```bash
HAVEN_JWT_SIGNING_KEY="<new key>"
HAVEN_JWT_SIGNING_KEY_PREV="<old key>"  # validates tokens signed with old key
# After 15 min (one access token lifetime): remove _PREV on next restart
```

---

## Database Schema — `haven`

```sql
CREATE TABLE haven.instance (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name                    TEXT        NOT NULL,
    locale                  TEXT        NOT NULL DEFAULT 'en-US',
    timezone                TEXT        NOT NULL DEFAULT 'UTC',
    setup_state             TEXT        NOT NULL DEFAULT 'unclaimed',
    setup_token_hash        TEXT,
    setup_token_expires_at  TIMESTAMPTZ,
    activated_at            TIMESTAMPTZ,
    version                 TEXT        NOT NULL DEFAULT '1.0.0',
    features                JSONB       NOT NULL DEFAULT '{}',
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT setup_state_values CHECK (setup_state IN ('unclaimed', 'setup', 'active'))
);

CREATE TABLE haven.users (
    id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    email                 TEXT        NOT NULL UNIQUE,
    display_name          TEXT        NOT NULL,
    password_hash         TEXT        NOT NULL,           -- Argon2id PHC string
    instance_role_id      TEXT        NOT NULL DEFAULT 'builtin:member',
    avatar_seed           TEXT,
    failed_login_attempts INT         NOT NULL DEFAULT 0,
    locked_at             TIMESTAMPTZ,
    locked_reason         TEXT,
    created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE haven.devices (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES haven.users(id) ON DELETE CASCADE,
    name         TEXT        NOT NULL,
    platform     TEXT        NOT NULL,  -- web | ios | android | agent
    fingerprint  TEXT        NOT NULL,
    user_agent   TEXT,
    last_seen_at TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT platform_values CHECK (platform IN ('web', 'ios', 'android', 'agent'))
);
CREATE INDEX idx_devices_user ON haven.devices(user_id);

-- Raw token NEVER stored — only SHA-256 hash
CREATE TABLE haven.refresh_tokens (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id   UUID        NOT NULL REFERENCES haven.devices(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- IMMUTABLE: DB user has INSERT + SELECT only. No UPDATE, no DELETE ever.
CREATE TABLE haven.audit_log (
    id          BIGSERIAL   PRIMARY KEY,
    user_id     UUID        REFERENCES haven.users(id),
    device_id   UUID        REFERENCES haven.devices(id),
    event       TEXT        NOT NULL,
    ip_address  INET,
    user_agent  TEXT,
    metadata    JSONB,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_user      ON haven.audit_log(user_id);
CREATE INDEX idx_audit_occurred  ON haven.audit_log(occurred_at DESC);

GRANT SELECT, INSERT ON haven.audit_log TO haven_db_user;
REVOKE UPDATE, DELETE ON haven.audit_log FROM haven_db_user;

CREATE TABLE haven.user_preferences (
    user_id          UUID    PRIMARY KEY REFERENCES haven.users(id) ON DELETE CASCADE,
    theme            TEXT    NOT NULL DEFAULT 'system',
    language         TEXT    NOT NULL DEFAULT 'en',
    timezone         TEXT    NOT NULL DEFAULT 'UTC',
    date_format      TEXT    NOT NULL DEFAULT 'YYYY-MM-DD',
    time_format      TEXT    NOT NULL DEFAULT '24h',
    notify_on_login  BOOLEAN NOT NULL DEFAULT true,
    notify_on_revoke BOOLEAN NOT NULL DEFAULT true,
    compact_mode     BOOLEAN NOT NULL DEFAULT false,
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Created with defaults in same transaction as haven.users row — always exists
```

---

## Security Specifications

| Requirement | Specification |
|-------------|--------------|
| Password hashing | Argon2id: time=3, memory=65536KB, parallelism=2, salt=32B, key=32B. ~250ms target. PHC string format. `golang.org/x/crypto/argon2` |
| JWT signing | HMAC-SHA256. Payload: `sub`, `did`, `role`, `iat`, `exp`, `jti`. Lifetime: 15 min exactly. |
| Refresh token | 32 random bytes, base64url. Store SHA-256 hash only. 30-day lifetime. |
| Token reuse | Consumed token presented again → revoke ALL user sessions + write `token_reuse_detected` audit event |
| Brute force — IP | 10 attempts per IP per 15-min window → HTTP 429 with Retry-After |
| Brute force — account | 10 consecutive failures → `locked_at` set + `account_locked` audit event |
| Transport | TLS 1.3 minimum. HTTP rejected — no redirect. |
| Web refresh cookie | HttpOnly, Secure, SameSite=Strict, Path=/api/haven/refresh, Max-Age=2592000 |
| iOS storage | `FlutterSecureStorage` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| Android storage | `FlutterSecureStorage` with `EncryptedSharedPreferences` + Android Keystore |
| Login error rule | NEVER distinguish "email not found" from "wrong password" — both return `INVALID_CREDENTIALS` |

---

## Audit Event Reference

| Event | Trigger | Key Metadata |
|-------|---------|-------------|
| `login_success` | Successful login | `device_id`, `device_name` |
| `login_failed` | Wrong credentials | `email_attempted`, `reason` |
| `logout` | User logout | `device_id` |
| `logout_all` | All sessions revoked | `sessions_revoked` |
| `token_refreshed` | Rotation | `device_id` |
| `token_reuse_detected` | Consumed token reused | `device_id`, `all_sessions_revoked: true` |
| `device_registered` | New device | `device_id`, `platform` |
| `device_revoked` | Force revoked | `device_id`, `revoked_by` |
| `password_changed` | Password update | `sessions_invalidated: true` |
| `account_locked` | Brute force | `failed_attempts` |
| `account_unlocked` | Manual unlock | `unlocked_by` |
| `profile_updated` | Name/email change | `fields_changed` |
| `authz_denied` | Permission check failed | `action`, `resource_type`, `resource_id` |

---

## Haven API Surface (Called by Luma)

```
# Auth
POST /api/haven/auth/register
POST /api/haven/auth/login
POST /api/haven/auth/refresh
POST /api/haven/auth/logout
POST /api/haven/auth/logout-all

# Token validation — called by Luma on every authenticated request
GET  /api/haven/validate
     Authorization: Bearer <access_token>
     Response: { user_id, role, device_id, instance_role } or 401

# Permission check — called by Luma before any protected action
POST /api/haven/authz/check
     Body: { user_id, action, resource_type, resource_id, vault_id }
     Response: { allowed: true } or { allowed: false, reason }

# Users
GET  /api/haven/users/{id}
PUT  /api/haven/users/me/profile
POST /api/haven/users/me/password
GET  /api/haven/users/me/preferences
PATCH /api/haven/users/me/preferences

# Devices
GET  /api/haven/devices
DELETE /api/haven/devices/{id}

# Audit
GET  /api/haven/audit/me
GET  /api/haven/audit              # owner only

# Invitations — UI only, no CLI path
POST /api/haven/invitations
GET  /api/haven/invitations
DELETE /api/haven/invitations/{id}
GET  /api/haven/join?token=...     # invitee registration page

# Admin
DELETE /api/haven/admin/users/{id}/lock
DELETE /api/haven/admin/users/{id}/sessions
```

---

## Invitation System

**Delivery:** QR code + copyable link simultaneously. Both encode the same URL: `https://haven.local/join?token=<token>`.

**Token:** 32 random bytes, stored as SHA-256 hash. Lookup token — not a JWT. Revocable instantly.

**Lifecycle:** `pending` → `accepted` | `expired` | `revoked`

**Invitee experience:** Pre-populated registration form showing instance name, inviter note, and pre-assigned Vault memberships. Name + password fields only. Email optional. Account creation, Vault membership, and Personal Vault creation in one atomic transaction.

**Error display:** Invalid, expired, and revoked tokens all show the same message — do not reveal revocation status.

---

## Definition of Done — Haven v1.0

1. Both household users register and log in from web browser
2. Both users log in from iOS (Keychain) and Android (EncryptedSharedPreferences)
3. Device list accurate after multi-platform login
4. Remote device revocation propagates within 15 minutes (one access token lifetime)
5. Token reuse detection triggers full session revocation
6. Brute force lockout verified manually
7. Audit log accurate and INSERT-only verified at DB level
8. Luma successfully calls `/api/haven/validate` and `/api/haven/authz/check`
9. Both users in daily use for 7 consecutive days before Luma feature development begins
