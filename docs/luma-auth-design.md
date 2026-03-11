# luma-auth — Identity & Access Management

## What luma-auth Is

luma-auth is a standalone IAM sidecar service distributed as a Docker image. Any project that needs authentication adds one block to its `docker-compose.yml` and gets full identity management: registration, login, sessions, device tracking, RBAC enforcement, and a complete audit log.

luma-auth is not a library compiled into the consumer app. It is a running service that the consumer app calls over HTTP. Updating luma-auth means changing the image tag and restarting the container — no recompilation of the consumer app required.

```yaml
# Every project that uses luma-auth adds this to docker-compose.yml
luma-auth:
  image: luma-auth:latest
  restart: unless-stopped
  environment:
    AUTH_DB_URL: postgres://auth_app:${AUTH_DB_PASS}@postgres:5432/luma-auth
    AUTH_JWT_SIGNING_KEY: ${AUTH_JWT_SIGNING_KEY}
    AUTH_PUBLIC_URL: https://auth.yourapp.local
  networks:
    - internal
```

## Runtime Relationship with Luma

Luma calls luma-auth's API for three things:
1. **Token validation** — every authenticated Luma request calls `GET /api/auth/validate` with the Bearer token
2. **Permission checks** — Luma calls `POST /api/auth/authz/check` before any protected action
3. **User context** — Luma calls `GET /api/auth/users/{id}` to resolve user display info

luma-auth never calls Luma. The dependency is one-directional.

```
Browser/App
    │
    ▼
Luma API ──[POST /api/auth/authz/check]──► luma-auth API
    │                                           │
    ▼                                           ▼
Luma DB                                    luma-auth DB
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

No transition exists from ACTIVE. Factory reset requires: `luma-auth-cli factory-reset --confirm-destroy-all-data`

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
AUTH_INSTANCE_NAME="My Home"
AUTH_OWNER_EMAIL="admin@home.local"
AUTH_OWNER_NAME="Administrator"
AUTH_OWNER_PASSWORD="..."           # min 12 chars — use a secrets manager
AUTH_INSTANCE_TIMEZONE="America/New_York"
AUTH_INSTANCE_LOCALE="en-US"

# Secrets
AUTH_JWT_SIGNING_KEY="..."          # 64 bytes hex — fatal if missing
AUTH_DB_PASSWORD="..."
AUTH_CA_KEY_PASSPHRASE="..."

# Optional
AUTH_SHARED_VAULT_NAME="Team"       # creates one shared vault
AUTH_UNATTENDED=true

# Commands
luma-auth-cli setup --unattended         # full unattended install
luma-auth-cli generate-secrets > .env    # generate all secrets
luma-auth-cli validate-config            # verify before starting
luma-auth-cli healthcheck                # exits 0 if healthy
```

Idempotent — if already ACTIVE, exits 0 with no changes.

---

## Secret Zero

| Secret | Specification |
|--------|--------------|
| JWT Signing Key | 512-bit (64 bytes) random, hex encoded. Fatal startup error if missing or < 32 bytes. Never written to database — memory only. |
| Database Password | 256-bit random. Connection string only. |
| Internal CA Private Key | ECDSA P-384. Passphrase-protected. Stored at `/etc/luma-auth/ca/`. Issues TLS leaf certs. |
| Instance Master Key | Derived from JWT signing key via HKDF, label `"auth-master-key-v1"`. Root for Phase 2 encryption key derivation. Never stored — always re-derived. |

### JWT Signing Key Rotation (zero-downtime)
```bash
AUTH_JWT_SIGNING_KEY="<new key>"
AUTH_JWT_SIGNING_KEY_PREV="<old key>"  # validates tokens signed with old key
# After 15 min (one access token lifetime): remove _PREV on next restart
```

---

## Database Schema — `auth`

```sql
CREATE TABLE auth.instance (
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

CREATE TABLE auth.users (
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

CREATE TABLE auth.devices (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name         TEXT        NOT NULL,
    platform     TEXT        NOT NULL,  -- web | ios | android | agent
    fingerprint  TEXT        NOT NULL,
    user_agent   TEXT,
    last_seen_at TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT platform_values CHECK (platform IN ('web', 'ios', 'android', 'agent'))
);
CREATE INDEX idx_devices_user ON auth.devices(user_id);

-- Raw token NEVER stored — only SHA-256 hash
CREATE TABLE auth.refresh_tokens (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id   UUID        NOT NULL REFERENCES auth.devices(id) ON DELETE CASCADE,
    token_hash  TEXT        NOT NULL UNIQUE,
    expires_at  TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- IMMUTABLE: DB user has INSERT + SELECT only. No UPDATE, no DELETE ever.
CREATE TABLE auth.audit_log (
    id          BIGSERIAL   PRIMARY KEY,
    user_id     UUID        REFERENCES auth.users(id),
    device_id   UUID        REFERENCES auth.devices(id),
    event       TEXT        NOT NULL,
    ip_address  INET,
    user_agent  TEXT,
    metadata    JSONB,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audit_user      ON auth.audit_log(user_id);
CREATE INDEX idx_audit_occurred  ON auth.audit_log(occurred_at DESC);

GRANT SELECT, INSERT ON auth.audit_log TO auth_app;
REVOKE UPDATE, DELETE ON auth.audit_log FROM auth_app;

CREATE TABLE auth.user_preferences (
    user_id          UUID    PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
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
-- Created with defaults in same transaction as auth.users row — always exists
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
| Web refresh cookie | HttpOnly, Secure, SameSite=Strict, Path=/api/auth/refresh, Max-Age=2592000 |
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

## luma-auth API Surface (Called by Luma)

```
# Auth
POST /api/auth/register
POST /api/auth/login
POST /api/auth/refresh
POST /api/auth/logout
POST /api/auth/logout-all

# Token validation — called by Luma on every authenticated request
GET  /api/auth/validate
     Authorization: Bearer <access_token>
     Response: { user_id, role, device_id, instance_role } or 401

# Permission check — called by Luma before any protected action
POST /api/auth/authz/check
     Body: { user_id, action, resource_type, resource_id, vault_id }
     Response: { allowed: true } or { allowed: false, reason }

# Users
GET  /api/auth/users/{id}
PUT  /api/auth/users/me/profile
POST /api/auth/users/me/password
GET  /api/auth/users/me/preferences
PATCH /api/auth/users/me/preferences

# Devices
GET  /api/auth/devices
DELETE /api/auth/devices/{id}

# Audit
GET  /api/auth/audit/me
GET  /api/auth/audit              # owner only

# Invitations — UI only, no CLI path
POST /api/auth/invitations
GET  /api/auth/invitations
DELETE /api/auth/invitations/{id}
GET  /api/auth/join?token=...     # invitee registration page

# Admin
DELETE /api/auth/admin/users/{id}/lock
DELETE /api/auth/admin/users/{id}/sessions
```

---

## Invitation System

**Delivery:** QR code + copyable link simultaneously. Both encode the same URL: `https://luma-auth.local/join?token=<token>`.

**Token:** 32 random bytes, stored as SHA-256 hash. Lookup token — not a JWT. Revocable instantly.

**Lifecycle:** `pending` → `accepted` | `expired` | `revoked`

**Invitee experience:** Pre-populated registration form showing instance name, inviter note, and pre-assigned Vault memberships. Name + password fields only. Email optional. Account creation, Vault membership, and Personal Vault creation in one atomic transaction.

**Error display:** Invalid, expired, and revoked tokens all show the same message — do not reveal revocation status.

---

## Definition of Done — luma-auth v1.0

1. Both household users register and log in from web browser
2. Both users log in from iOS (Keychain) and Android (EncryptedSharedPreferences)
3. Device list accurate after multi-platform login
4. Remote device revocation propagates within 15 minutes (one access token lifetime)
5. Token reuse detection triggers full session revocation
6. Brute force lockout verified manually
7. Audit log accurate and INSERT-only verified at DB level
8. Luma successfully calls `/api/auth/validate` and `/api/auth/authz/check`
9. Both users in daily use for 7 consecutive days before Luma feature development begins
