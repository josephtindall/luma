package recoverytoken

import (
	"context"
	"time"
)

// Token is the stored recovery token record.
type Token struct {
	UserID    string
	TokenHash string // SHA-256 hex of the raw 64-digit code
	CreatedAt time.Time
	UpdatedAt time.Time
}

// Repository is the data access interface for recovery tokens.
type Repository interface {
	// Upsert creates or replaces a user's recovery token.
	Upsert(ctx context.Context, userID, tokenHash string) error
	// GetByUserID loads the stored token record for a user, or nil if none.
	GetByUserID(ctx context.Context, userID string) (*Token, error)
	// DeleteByUserID removes the token (after successful use).
	DeleteByUserID(ctx context.Context, userID string) error
}
