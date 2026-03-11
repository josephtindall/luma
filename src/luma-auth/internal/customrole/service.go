package customrole

import (
	"context"
	"fmt"

	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// Service implements custom role business logic.
type Service struct {
	repo Repository
}

// NewService constructs the custom role service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) Create(ctx context.Context, name string, priority *int, description *string) (*CustomRole, error) {
	return s.repo.Create(ctx, name, priority, description)
}

func (s *Service) Update(ctx context.Context, id, name string, priority *int, description *string) (*CustomRole, error) {
	cr, err := s.repo.Get(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("customrole.Update: %w", err)
	}
	if cr.IsSystem {
		return nil, pkgerrors.ErrSystemEntity
	}
	return s.repo.Update(ctx, id, name, priority, description)
}

func (s *Service) Delete(ctx context.Context, id string) error {
	cr, err := s.repo.Get(ctx, id)
	if err != nil {
		return fmt.Errorf("customrole.Delete: %w", err)
	}
	if cr.IsSystem {
		return pkgerrors.ErrSystemEntity
	}
	return s.repo.Delete(ctx, id)
}

func (s *Service) Get(ctx context.Context, id string) (*CustomRoleWithDetails, error) {
	return s.repo.Get(ctx, id)
}

func (s *Service) List(ctx context.Context) ([]*CustomRoleWithDetails, error) {
	return s.repo.List(ctx)
}

func (s *Service) SetPermission(ctx context.Context, roleID, action, effect string) error {
	cr, err := s.repo.Get(ctx, roleID)
	if err != nil {
		return fmt.Errorf("customrole.SetPermission: %w", err)
	}
	if cr.IsSystem {
		return pkgerrors.ErrSystemEntity
	}
	return s.repo.SetPermission(ctx, roleID, action, effect)
}

func (s *Service) RemovePermission(ctx context.Context, roleID, action string) error {
	cr, err := s.repo.Get(ctx, roleID)
	if err != nil {
		return fmt.Errorf("customrole.RemovePermission: %w", err)
	}
	if cr.IsSystem {
		return pkgerrors.ErrSystemEntity
	}
	return s.repo.RemovePermission(ctx, roleID, action)
}

func (s *Service) AssignToUser(ctx context.Context, roleID, userID string) error {
	return s.repo.AssignToUser(ctx, roleID, userID)
}

func (s *Service) RemoveFromUser(ctx context.Context, roleID, userID string) error {
	return s.repo.RemoveFromUser(ctx, roleID, userID)
}

func (s *Service) GetUserCustomRoles(ctx context.Context, userID string) ([]*CustomRole, error) {
	return s.repo.GetUserCustomRoles(ctx, userID)
}
