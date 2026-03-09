package customrole

import (
	"context"
)

// Service implements custom role business logic.
type Service struct {
	repo Repository
}

// NewService constructs the custom role service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

func (s *Service) Create(ctx context.Context, name string, priority *int) (*CustomRole, error) {
	return s.repo.Create(ctx, name, priority)
}

func (s *Service) Update(ctx context.Context, id, name string, priority *int) (*CustomRole, error) {
	return s.repo.Update(ctx, id, name, priority)
}

func (s *Service) Delete(ctx context.Context, id string) error {
	return s.repo.Delete(ctx, id)
}

func (s *Service) Get(ctx context.Context, id string) (*CustomRoleWithDetails, error) {
	return s.repo.Get(ctx, id)
}

func (s *Service) List(ctx context.Context) ([]*CustomRoleWithDetails, error) {
	return s.repo.List(ctx)
}

func (s *Service) SetPermission(ctx context.Context, roleID, action, effect string) error {
	return s.repo.SetPermission(ctx, roleID, action, effect)
}

func (s *Service) RemovePermission(ctx context.Context, roleID, action string) error {
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
