package invitation

import (
	"context"
	"fmt"
	"time"

	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/token"
)

const invitationLifetime = 7 * 24 * time.Hour // 7 days

// Service handles invitation creation, validation, and revocation.
type Service struct {
	repo Repository
}

// NewService constructs the invitation service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// Create generates a new invitation, stores the hash, and returns the raw token.
// The raw token is embedded in the join URL — it is never stored.
func (s *Service) Create(ctx context.Context, params CreateParams) (rawToken string, inv *Invitation, err error) {
	raw, hash, err := token.GenerateRefreshToken() // 32 random bytes, same mechanism
	if err != nil {
		return "", nil, fmt.Errorf("invitation.Service.Create generate: %w", err)
	}

	inv = &Invitation{
		InviterID: params.InviterID,
		Email:     params.Email,
		Note:      params.Note,
		TokenHash: hash,
		Status:    StatusPending,
		ExpiresAt: time.Now().UTC().Add(invitationLifetime),
	}
	if err := s.repo.Create(ctx, inv); err != nil {
		return "", nil, fmt.Errorf("invitation.Service.Create store: %w", err)
	}
	return raw, inv, nil
}

// Validate looks up and validates an invitation by raw token.
// Invalid, expired, and revoked tokens all return the same error — do not
// distinguish revocation status to the invitee.
func (s *Service) Validate(ctx context.Context, rawToken string) (*Invitation, error) {
	hash := token.HashRefreshToken(rawToken)
	inv, err := s.repo.GetByHash(ctx, hash)
	if err != nil {
		return nil, pkgerrors.ErrTokenInvalid
	}
	if !inv.IsValid() {
		return nil, pkgerrors.ErrTokenInvalid
	}
	return inv, nil
}

// List returns all pending invitations.
func (s *Service) List(ctx context.Context) ([]*Invitation, error) {
	invs, err := s.repo.List(ctx)
	if err != nil {
		return nil, fmt.Errorf("invitation.Service.List: %w", err)
	}
	return invs, nil
}

// Revoke cancels an invitation by ID.
func (s *Service) Revoke(ctx context.Context, id string) error {
	if err := s.repo.Revoke(ctx, id); err != nil {
		return fmt.Errorf("invitation.Service.Revoke: %w", err)
	}
	return nil
}
