package user

import (
	"context"
	"fmt"
	"strings"

	"github.com/josephtindall/luma-auth/internal/audit"
	"github.com/josephtindall/luma-auth/pkg/crypto"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

const (
	minPasswordLen  = 8
	maxFailedLogins = 10
)

// Service contains all business logic for user management.
// It depends on the Repository interface — never on a concrete type.
type Service struct {
	repo  Repository
	audit audit.Service
}

// NewService constructs a Service with the given repository and audit service.
func NewService(repo Repository, auditSvc audit.Service) *Service {
	return &Service{repo: repo, audit: auditSvc}
}

// GetByID returns the public projection of a user.
func (s *Service) GetByID(ctx context.Context, id string) (*PublicUser, error) {
	u, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("user.Service.GetByID: %w", err)
	}
	return u.ToPublic(), nil
}

// UpdateProfile applies validated profile changes.
func (s *Service) UpdateProfile(ctx context.Context, id string, params UpdateProfileParams) error {
	var changed []string
	if params.DisplayName != "" {
		params.DisplayName = strings.TrimSpace(params.DisplayName)
		changed = append(changed, "display_name")
	}
	if params.Email != "" {
		params.Email = strings.ToLower(strings.TrimSpace(params.Email))
		changed = append(changed, "email")
	}
	if err := s.repo.UpdateProfile(ctx, id, params); err != nil {
		return fmt.Errorf("user.Service.UpdateProfile: %w", err)
	}
	s.audit.WriteAsync(ctx, audit.Event{
		UserID: id,
		Event:  audit.EventProfileUpdated,
		Metadata: map[string]any{
			"fields_changed": changed,
		},
	})
	return nil
}

// ChangePassword validates the current password, hashes the new one, and
// updates the record. On success, all existing sessions should be revoked by
// the caller (session.Service.RevokeAllForUser).
func (s *Service) ChangePassword(ctx context.Context, id string, params ChangePasswordParams) error {
	if len(params.NewPassword) < minPasswordLen {
		return pkgerrors.ErrPasswordTooShort
	}

	u, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return fmt.Errorf("user.Service.ChangePassword get: %w", err)
	}

	ok, err := crypto.VerifyPassword(params.CurrentPassword, u.PasswordHash)
	if err != nil {
		return fmt.Errorf("user.Service.ChangePassword verify: %w", err)
	}
	if !ok {
		return pkgerrors.ErrInvalidCredentials
	}

	hash, err := crypto.HashPassword(params.NewPassword)
	if err != nil {
		return fmt.Errorf("user.Service.ChangePassword hash: %w", err)
	}

	if err := s.repo.UpdatePassword(ctx, id, hash); err != nil {
		return fmt.Errorf("user.Service.ChangePassword update: %w", err)
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID: id,
		Event:  audit.EventPasswordChanged,
		Metadata: map[string]any{
			"sessions_invalidated": false,
		},
	})
	return nil
}

// RecordFailedLogin increments the counter and locks the account when the
// threshold is reached. IMPORTANT: this is a side effect of a failed login
// attempt — it must never reveal whether the email existed.
func (s *Service) RecordFailedLogin(ctx context.Context, id string) error {
	count, err := s.repo.IncrementFailedLogins(ctx, id)
	if err != nil {
		return fmt.Errorf("user.Service.RecordFailedLogin: %w", err)
	}
	if count >= maxFailedLogins {
		if err := s.repo.LockAccount(ctx, id, "brute force threshold reached"); err != nil {
			return fmt.Errorf("user.Service.RecordFailedLogin lock: %w", err)
		}
	}
	return nil
}

// LockAccount manually locks a user account — owner-only operation.
// requesterID identifies who performed the lock (for audit purposes).
func (s *Service) LockAccount(ctx context.Context, id, requesterID string) error {
	if err := s.repo.LockAccount(ctx, id, "admin_lock"); err != nil {
		return fmt.Errorf("user.Service.LockAccount: %w", err)
	}
	s.audit.WriteAsync(ctx, audit.Event{
		UserID: id,
		Event:  audit.EventAccountLocked,
		Metadata: map[string]any{
			"locked_by": requesterID,
			"reason":    "admin_lock",
		},
	})
	return nil
}

// UnlockAccount clears the lock on a user — owner-only operation.
// requesterID identifies who performed the unlock (for audit purposes).
func (s *Service) UnlockAccount(ctx context.Context, id, requesterID string) error {
	if err := s.repo.UnlockAccount(ctx, id); err != nil {
		return fmt.Errorf("user.Service.UnlockAccount: %w", err)
	}
	s.audit.WriteAsync(ctx, audit.Event{
		UserID: id,
		Event:  audit.EventAccountUnlocked,
		Metadata: map[string]any{
			"unlocked_by": requesterID,
		},
	})
	return nil
}
