package invitation

import "context"

// Repository is the persistence interface for invitations.
type Repository interface {
	// Create inserts a new invitation row.
	Create(ctx context.Context, inv *Invitation) error

	// GetByHash looks up an invitation by token hash.
	GetByHash(ctx context.Context, tokenHash string) (*Invitation, error)

	// GetByID returns an invitation by UUID.
	GetByID(ctx context.Context, id string) (*Invitation, error)

	// List returns all non-revoked invitations (for the owner's admin view).
	List(ctx context.Context) ([]*Invitation, error)

	// Accept transitions an invitation from pending to accepted.
	Accept(ctx context.Context, id string) error

	// Revoke transitions an invitation to revoked.
	Revoke(ctx context.Context, id string) error
}
