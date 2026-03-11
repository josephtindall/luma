package passwordreset

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/josephtindall/luma-auth/internal/user"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

const (
	tokenSize        = 32 // bytes of raw entropy
	adminResetExpiry = 24 * time.Hour
	forceChangeExpiry = 15 * time.Minute
)

// UserPasswordSetter is a narrow interface satisfied by user.Service.
type UserPasswordSetter interface {
	SetPasswordDirect(ctx context.Context, id, newPassword string) error
	SetForcePasswordChange(ctx context.Context, targetID, requesterID string, force bool) error
}

// UserGetter is a narrow interface for fetching the user (to verify they exist).
type UserGetter interface {
	GetByID(ctx context.Context, id string) (*user.User, error)
}

// Service contains business logic for password reset tokens.
type Service struct {
	repo      Repository
	userRepo  user.Repository
	userSvc   UserPasswordSetter
}

// NewService constructs the password reset service.
func NewService(repo Repository, userRepo user.Repository, userSvc UserPasswordSetter) *Service {
	return &Service{repo: repo, userRepo: userRepo, userSvc: userSvc}
}

// CreateAdminResetToken generates a one-time admin-reset token for the given user.
// Returns the raw token to embed in the reset URL. Expires in 24 hours.
func (s *Service) CreateAdminResetToken(ctx context.Context, userID, requesterID string) (rawToken string, expiresAt time.Time, err error) {
	// Verify the target user exists.
	if _, err := s.userRepo.GetByID(ctx, userID); err != nil {
		return "", time.Time{}, fmt.Errorf("passwordreset.Service.CreateAdminResetToken: %w", err)
	}

	raw, hash, err := generateToken()
	if err != nil {
		return "", time.Time{}, fmt.Errorf("passwordreset.Service.CreateAdminResetToken generate: %w", err)
	}

	exp := time.Now().UTC().Add(adminResetExpiry)
	t := &Token{
		UserID:    userID,
		TokenHash: hash,
		Source:    "admin_reset",
		ExpiresAt: exp,
	}
	if err := s.repo.Create(ctx, t); err != nil {
		return "", time.Time{}, fmt.Errorf("passwordreset.Service.CreateAdminResetToken store: %w", err)
	}

	return raw, exp, nil
}

// CreateForceChangeToken generates a short-lived token for a user who has
// force_password_change=true and successfully entered their password.
// The returned token is presented to the user's browser and must be submitted
// along with the new password to POST /api/auth/reset-password.
func (s *Service) CreateForceChangeToken(ctx context.Context, userID string) (rawToken string, err error) {
	raw, hash, err := generateToken()
	if err != nil {
		return "", fmt.Errorf("passwordreset.Service.CreateForceChangeToken generate: %w", err)
	}

	t := &Token{
		UserID:    userID,
		TokenHash: hash,
		Source:    "force_change",
		ExpiresAt: time.Now().UTC().Add(forceChangeExpiry),
	}
	if err := s.repo.Create(ctx, t); err != nil {
		return "", fmt.Errorf("passwordreset.Service.CreateForceChangeToken store: %w", err)
	}

	return raw, nil
}

// ResetPassword validates the raw token, changes the user's password,
// and returns the userID so the caller can issue session tokens.
// If the token source is "force_change", the force_password_change flag
// is cleared after the password is set.
func (s *Service) ResetPassword(ctx context.Context, rawToken, newPassword string) (userID string, err error) {
	hash := hashToken(rawToken)

	t, err := s.repo.GetByHash(ctx, hash)
	if err != nil {
		return "", pkgerrors.ErrTokenInvalid
	}
	if !t.IsValid() {
		return "", pkgerrors.ErrTokenInvalid
	}

	// Consume the token first to prevent replay attacks.
	// If the password change subsequently fails, the user must request a new link.
	if err := s.repo.Consume(ctx, t.ID); err != nil {
		return "", fmt.Errorf("passwordreset.Service.ResetPassword consume: %w", err)
	}

	// Change the password (validates minimum length internally).
	if err := s.userSvc.SetPasswordDirect(ctx, t.UserID, newPassword); err != nil {
		return "", fmt.Errorf("passwordreset.Service.ResetPassword set password: %w", err)
	}

	// If this was a force-change token, clear the flag.
	if t.Source == "force_change" {
		_ = s.userSvc.SetForcePasswordChange(ctx, t.UserID, "", false)
	}

	return t.UserID, nil
}

func generateToken() (raw, hash string, err error) {
	b := make([]byte, tokenSize)
	if _, err = rand.Read(b); err != nil {
		return "", "", fmt.Errorf("passwordreset: generate token: %w", err)
	}
	raw = base64.RawURLEncoding.EncodeToString(b)
	hash = hashToken(raw)
	return raw, hash, nil
}

func hashToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
