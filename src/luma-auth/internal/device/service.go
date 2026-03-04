package device

import (
	"context"
	"fmt"

	"github.com/josephtindall/luma-auth/internal/audit"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// Service contains business logic for device management.
type Service struct {
	repo  Repository
	audit audit.Service
}

// NewService constructs a device Service.
func NewService(repo Repository, auditSvc audit.Service) *Service {
	return &Service{repo: repo, audit: auditSvc}
}

// RegisterOrGet returns an existing device matching the fingerprint, or
// creates and returns a new one. Devices are matched per-user, not globally.
func (s *Service) RegisterOrGet(ctx context.Context, params RegisterParams) (*Device, error) {
	existing, err := s.repo.GetByFingerprint(ctx, params.UserID, params.Fingerprint)
	if err != nil {
		return nil, fmt.Errorf("device.Service.RegisterOrGet lookup: %w", err)
	}
	if existing != nil {
		if existing.IsRevoked() {
			return nil, pkgerrors.ErrDeviceRevoked
		}
		if err := s.repo.UpdateLastSeen(ctx, existing.ID); err != nil {
			return nil, fmt.Errorf("device.Service.RegisterOrGet touch: %w", err)
		}
		return existing, nil
	}

	d, err := s.repo.Create(ctx, params)
	if err != nil {
		return nil, fmt.Errorf("device.Service.RegisterOrGet create: %w", err)
	}
	return d, nil
}

// ListForUser returns all active devices for a user.
func (s *Service) ListForUser(ctx context.Context, userID string) ([]*Device, error) {
	devices, err := s.repo.ListForUser(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("device.Service.ListForUser: %w", err)
	}
	return devices, nil
}

// Revoke revokes a device. requesterID identifies who performed the revocation.
// The caller must also revoke all sessions for this device via session.Service.RevokeAllForDevice.
func (s *Service) Revoke(ctx context.Context, deviceID, callerUserID string) error {
	d, err := s.repo.GetByID(ctx, deviceID)
	if err != nil {
		return fmt.Errorf("device.Service.Revoke get: %w", err)
	}
	// Users can only revoke their own devices (owners can revoke any — checked in handler).
	if d.UserID != callerUserID {
		return pkgerrors.ErrForbidden
	}
	if err := s.repo.Revoke(ctx, deviceID); err != nil {
		return fmt.Errorf("device.Service.Revoke: %w", err)
	}
	s.audit.WriteAsync(ctx, audit.Event{
		DeviceID: deviceID,
		Event:    audit.EventDeviceRevoked,
		Metadata: map[string]any{
			"revoked_by": callerUserID,
		},
	})
	return nil
}
