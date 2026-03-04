# MFA Design — Multi-Factor Authentication

## Overview

Luma-auth supports two MFA methods:

1. **TOTP** — time-based one-time passwords (authenticator apps: Authy, Google Authenticator, 1Password)
2. **Passkeys** — WebAuthn/FIDO2 credentials (Touch ID, Windows Hello, phone passkey, security keys)

TOTP adds a second factor after password verification. Passkeys replace the password entirely — a passkey login is inherently two-factor (possession + biometric/PIN) and skips TOTP.

## Schema

All tables live in the `auth` schema alongside existing tables.

### `auth.totp_secrets`

One active secret per user. The secret is a 20-byte raw value encrypted at rest by PostgreSQL column-level encryption or application-layer envelope encryption.

| Column     | Type        | Constraints                                       |
|------------|-------------|---------------------------------------------------|
| user_id    | UUID        | PK, FK → auth.users(id) ON DELETE CASCADE         |
| secret     | BYTEA       | NOT NULL — 20-byte raw TOTP secret                |
| verified   | BOOLEAN     | NOT NULL DEFAULT false                            |
| created_at | TIMESTAMPTZ | NOT NULL DEFAULT NOW()                            |

### `auth.mfa_challenges`

Short-lived tokens proving "password OK, awaiting second factor." Created during login when `user.mfa_enabled = true`. Consumed on successful MFA verification.

| Column      | Type        | Constraints                                       |
|-------------|-------------|---------------------------------------------------|
| id          | UUID        | PK DEFAULT gen_random_uuid()                      |
| user_id     | UUID        | NOT NULL, FK → auth.users(id) ON DELETE CASCADE   |
| device_id   | UUID        | NOT NULL, FK → auth.devices(id) ON DELETE CASCADE |
| token_hash  | TEXT        | NOT NULL UNIQUE — SHA-256 of the raw token        |
| expires_at  | TIMESTAMPTZ | NOT NULL — 5 minutes from creation                |
| consumed_at | TIMESTAMPTZ | NULL until used                                   |
| created_at  | TIMESTAMPTZ | NOT NULL DEFAULT NOW()                            |

### `auth.passkeys`

WebAuthn credentials. Multiple passkeys per user. Soft-revoke via `revoked_at`.

| Column        | Type        | Constraints                                       |
|---------------|-------------|---------------------------------------------------|
| id            | UUID        | PK DEFAULT gen_random_uuid()                      |
| user_id       | UUID        | NOT NULL, FK → auth.users(id) ON DELETE CASCADE   |
| credential_id | BYTEA       | NOT NULL UNIQUE — raw credential ID from WebAuthn |
| public_key    | BYTEA       | NOT NULL — CBOR-encoded public key                |
| sign_count    | BIGINT      | NOT NULL DEFAULT 0                                |
| name          | TEXT        | NOT NULL — user-chosen label                      |
| aaguid        | BYTEA       | authenticator identifier (nullable)               |
| transports    | TEXT[]      | usb, nfc, ble, internal                           |
| last_used_at  | TIMESTAMPTZ | NULL until first use                              |
| revoked_at    | TIMESTAMPTZ | NULL unless revoked                               |
| created_at    | TIMESTAMPTZ | NOT NULL DEFAULT NOW()                            |

### `auth.users` — new column

```sql
ALTER TABLE auth.users ADD COLUMN mfa_enabled BOOLEAN NOT NULL DEFAULT false;
```

Single source of truth for "does login require a second factor." Set `true` when TOTP is verified or first passkey registered. Set `false` when all MFA methods are removed.

## API Surface

### TOTP Management (Bearer required)

| Method | Path                        | Description                                      |
|--------|-----------------------------|--------------------------------------------------|
| POST   | /api/auth/mfa/totp/setup    | Generate secret, return otpauth_uri + QR base64  |
| POST   | /api/auth/mfa/totp/confirm  | Verify code, activate TOTP, set mfa_enabled=true |
| DELETE | /api/auth/mfa/totp          | Require password, delete secret, maybe clear flag |

### MFA Challenge (unauthenticated, rate-limited)

| Method | Path                        | Description                                      |
|--------|-----------------------------|--------------------------------------------------|
| POST   | /api/auth/mfa/verify        | Verify TOTP code, consume challenge, issue tokens |

### Passkey Registration (Bearer required)

| Method | Path                                  | Description                                      |
|--------|---------------------------------------|--------------------------------------------------|
| POST   | /api/auth/passkeys/register/begin     | Return PublicKeyCredentialCreationOptions         |
| POST   | /api/auth/passkeys/register/finish    | Validate attestation, store credential            |

### Passkey Login (unauthenticated, rate-limited)

| Method | Path                                  | Description                                      |
|--------|---------------------------------------|--------------------------------------------------|
| POST   | /api/auth/passkeys/login/begin        | Return PublicKeyCredentialRequestOptions          |
| POST   | /api/auth/passkeys/login/finish       | Verify assertion, issue tokens (skips TOTP)       |

### Passkey Management (Bearer required)

| Method | Path                        | Description                                      |
|--------|-----------------------------|--------------------------------------------------|
| GET    | /api/auth/passkeys          | List user's passkeys                             |
| DELETE | /api/auth/passkeys/{id}     | Revoke passkey, maybe clear mfa_enabled           |

## Login Flow Changes

### Current flow

```
Password OK → issue token pair immediately
```

### New flow

```
Password OK + mfa_enabled=false → issue token pair (unchanged)
Password OK + mfa_enabled=true  → create MFA challenge (5-min expiry)
                                → return {mfa_required: true, mfa_token, methods}
Client POST /mfa/verify         → verify TOTP code → issue token pair + cookie
```

The `mfa_token` is a short-lived opaque token separate from access/refresh tokens. It proves "this user passed password verification" and is single-use.

### Passkey login flow

```
Client POST /passkeys/login/begin  → challenge + allowCredentials
Client invokes navigator.credentials.get()
Client POST /passkeys/login/finish → verify signature → issue token pair + cookie
```

Passkey login bypasses password and TOTP entirely — the credential is already two-factor.

## MFA Token Security

- Generated: 32 bytes from `crypto/rand`, base64url-encoded
- Stored: SHA-256 hash only (same pattern as refresh tokens)
- Expiry: 5 minutes from creation
- Single use: `consumed_at` set on verification
- Bound to user+device: challenge stores both IDs

## Audit Events

| Event                   | When                                    |
|-------------------------|-----------------------------------------|
| totp_enrolled           | TOTP setup confirmed (code verified)    |
| totp_removed            | TOTP disabled by user                   |
| mfa_challenge_success   | Second factor verified during login     |
| mfa_challenge_failed    | Wrong TOTP code during login            |
| passkey_registered      | New passkey credential stored           |
| passkey_login           | Successful passkey authentication       |
| passkey_revoked         | Passkey removed by user                 |

## Luma Proxy Routes

The luma proxy translates `/api/luma/` paths to `/api/auth/` calls to the auth service.

Cookie-issuing endpoints (login, mfa/verify, passkeys/login/finish) need dedicated handlers with `rewriteCookies()`. All other endpoints use `proxyAuth` or `proxySetup` patterns.

| Luma path                              | Auth service path                           | Handler type       |
|----------------------------------------|---------------------------------------------|--------------------|
| POST /api/luma/mfa/totp/setup          | POST /api/auth/mfa/totp/setup               | proxyAuth          |
| POST /api/luma/mfa/totp/confirm        | POST /api/auth/mfa/totp/confirm             | proxyAuth          |
| DELETE /api/luma/mfa/totp              | DELETE /api/auth/mfa/totp                   | proxyAuth          |
| POST /api/luma/auth/mfa/verify         | POST /api/auth/mfa/verify                   | dedicated (cookie) |
| POST /api/luma/passkeys/register/begin | POST /api/auth/passkeys/register/begin      | proxyAuth          |
| POST /api/luma/passkeys/register/finish| POST /api/auth/passkeys/register/finish     | proxyAuth          |
| GET /api/luma/passkeys                 | GET /api/auth/passkeys                      | proxyAuth          |
| DELETE /api/luma/passkeys/{id}         | DELETE /api/auth/passkeys/{id}              | proxyAuth          |
| POST /api/luma/passkeys/login/begin    | POST /api/auth/passkeys/login/begin         | proxySetup (no auth)|
| POST /api/luma/passkeys/login/finish   | POST /api/auth/passkeys/login/finish        | dedicated (cookie) |

## Flutter Integration

### Login screen

- Existing password form unchanged
- Add "Sign in with passkey" button below form
- On `mfa_required` response: store mfa_token, navigate to /mfa

### MFA verification screen (/mfa)

- 6-digit code input with auto-submit on 6 characters
- Error display for wrong codes
- "Use a different method" link (future: passkey fallback)

### Settings — Two-factor authentication section

- Not enrolled: "Set up authenticator app" button → QR code dialog → verify code → done
- Enrolled: "Authenticator app enabled" with "Remove" button (requires password confirmation)

### Settings — Passkeys section

- List registered passkeys with name + created date
- "Add passkey" button → navigator.credentials.create() → name dialog → done
- Delete button on each passkey (with confirmation)

## Security Invariants

1. The `mfa_token` never grants access — it only proves password verification
2. MFA challenges expire after 5 minutes and are single-use
3. Passkey login skips TOTP — the credential is inherently two-factor
4. TOTP secrets are stored encrypted; raw secrets are only returned during setup
5. Removing the last MFA method sets `mfa_enabled = false`
6. Failed MFA attempts are audit-logged for abuse detection
7. All MFA and passkey endpoints that issue tokens are rate-limited

## Dependencies

| Library                            | Purpose              |
|------------------------------------|----------------------|
| github.com/pquerna/otp v1.4.0     | TOTP generation/verify|
| github.com/go-webauthn/webauthn   | WebAuthn ceremonies  |

## WebAuthn Configuration

Derived from the auth service's `AUTH_BASE_URL`:
- **RPID**: hostname from `AUTH_BASE_URL` (e.g. `luma.local`)
- **RPOrigins**: the full `AUTH_BASE_URL` origin (e.g. `https://luma.local`)
- **RPDisplayName**: instance name from `auth.instance` table, or "Luma" as fallback

WebAuthn session data (between begin/finish calls) is stored in Redis with a 5-minute TTL, keyed by the challenge value.
