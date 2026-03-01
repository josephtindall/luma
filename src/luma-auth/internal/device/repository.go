package device

import "context"

// Repository is the persistence interface for devices.
type Repository interface {
	// GetByID returns the device with the given UUID.
	GetByID(ctx context.Context, id string) (*Device, error)

	// GetByFingerprint looks up a device by user+fingerprint pair.
	// Returns nil, nil if not found (not an error — caller registers a new device).
	GetByFingerprint(ctx context.Context, userID, fingerprint string) (*Device, error)

	// ListForUser returns all non-revoked devices for a user, most recent first.
	ListForUser(ctx context.Context, userID string) ([]*Device, error)

	// Create inserts a new device row and returns the created record.
	Create(ctx context.Context, params RegisterParams) (*Device, error)

	// UpdateLastSeen bumps the last_seen_at timestamp.
	UpdateLastSeen(ctx context.Context, id string) error

	// Revoke sets revoked_at on the device, invalidating all its tokens.
	Revoke(ctx context.Context, id string) error
}
