package preferences

import "context"

// Repository is the persistence interface for user preferences.
type Repository interface {
	// Get returns preferences for a user. Always returns a row — created with
	// defaults in the same transaction as the user row.
	Get(ctx context.Context, userID string) (*Preferences, error)

	// Update applies a partial update to the preferences row.
	Update(ctx context.Context, userID string, params UpdateParams) error
}
