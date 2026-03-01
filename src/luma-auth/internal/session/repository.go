package session

import "context"

// Repository is the persistence interface for refresh tokens.
type Repository interface {
	// Create inserts a new refresh token row.
	Create(ctx context.Context, t *RefreshToken) error

	// GetByHash looks up a refresh token by its SHA-256 hash.
	GetByHash(ctx context.Context, hash string) (*RefreshToken, error)

	// Consume marks a token as consumed (rotation step 1).
	// Returns ErrTokenInvalid if already consumed or revoked.
	Consume(ctx context.Context, id string) error

	// RevokeAllForUser hard-revokes every refresh token for a user.
	// Called on: password change, token reuse detection, logout-all.
	RevokeAllForUser(ctx context.Context, userID string) error

	// RevokeAllForDevice revokes all tokens issued to a specific device.
	RevokeAllForDevice(ctx context.Context, deviceID string) error
}
