package mfa

import (
	"context"
	"time"
)

// Repository is the persistence interface for MFA data (TOTP, challenges, passkeys).
type Repository interface {
	// ── TOTP ────────────────────────────────────────────────────────────

	// CreateTOTPSecret inserts a new TOTP secret and returns its UUID.
	CreateTOTPSecret(ctx context.Context, userID, name string, secret []byte) (string, error)

	// GetTOTPSecretByID returns a single TOTP secret by UUID.
	GetTOTPSecretByID(ctx context.Context, id string) (*TOTPSecret, error)

	// ListTOTPSecrets returns all TOTP secrets for a user (verified and pending).
	ListTOTPSecrets(ctx context.Context, userID string) ([]*TOTPSecret, error)

	// ListVerifiedTOTPSecrets returns only verified TOTP secrets for a user.
	ListVerifiedTOTPSecrets(ctx context.Context, userID string) ([]*TOTPSecret, error)

	// VerifyTOTPSecret marks a single TOTP secret as verified by ID.
	VerifyTOTPSecret(ctx context.Context, id string) error

	// DeleteTOTPSecret removes a single TOTP secret by ID.
	DeleteTOTPSecret(ctx context.Context, id string) error

	// DeleteUnverifiedTOTPSecrets removes all unverified TOTP secrets for a user.
	DeleteUnverifiedTOTPSecrets(ctx context.Context, userID string) error

	// CountVerifiedTOTPSecrets returns how many verified TOTP secrets a user has.
	CountVerifiedTOTPSecrets(ctx context.Context, userID string) (int, error)

	// UpdateTOTPLastUsedCounter sets the last accepted time-step counter (replay guard).
	UpdateTOTPLastUsedCounter(ctx context.Context, id string, counter int64) error

	// ── MFA Challenges ──────────────────────────────────────────────────

	// CreateChallenge inserts a new MFA challenge.
	CreateChallenge(ctx context.Context, userID, deviceID, tokenHash string, expiresAt time.Time) error

	// GetChallengeByHash looks up an MFA challenge by token hash.
	GetChallengeByHash(ctx context.Context, tokenHash string) (*MFAChallenge, error)

	// ConsumeChallenge marks a challenge as consumed.
	ConsumeChallenge(ctx context.Context, id string) error

	// ── Passkeys ────────────────────────────────────────────────────────

	// CreatePasskey inserts a new passkey credential.
	CreatePasskey(ctx context.Context, p *Passkey) error

	// GetPasskeyByCredentialID looks up a passkey by its WebAuthn credential ID.
	GetPasskeyByCredentialID(ctx context.Context, credentialID []byte) (*Passkey, error)

	// ListPasskeysForUser returns all non-revoked passkeys for a user.
	ListPasskeysForUser(ctx context.Context, userID string) ([]*Passkey, error)

	// UpdatePasskeySignCount bumps the sign count and last_used_at timestamp.
	UpdatePasskeySignCount(ctx context.Context, id string, signCount int64) error

	// RevokePasskey sets revoked_at on a passkey.
	RevokePasskey(ctx context.Context, id string) error

	// GetPasskeyByID returns a passkey by its UUID.
	GetPasskeyByID(ctx context.Context, id string) (*Passkey, error)

	// CountActivePasskeys returns the number of non-revoked passkeys for a user.
	CountActivePasskeys(ctx context.Context, userID string) (int, error)

	// ── Recovery Codes ──────────────────────────────────────────────────────────

	// ReplaceRecoveryCodes deletes any existing unused codes for the user and
	// inserts a new batch of hashed codes.
	ReplaceRecoveryCodes(ctx context.Context, userID string, codeHashes []string) error

	// GetRecoveryCodeByHash looks up an unused recovery code by its hash.
	GetRecoveryCodeByHash(ctx context.Context, userID, codeHash string) (*RecoveryCode, error)

	// ConsumeRecoveryCode marks a recovery code as used.
	ConsumeRecoveryCode(ctx context.Context, id string) error

	// CountUnusedRecoveryCodes returns the number of unused recovery codes for a user.
	CountUnusedRecoveryCodes(ctx context.Context, userID string) (int, error)
}
