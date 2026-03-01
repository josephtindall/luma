package session

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/josephtindall/luma-auth/internal/audit"
	"github.com/josephtindall/luma-auth/internal/device"
	"github.com/josephtindall/luma-auth/internal/invitation"
	"github.com/josephtindall/luma-auth/internal/user"
	"github.com/josephtindall/luma-auth/pkg/crypto"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/token"
)

// Issuer is the interface the bootstrap handler uses to issue the first token
// pair after owner creation. Defined here to avoid an import cycle.
type Issuer interface {
	IssueForUser(ctx context.Context, params IssueForUserParams) (*TokenPair, error)
}

// IssueForUserParams carries device info needed to register and issue tokens
// for a user who has just been created (e.g. owner after bootstrap).
type IssueForUserParams struct {
	UserID      string
	DeviceName  string
	Platform    string
	Fingerprint string
	UserAgent   string
	IPAddress   string
}

// SessionRegisterParams holds the validated inputs for an invitation-gated registration.
type SessionRegisterParams struct {
	InvitationID string
	Email        string
	DisplayName  string
	Password     string
	DeviceName   string
	Platform     string
	Fingerprint  string
	UserAgent    string
	IPAddress    string
}

// Service handles login, logout, and token refresh. It orchestrates the user,
// device, session, and audit packages — all wired in cmd/server/main.go.
type Service struct {
	users       user.Repository
	devices     device.Repository
	tokens      Repository
	audit       audit.Service
	invitations invitation.Repository
	jwtKey      []byte
}

// NewService constructs the session service.
func NewService(
	users user.Repository,
	devices device.Repository,
	tokens Repository,
	audit audit.Service,
	invitations invitation.Repository,
	jwtKey []byte,
) *Service {
	return &Service{
		users:       users,
		devices:     devices,
		tokens:      tokens,
		audit:       audit,
		invitations: invitations,
		jwtKey:      jwtKey,
	}
}

// Login authenticates a user and issues a token pair.
//
// Security invariants enforced here:
//   - Wrong password and unknown email both return ErrInvalidCredentials — no distinction.
//   - Locked accounts return ErrAccountLocked (but ONLY after the credential check,
//     so the error doesn't reveal that the account exists).
//   - Device is registered or matched by fingerprint.
func (s *Service) Login(ctx context.Context, params LoginParams) (*TokenPair, error) {
	// Always look up by email. If not found, return ErrInvalidCredentials — not ErrUserNotFound.
	u, err := s.users.GetByEmail(ctx, params.Email)
	if err != nil {
		s.audit.WriteAsync(ctx, audit.Event{
			Event:     audit.EventLoginFailed,
			IPAddress: params.IPAddress,
			Metadata:  map[string]any{"email_attempted": params.Email, "reason": "user_not_found"},
		})
		return nil, pkgerrors.ErrInvalidCredentials
	}

	// Verify password before checking lock status — avoids oracle on account existence.
	ok, err := crypto.VerifyPassword(params.Password, u.PasswordHash)
	if err != nil || !ok {
		_ = recordFailedLogin(ctx, s.users, s.audit, u, params.IPAddress)
		return nil, pkgerrors.ErrInvalidCredentials
	}

	if u.IsLocked() {
		return nil, pkgerrors.ErrAccountLocked
	}

	// Reset the failure counter on success.
	_ = s.users.ResetFailedLogins(ctx, u.ID)

	// Register or match the device.
	dev, err := s.devices.GetByFingerprint(ctx, u.ID, params.Fingerprint)
	if err != nil {
		return nil, fmt.Errorf("session.Service.Login device lookup: %w", err)
	}
	if dev == nil {
		dev, err = s.devices.Create(ctx, device.RegisterParams{
			UserID:      u.ID,
			Name:        params.DeviceName,
			Platform:    device.Platform(params.Platform),
			Fingerprint: params.Fingerprint,
			UserAgent:   params.UserAgent,
		})
		if err != nil {
			return nil, fmt.Errorf("session.Service.Login create device: %w", err)
		}
		s.audit.WriteAsync(ctx, audit.Event{
			UserID:   u.ID,
			DeviceID: dev.ID,
			Event:    audit.EventDeviceRegistered,
			Metadata: map[string]any{"platform": params.Platform},
		})
	} else if dev.IsRevoked() {
		return nil, pkgerrors.ErrDeviceRevoked
	}

	_ = s.devices.UpdateLastSeen(ctx, dev.ID)

	pair, err := s.issueTokenPair(ctx, u, dev)
	if err != nil {
		return nil, err
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID:    u.ID,
		DeviceID:  dev.ID,
		Event:     audit.EventLoginSuccess,
		IPAddress: params.IPAddress,
		UserAgent: params.UserAgent,
		Metadata:  map[string]any{"device_name": dev.Name},
	})

	return pair, nil
}

// Register creates a new user via an invitation token and issues a token pair.
func (s *Service) Register(ctx context.Context, params SessionRegisterParams) (*TokenPair, error) {
	// Validate invitation.
	inv, err := s.invitations.GetByID(ctx, params.InvitationID)
	if err != nil || inv == nil || !inv.IsValid() {
		return nil, pkgerrors.ErrTokenInvalid
	}

	if len(params.Password) < 12 {
		return nil, pkgerrors.ErrPasswordTooShort
	}

	hash, err := crypto.HashPassword(params.Password)
	if err != nil {
		return nil, fmt.Errorf("session.Service.Register hash: %w", err)
	}

	userID, err := s.users.RegisterAtomic(ctx, user.RegisterParams{
		Email:        params.Email,
		DisplayName:  params.DisplayName,
		PasswordHash: hash,
		InvitationID: params.InvitationID,
	})
	if err != nil {
		return nil, fmt.Errorf("session.Service.Register create user: %w", err)
	}

	pair, err := s.IssueForUser(ctx, IssueForUserParams{
		UserID:      userID,
		DeviceName:  params.DeviceName,
		Platform:    params.Platform,
		Fingerprint: params.Fingerprint,
		UserAgent:   params.UserAgent,
		IPAddress:   params.IPAddress,
	})
	if err != nil {
		return nil, fmt.Errorf("session.Service.Register issue tokens: %w", err)
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID: userID,
		Event:  audit.EventUserRegistered,
		Metadata: map[string]any{
			"invitation_id": params.InvitationID,
		},
	})

	return pair, nil
}

// IssueForUser registers (or matches) a device for an existing user and
// issues a fresh token pair. Used after owner creation during bootstrap so
// the owner lands directly on the dashboard without a separate login step.
func (s *Service) IssueForUser(ctx context.Context, params IssueForUserParams) (*TokenPair, error) {
	u, err := s.users.GetByID(ctx, params.UserID)
	if err != nil {
		return nil, fmt.Errorf("session.Service.IssueForUser get user: %w", err)
	}

	dev, err := s.devices.GetByFingerprint(ctx, params.UserID, params.Fingerprint)
	if err != nil {
		return nil, fmt.Errorf("session.Service.IssueForUser device lookup: %w", err)
	}
	if dev == nil {
		dev, err = s.devices.Create(ctx, device.RegisterParams{
			UserID:      params.UserID,
			Name:        params.DeviceName,
			Platform:    device.Platform(params.Platform),
			Fingerprint: params.Fingerprint,
			UserAgent:   params.UserAgent,
		})
		if err != nil {
			return nil, fmt.Errorf("session.Service.IssueForUser create device: %w", err)
		}
		s.audit.WriteAsync(ctx, audit.Event{
			UserID:   params.UserID,
			DeviceID: dev.ID,
			Event:    audit.EventDeviceRegistered,
			Metadata: map[string]any{"platform": params.Platform},
		})
	}

	_ = s.devices.UpdateLastSeen(ctx, dev.ID)

	pair, err := s.issueTokenPair(ctx, u, dev)
	if err != nil {
		return nil, err
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID:    params.UserID,
		DeviceID:  dev.ID,
		Event:     audit.EventLoginSuccess,
		IPAddress: params.IPAddress,
		UserAgent: params.UserAgent,
		Metadata:  map[string]any{"device_name": dev.Name, "via": "bootstrap"},
	})

	return pair, nil
}

// Refresh validates a refresh token and issues a new token pair (rotation).
// Reuse detection: if the presented token was already consumed, ALL sessions
// for the owning user are revoked immediately.
func (s *Service) Refresh(ctx context.Context, rawToken string) (*TokenPair, error) {
	hash := token.HashRefreshToken(rawToken)

	rt, err := s.tokens.GetByHash(ctx, hash)
	if err != nil {
		return nil, pkgerrors.ErrTokenInvalid
	}

	// Reuse detection — consumed token presented again.
	if rt.ConsumedAt != nil {
		dev, err := s.devices.GetByID(ctx, rt.DeviceID)
		if err != nil {
			// Device lookup failed — revoke by device as a fallback so the
			// compromised token family is at least neutralised.
			slog.Error("token reuse: device lookup failed, revoking by device",
				"device_id", rt.DeviceID, "err", err)
			_ = s.tokens.RevokeAllForDevice(ctx, rt.DeviceID)
		} else {
			_ = s.tokens.RevokeAllForUser(ctx, dev.UserID)
		}
		s.audit.WriteAsync(ctx, audit.Event{
			DeviceID: rt.DeviceID,
			Event:    audit.EventTokenReuseDetected,
			Metadata: map[string]any{"all_sessions_revoked": err == nil},
		})
		return nil, pkgerrors.ErrTokenReuseDetected
	}

	if !rt.IsValid() {
		return nil, pkgerrors.ErrTokenRevoked
	}

	// Consume the old token before issuing the new one.
	if err := s.tokens.Consume(ctx, rt.ID); err != nil {
		return nil, fmt.Errorf("session.Service.Refresh consume: %w", err)
	}

	dev, err := s.devices.GetByID(ctx, rt.DeviceID)
	if err != nil {
		return nil, fmt.Errorf("session.Service.Refresh get device: %w", err)
	}
	if dev.IsRevoked() {
		return nil, pkgerrors.ErrDeviceRevoked
	}

	u, err := s.users.GetByID(ctx, dev.UserID)
	if err != nil {
		return nil, fmt.Errorf("session.Service.Refresh get user: %w", err)
	}

	pair, err := s.issueTokenPair(ctx, u, dev)
	if err != nil {
		return nil, err
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID:   u.ID,
		DeviceID: dev.ID,
		Event:    audit.EventTokenRefreshed,
	})

	return pair, nil
}

// Logout revokes all tokens for a specific device.
func (s *Service) Logout(ctx context.Context, userID, deviceID string) error {
	if err := s.tokens.RevokeAllForDevice(ctx, deviceID); err != nil {
		return fmt.Errorf("session.Service.Logout: %w", err)
	}
	s.audit.WriteAsync(ctx, audit.Event{
		UserID:   userID,
		DeviceID: deviceID,
		Event:    audit.EventLogout,
	})
	return nil
}

// GetUser returns the user record for the given ID. Used by the Validate
// handler to enrich the response with fields not carried in the JWT.
func (s *Service) GetUser(ctx context.Context, id string) (*user.User, error) {
	return s.users.GetByID(ctx, id)
}

// LogoutAll revokes all sessions for a user across every device.
func (s *Service) LogoutAll(ctx context.Context, userID string) error {
	if err := s.tokens.RevokeAllForUser(ctx, userID); err != nil {
		return fmt.Errorf("session.Service.LogoutAll: %w", err)
	}
	s.audit.WriteAsync(ctx, audit.Event{
		UserID: userID,
		Event:  audit.EventLogoutAll,
	})
	return nil
}

func (s *Service) issueTokenPair(ctx context.Context, u *user.User, dev *device.Device) (*TokenPair, error) {
	access, err := token.GenerateAccessToken(u.ID, dev.ID, u.InstanceRoleID, s.jwtKey)
	if err != nil {
		return nil, fmt.Errorf("session.Service.issueTokenPair access: %w", err)
	}

	raw, hash, err := token.GenerateRefreshToken()
	if err != nil {
		return nil, fmt.Errorf("session.Service.issueTokenPair refresh: %w", err)
	}

	rt := &RefreshToken{
		DeviceID:  dev.ID,
		TokenHash: hash,
		ExpiresAt: token.RefreshTokenExpiry(),
	}
	if err := s.tokens.Create(ctx, rt); err != nil {
		return nil, fmt.Errorf("session.Service.issueTokenPair store: %w", err)
	}

	return &TokenPair{
		AccessToken:  access,
		RefreshToken: raw,
		ExpiresAt:    rt.ExpiresAt,
	}, nil
}

func recordFailedLogin(ctx context.Context, users user.Repository, auditSvc audit.Service, u *user.User, ip string) error {
	count, err := users.IncrementFailedLogins(ctx, u.ID)
	if err != nil {
		return err
	}
	auditSvc.WriteAsync(ctx, audit.Event{
		UserID:    u.ID,
		Event:     audit.EventLoginFailed,
		IPAddress: ip,
		Metadata:  map[string]any{"reason": "wrong_password", "failed_attempts": count},
	})
	if count >= 10 {
		if err := users.LockAccount(ctx, u.ID, "brute_force"); err != nil {
			slog.Warn("failed to lock account", "user_id", u.ID, "err", err)
		}
		auditSvc.WriteAsync(ctx, audit.Event{
			UserID:   u.ID,
			Event:    audit.EventAccountLocked,
			Metadata: map[string]any{"failed_attempts": count},
		})
	}
	return nil
}
