package audit

import "context"

// Repository is the persistence interface for audit events.
// INSERT only — reads are for the audit log endpoints.
type Repository interface {
	// Insert writes one audit event. Never blocks the caller beyond a DB write.
	Insert(ctx context.Context, e Event) error

	// ListForUser returns the filtered, paginated audit history for a single user.
	ListForUser(ctx context.Context, userID string, q AuditQuery) (*Page, error)

	// ListAll returns the filtered, paginated global audit log.
	// Row.UserEmail and Row.UserDisplayName are populated via JOIN.
	ListAll(ctx context.Context, q AuditQuery) (*Page, error)
}
