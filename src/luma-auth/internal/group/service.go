package group

import (
	"context"
	"fmt"

	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// CacheInvalidator is a narrow interface for invalidating a user's authz cache.
// Satisfied by authz.Repository without creating an import cycle.
type CacheInvalidator interface {
	InvalidateUserCache(ctx context.Context, userID string) error
}

// Service implements group business logic.
type Service struct {
	repo        Repository
	cacheInv    CacheInvalidator // optional — nil disables cache invalidation
}

// NewService constructs the group service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// SetCacheInvalidator wires cache invalidation after construction.
func (s *Service) SetCacheInvalidator(inv CacheInvalidator) {
	s.cacheInv = inv
}

// Create creates a new group.
func (s *Service) Create(ctx context.Context, name string, description *string) (*Group, error) {
	return s.repo.Create(ctx, name, description)
}

// Rename changes a group's display name and optional description.
func (s *Service) Rename(ctx context.Context, id, name string, description *string) (*Group, error) {
	return s.repo.Rename(ctx, id, name, description)
}

// Delete deletes a group only if it is not a system group and has no members.
func (s *Service) Delete(ctx context.Context, id string) error {
	g, err := s.repo.Get(ctx, id)
	if err != nil {
		return fmt.Errorf("group.Delete: %w", err)
	}
	if g.IsSystem {
		return pkgerrors.ErrSystemEntity
	}
	if g.MemberCount > 0 {
		return pkgerrors.ErrGroupNotEmpty
	}
	return s.repo.Delete(ctx, id)
}

// Get returns full group details.
func (s *Service) Get(ctx context.Context, id string) (*GroupWithDetails, error) {
	return s.repo.Get(ctx, id)
}

// List returns all groups with details.
func (s *Service) List(ctx context.Context) ([]*GroupWithDetails, error) {
	return s.repo.List(ctx)
}

// AddMember adds a user or sub-group to a group after cycle detection.
// Returns ErrGroupNoMemberControl if the group has membership auto-management.
func (s *Service) AddMember(ctx context.Context, groupID, memberType, memberID string) error {
	g, err := s.repo.Get(ctx, groupID)
	if err != nil {
		return fmt.Errorf("group.AddMember: %w", err)
	}
	if g.NoMemberControl {
		return pkgerrors.ErrGroupNoMemberControl
	}

	if memberType == "group" {
		cycle, err := s.repo.WouldCycle(ctx, groupID, memberID)
		if err != nil {
			return fmt.Errorf("group.AddMember: cycle check: %w", err)
		}
		if cycle {
			return pkgerrors.ErrGroupCycle
		}
	}
	if err := s.repo.AddMember(ctx, groupID, memberType, memberID); err != nil {
		return err
	}
	if s.cacheInv != nil && memberType == "user" {
		_ = s.cacheInv.InvalidateUserCache(ctx, memberID)
	}
	return nil
}

// RemoveMember removes a member from a group.
// Returns ErrGroupNoMemberControl if the group has membership auto-management.
func (s *Service) RemoveMember(ctx context.Context, groupID, memberType, memberID string) error {
	g, err := s.repo.Get(ctx, groupID)
	if err != nil {
		return fmt.Errorf("group.RemoveMember: %w", err)
	}
	if g.NoMemberControl {
		return pkgerrors.ErrGroupNoMemberControl
	}
	if err := s.repo.RemoveMember(ctx, groupID, memberType, memberID); err != nil {
		return err
	}
	if s.cacheInv != nil && memberType == "user" {
		_ = s.cacheInv.InvalidateUserCache(ctx, memberID)
	}
	return nil
}

// AssignRole assigns a custom role to a group.
func (s *Service) AssignRole(ctx context.Context, groupID, roleID string) error {
	return s.repo.AssignRole(ctx, groupID, roleID)
}

// RemoveRole removes a custom role from a group.
func (s *Service) RemoveRole(ctx context.Context, groupID, roleID string) error {
	return s.repo.RemoveRole(ctx, groupID, roleID)
}

// GetUserGroupIDs returns all group IDs the user belongs to (direct and nested).
func (s *Service) GetUserGroupIDs(ctx context.Context, userID string) ([]string, error) {
	return s.repo.GetUserGroupIDs(ctx, userID)
}
