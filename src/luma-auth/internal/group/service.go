package group

import (
	"context"
	"fmt"

	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// Service implements group business logic.
type Service struct {
	repo Repository
}

// NewService constructs the group service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// Create creates a new group.
func (s *Service) Create(ctx context.Context, name string) (*Group, error) {
	return s.repo.Create(ctx, name)
}

// Rename changes a group's display name.
func (s *Service) Rename(ctx context.Context, id, name string) (*Group, error) {
	return s.repo.Rename(ctx, id, name)
}

// Delete deletes a group only if it has no members.
func (s *Service) Delete(ctx context.Context, id string) error {
	g, err := s.repo.Get(ctx, id)
	if err != nil {
		return fmt.Errorf("group.Delete: %w", err)
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
func (s *Service) AddMember(ctx context.Context, groupID, memberType, memberID string) error {
	if memberType == "group" {
		cycle, err := s.repo.WouldCycle(ctx, groupID, memberID)
		if err != nil {
			return fmt.Errorf("group.AddMember: cycle check: %w", err)
		}
		if cycle {
			return pkgerrors.ErrGroupCycle
		}
	}
	return s.repo.AddMember(ctx, groupID, memberType, memberID)
}

// RemoveMember removes a member from a group.
func (s *Service) RemoveMember(ctx context.Context, groupID, memberType, memberID string) error {
	return s.repo.RemoveMember(ctx, groupID, memberType, memberID)
}

// AssignRole assigns a custom role to a group.
func (s *Service) AssignRole(ctx context.Context, groupID, roleID string) error {
	return s.repo.AssignRole(ctx, groupID, roleID)
}

// RemoveRole removes a custom role from a group.
func (s *Service) RemoveRole(ctx context.Context, groupID, roleID string) error {
	return s.repo.RemoveRole(ctx, groupID, roleID)
}
