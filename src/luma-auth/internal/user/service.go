package user

import (
	"context"
	"fmt"
	"strings"
	"unicode"

	"github.com/google/uuid"

	"github.com/josephtindall/luma-auth/internal/audit"
	"github.com/josephtindall/luma-auth/pkg/crypto"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

const (
	maxFailedLogins = 10
)

// SessionTerminatorService is a narrow interface satisfied by session.Service.
// Used by user.Service to revoke sessions when force_password_change is set.
type SessionTerminatorService interface {
	LogoutAll(ctx context.Context, userID string) error
}

// Service contains all business logic for user management.
// It depends on the Repository interface — never on a concrete type.
type Service struct {
	repo     Repository
	audit    audit.Service
	sessions SessionTerminatorService // optional — nil in tests that don't need session revocation
	policy   PasswordPolicyProvider   // optional — falls back to hardcoded defaults when nil
}

// NewService constructs a Service with the given repository and audit service.
func NewService(repo Repository, auditSvc audit.Service) *Service {
	return &Service{repo: repo, audit: auditSvc}
}

// SetSessions wires the session terminator after construction (avoids import cycle
// since session.Service already imports user.Repository).
func (s *Service) SetSessions(sessions SessionTerminatorService) {
	s.sessions = sessions
}

// SetPolicy wires the password policy provider after construction (avoids import
// cycle since bootstrap imports user).
func (s *Service) SetPolicy(p PasswordPolicyProvider) {
	s.policy = p
}

// getPolicy returns the current password policy, falling back to safe defaults.
func (s *Service) getPolicy(ctx context.Context) *PasswordPolicy {
	if s.policy != nil {
		p, err := s.policy.GetPasswordPolicy(ctx)
		if err == nil && p != nil {
			return p
		}
	}
	return &PasswordPolicy{MinLength: 8}
}

// validateNewPassword checks the plaintext password against the current policy.
func (s *Service) validateNewPassword(ctx context.Context, plaintext string) error {
	p := s.getPolicy(ctx)
	if len(plaintext) < p.MinLength {
		return pkgerrors.ErrPasswordTooShort
	}
	if p.RequireUppercase || p.RequireLowercase || p.RequireNumbers || p.RequireSymbols {
		var hasUpper, hasLower, hasDigit, hasSymbol bool
		for _, r := range plaintext {
			switch {
			case unicode.IsUpper(r):
				hasUpper = true
			case unicode.IsLower(r):
				hasLower = true
			case unicode.IsDigit(r):
				hasDigit = true
			case unicode.IsPunct(r) || unicode.IsSymbol(r):
				hasSymbol = true
			}
		}
		if p.RequireUppercase && !hasUpper {
			return fmt.Errorf("password must contain at least one uppercase letter: %w", pkgerrors.ErrPasswordTooShort)
		}
		if p.RequireLowercase && !hasLower {
			return fmt.Errorf("password must contain at least one lowercase letter: %w", pkgerrors.ErrPasswordTooShort)
		}
		if p.RequireNumbers && !hasDigit {
			return fmt.Errorf("password must contain at least one number: %w", pkgerrors.ErrPasswordTooShort)
		}
		if p.RequireSymbols && !hasSymbol {
			return fmt.Errorf("password must contain at least one symbol: %w", pkgerrors.ErrPasswordTooShort)
		}
	}
	return nil
}

// checkPasswordNotReused verifies the plaintext does not match any of the user's
// recent stored hashes. Returns ErrPasswordReused if a match is found.
func (s *Service) checkPasswordNotReused(ctx context.Context, userID, plaintext string) error {
	p := s.getPolicy(ctx)
	if p.HistoryCount <= 0 {
		return nil
	}
	hashes, err := s.repo.GetRecentPasswordHashes(ctx, userID, p.HistoryCount)
	if err != nil {
		return fmt.Errorf("user.Service.checkPasswordNotReused: %w", err)
	}
	for _, h := range hashes {
		ok, err := crypto.VerifyPassword(plaintext, h)
		if err != nil {
			continue // treat corrupt hash as non-match
		}
		if ok {
			return pkgerrors.ErrPasswordReused
		}
	}
	return nil
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
	if err := s.validateNewPassword(ctx, params.NewPassword); err != nil {
		return err
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

	if err := s.checkPasswordNotReused(ctx, id, params.NewPassword); err != nil {
		return err
	}

	hash, err := crypto.HashPassword(params.NewPassword)
	if err != nil {
		return fmt.Errorf("user.Service.ChangePassword hash: %w", err)
	}

	if err := s.repo.UpdatePassword(ctx, id, hash); err != nil {
		return fmt.Errorf("user.Service.ChangePassword update: %w", err)
	}
	_ = s.repo.AddPasswordHistory(ctx, id, hash)

	s.audit.WriteAsync(ctx, audit.Event{
		UserID: id,
		Event:  audit.EventPasswordChanged,
		Metadata: map[string]any{
			"sessions_invalidated": false,
		},
	})
	return nil
}

// SetPasswordDirect updates a user's password hash without verifying the old
// password. Used by the password-reset flow after a valid reset token is consumed.
func (s *Service) SetPasswordDirect(ctx context.Context, id, newPassword string) error {
	if err := s.validateNewPassword(ctx, newPassword); err != nil {
		return err
	}
	if err := s.checkPasswordNotReused(ctx, id, newPassword); err != nil {
		return err
	}
	hash, err := crypto.HashPassword(newPassword)
	if err != nil {
		return fmt.Errorf("user.Service.SetPasswordDirect hash: %w", err)
	}
	if err := s.repo.UpdatePassword(ctx, id, hash); err != nil {
		return fmt.Errorf("user.Service.SetPasswordDirect update: %w", err)
	}
	_ = s.repo.AddPasswordHistory(ctx, id, hash)
	s.audit.WriteAsync(ctx, audit.Event{
		UserID: id,
		Event:  audit.EventPasswordChanged,
		Metadata: map[string]any{
			"via": "password_reset",
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

// ListUsers returns all users as admin-safe projections with MFA counts,
// ordered by creation date descending. Admin-only operation.
func (s *Service) ListUsers(ctx context.Context, limit, offset int) ([]*AdminUser, error) {
	users, err := s.repo.ListWithCounts(ctx, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("user.Service.ListUsers: %w", err)
	}
	return users, nil
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

// AdminCreate creates a new user directly (no invitation required).
// Owner-only operation. Returns the AdminUser projection on success.
func (s *Service) AdminCreate(ctx context.Context, params AdminCreateParams, requesterID string) (*AdminUser, error) {
	params.Email = strings.ToLower(strings.TrimSpace(params.Email))
	if params.Email == "" {
		return nil, pkgerrors.ErrEmailTaken // reuse closest sentinel
	}
	if err := s.validateNewPassword(ctx, params.Password); err != nil {
		return nil, err
	}

	hash, err := crypto.HashPassword(params.Password)
	if err != nil {
		return nil, fmt.Errorf("user.Service.AdminCreate hash: %w", err)
	}

	u := &User{
		ID:                  uuid.New().String(),
		Email:               params.Email,
		DisplayName:         strings.TrimSpace(params.DisplayName),
		PasswordHash:        hash,
		InstanceRoleID:      "builtin:instance-member",
		ForcePasswordChange: params.ForcePasswordChange,
	}

	if err := s.repo.Create(ctx, u); err != nil {
		return nil, fmt.Errorf("user.Service.AdminCreate create: %w", err)
	}
	_ = s.repo.AddPasswordHistory(ctx, u.ID, hash)

	s.audit.WriteAsync(ctx, audit.Event{
		UserID: u.ID,
		Event:  audit.EventAdminUserCreated,
		Metadata: map[string]any{
			"created_by": requesterID,
			"email":      u.Email,
		},
	})

	return u.ToAdmin(), nil
}

// SetForcePasswordChange sets or clears the force_password_change flag for a user.
// When setting (force=true), all existing sessions are revoked immediately.
func (s *Service) SetForcePasswordChange(ctx context.Context, targetID, requesterID string, force bool) error {
	if err := s.repo.SetForcePasswordChange(ctx, targetID, force); err != nil {
		return fmt.Errorf("user.Service.SetForcePasswordChange: %w", err)
	}
	if force && s.sessions != nil {
		_ = s.sessions.LogoutAll(ctx, targetID)
	}
	s.audit.WriteAsync(ctx, audit.Event{
		UserID: targetID,
		Event:  audit.EventAdminForcePasswordChange,
		Metadata: map[string]any{
			"set_to":       force,
			"requested_by": requesterID,
		},
	})
	return nil
}
