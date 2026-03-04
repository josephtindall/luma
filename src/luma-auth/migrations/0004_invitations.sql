-- Migration 0004: invitations
-- Token-based invite links. The raw token is never stored — only the SHA-256 hash.
-- Invalid, expired, and revoked tokens show the same error to invitees.

CREATE TABLE auth.invitations
(
    id          UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    inviter_id  UUID        NOT NULL REFERENCES auth.users (id),
    email       TEXT,                        -- optional; blank for QR-only invites
    note        TEXT,
    token_hash  TEXT        NOT NULL UNIQUE, -- SHA-256(raw_token), hex
    status      TEXT        NOT NULL DEFAULT 'pending',
    expires_at  TIMESTAMPTZ NOT NULL,
    accepted_at TIMESTAMPTZ,
    revoked_at  TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT invitation_status_values
        CHECK (status IN ('pending', 'accepted', 'expired', 'revoked'))
);

CREATE INDEX idx_invitations_inviter ON auth.invitations (inviter_id);
CREATE INDEX idx_invitations_status ON auth.invitations (status) WHERE status = 'pending';
