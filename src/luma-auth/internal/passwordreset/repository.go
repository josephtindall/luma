package passwordreset

import "context"

// Repository is the persistence interface for password reset tokens.
type Repository interface {
	// Create inserts a new token record.
	Create(ctx context.Context, t *Token) error

	// GetByHash retrieves a token by its SHA-256 hash.
	GetByHash(ctx context.Context, tokenHash string) (*Token, error)

	// Consume marks a token as used (sets consumed_at = NOW()).
	Consume(ctx context.Context, id string) error
}
