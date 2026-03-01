package audit

import "context"

// Repository is the persistence interface for audit events.
// INSERT only — reads are for the audit log endpoints.
type Repository interface {
	// Insert writes one audit event. Never blocks the caller beyond a DB write.
	Insert(ctx context.Context, e Event) error

	// ListForUser returns the paginated audit history for a user.
	ListForUser(ctx context.Context, userID string, limit, offset int) ([]*Row, error)

	// ListAll returns the paginated global audit log — owner only.
	ListAll(ctx context.Context, limit, offset int) ([]*Row, error)
}
