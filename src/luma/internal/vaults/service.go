package vaults

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/josephtindall/luma/pkg/errors"
	"github.com/josephtindall/luma/pkg/shortid"
)

// Deterministic UUIDs for luma-auth system groups — seeded in luma-auth migrations.
// Used in vault_group_members so luma can resolve actual group membership via luma-auth.
const (
	systemGroupUsers      = "00000000-0000-0000-0000-000000000003" // "Users" — every instance member
	systemGroupSuperAdmins = "00000000-0000-0000-0000-000000000002" // "Super Admins"
)

// legacySystemGroups are old string identifiers replaced by the real luma-auth UUIDs.
// Rows with these IDs are removed on first startup after the upgrade.
var legacySystemGroups = []string{"system:users", "system:superadmins"}

// Service contains all business logic for vaults.
type Service struct {
	repo Repository
}

// NewService creates a new vault service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// CreateSharedVault creates a new shared vault and makes the creator a vault admin.
func (s *Service) CreateSharedVault(ctx context.Context, ownerID string, req CreateVaultRequest) (*Vault, error) {
	if strings.TrimSpace(req.Name) == "" {
		return nil, fmt.Errorf("vault name: %w", errors.ErrValidation)
	}

	slug := generateSlug(req.Name)

	vault := &Vault{
		Name:        req.Name,
		Slug:        slug,
		Type:        VaultTypeShared,
		OwnerID:     ownerID,
		IsPrivate:   req.IsPrivate,
		Description: req.Description,
		Icon:        req.Icon,
		Color:       req.Color,
	}

	if err := s.repo.Create(ctx, vault); err != nil {
		return nil, fmt.Errorf("creating vault: %w", err)
	}

	member := &VaultMember{
		VaultID: vault.ID,
		UserID:  ownerID,
		RoleID:  "builtin:vault-admin",
		AddedBy: &ownerID,
	}
	if err := s.repo.AddMember(ctx, member); err != nil {
		return nil, fmt.Errorf("adding creator as admin: %w", err)
	}

	return vault, nil
}

// CreatePersonalVault creates a personal vault for a user.
func (s *Service) CreatePersonalVault(ctx context.Context, userID, displayName string) (*Vault, error) {
	name := displayName + "'s Space"
	slug := generateSlug(name)

	vault := &Vault{
		Name:    name,
		Slug:    slug,
		Type:    VaultTypePersonal,
		OwnerID: userID,
	}

	if err := s.repo.Create(ctx, vault); err != nil {
		return nil, fmt.Errorf("creating personal vault: %w", err)
	}

	member := &VaultMember{
		VaultID: vault.ID,
		UserID:  userID,
		RoleID:  "builtin:vault-admin",
	}
	if err := s.repo.AddMember(ctx, member); err != nil {
		return nil, fmt.Errorf("adding owner as admin: %w", err)
	}

	return vault, nil
}

// GetVault returns a vault by ID.
func (s *Service) GetVault(ctx context.Context, id string) (*Vault, error) {
	vault, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("getting vault: %w", err)
	}
	return vault, nil
}

// ListVaults returns all vaults a user is a member of.
func (s *Service) ListVaults(ctx context.Context, userID string, includeArchived bool) ([]*Vault, error) {
	vaults, err := s.repo.ListByUser(ctx, userID, includeArchived)
	if err != nil {
		return nil, fmt.Errorf("listing vaults: %w", err)
	}
	return vaults, nil
}

// UpdateVault updates a vault's mutable fields.
func (s *Service) UpdateVault(ctx context.Context, id string, req UpdateVaultRequest) (*Vault, error) {
	vault, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return nil, fmt.Errorf("getting vault for update: %w", err)
	}

	if vault.IsArchived {
		return nil, fmt.Errorf("cannot update: %w", errors.ErrArchived)
	}

	if req.Name != nil {
		if strings.TrimSpace(*req.Name) == "" {
			return nil, fmt.Errorf("vault name: %w", errors.ErrValidation)
		}
		vault.Name = *req.Name
	}
	if req.IsPrivate != nil {
		vault.IsPrivate = *req.IsPrivate
	}
	if req.Description != nil {
		vault.Description = req.Description
	}
	if req.Icon != nil {
		vault.Icon = req.Icon
	}
	if req.Color != nil {
		vault.Color = req.Color
	}
	vault.UpdatedAt = time.Now()

	if err := s.repo.Update(ctx, vault); err != nil {
		return nil, fmt.Errorf("updating vault: %w", err)
	}
	return vault, nil
}

// ArchiveVault soft-deletes a vault.
func (s *Service) ArchiveVault(ctx context.Context, id, archivedBy string) error {
	vault, err := s.repo.GetByID(ctx, id)
	if err != nil {
		return fmt.Errorf("getting vault for archive: %w", err)
	}
	if vault.IsArchived {
		return fmt.Errorf("already archived: %w", errors.ErrConflict)
	}
	if err := s.repo.Archive(ctx, id, archivedBy); err != nil {
		return fmt.Errorf("archiving vault: %w", err)
	}
	return nil
}

// AddMember adds a member to a vault.
func (s *Service) AddMember(ctx context.Context, vaultID string, req AddMemberRequest, addedBy string) error {
	vault, err := s.repo.GetByID(ctx, vaultID)
	if err != nil {
		return fmt.Errorf("getting vault for add member: %w", err)
	}
	if vault.IsArchived {
		return fmt.Errorf("cannot add member: %w", errors.ErrArchived)
	}

	existing, err := s.repo.GetMember(ctx, vaultID, req.UserID)
	if err != nil && !errors.Is(err, errors.ErrNotFound) {
		return fmt.Errorf("checking existing member: %w", err)
	}
	if existing != nil {
		return fmt.Errorf("user already a member: %w", errors.ErrAlreadyExists)
	}

	member := &VaultMember{
		VaultID: vaultID,
		UserID:  req.UserID,
		RoleID:  req.RoleID,
		AddedBy: &addedBy,
	}
	if err := s.repo.AddMember(ctx, member); err != nil {
		return fmt.Errorf("adding member: %w", err)
	}
	return nil
}

// RemoveMember removes a member from a vault. Cannot remove the last admin.
func (s *Service) RemoveMember(ctx context.Context, vaultID, userID string) error {
	member, err := s.repo.GetMember(ctx, vaultID, userID)
	if err != nil {
		return fmt.Errorf("getting member: %w", err)
	}

	if member.RoleID == "builtin:vault-admin" {
		count, err := s.repo.CountAdmins(ctx, vaultID)
		if err != nil {
			return fmt.Errorf("counting admins: %w", err)
		}
		if count <= 1 {
			return fmt.Errorf("cannot remove last admin: %w", errors.ErrConflict)
		}
	}

	if err := s.repo.RemoveMember(ctx, vaultID, userID); err != nil {
		return fmt.Errorf("removing member: %w", err)
	}
	return nil
}

// UpdateMemberRole changes a member's vault role. Cannot downgrade the last admin.
func (s *Service) UpdateMemberRole(ctx context.Context, vaultID, userID, newRoleID string) error {
	member, err := s.repo.GetMember(ctx, vaultID, userID)
	if err != nil {
		return fmt.Errorf("getting member for role update: %w", err)
	}

	if member.RoleID == "builtin:vault-admin" && newRoleID != "builtin:vault-admin" {
		count, err := s.repo.CountAdmins(ctx, vaultID)
		if err != nil {
			return fmt.Errorf("counting admins: %w", err)
		}
		if count <= 1 {
			return fmt.Errorf("cannot downgrade last admin: %w", errors.ErrConflict)
		}
	}

	if err := s.repo.UpdateMemberRole(ctx, vaultID, userID, newRoleID); err != nil {
		return fmt.Errorf("updating member role: %w", err)
	}
	return nil
}

// ListAllVaults returns all vaults on the instance (admin use only).
func (s *Service) ListAllVaults(ctx context.Context, includeArchived bool) ([]*Vault, error) {
	vaults, err := s.repo.ListAll(ctx, includeArchived)
	if err != nil {
		return nil, fmt.Errorf("listing all vaults: %w", err)
	}
	return vaults, nil
}

// IsVaultPrivate returns whether the vault requires explicit membership.
func (s *Service) IsVaultPrivate(ctx context.Context, vaultID string) (bool, error) {
	vault, err := s.repo.GetByID(ctx, vaultID)
	if err != nil {
		return true, fmt.Errorf("checking vault privacy: %w", err)
	}
	return vault.IsPrivate, nil
}

// ListMembers returns all members of a vault.
func (s *Service) ListMembers(ctx context.Context, vaultID string) ([]*VaultMember, error) {
	members, err := s.repo.ListMembers(ctx, vaultID)
	if err != nil {
		return nil, fmt.Errorf("listing members: %w", err)
	}
	return members, nil
}

// EnsureSharedVault creates the instance-wide "Shared" vault if it doesn't exist,
// and ensures system groups have the correct roles:
//   - Users (systemGroupUsers)      → builtin:vault-editor
//   - Super Admins (systemGroupSuperAdmins) → builtin:vault-admin
//
// Any legacy "system:*" rows from earlier versions are removed on first run.
func (s *Service) EnsureSharedVault(ctx context.Context) error {
	id, err := s.repo.GetSystemSharedVaultID(ctx)
	if errors.Is(err, errors.ErrNotFound) {
		vault, createErr := s.createSystemVault(ctx)
		if createErr != nil {
			return fmt.Errorf("creating shared vault: %w", createErr)
		}
		id = vault.ID
	} else if err != nil {
		return fmt.Errorf("getting shared vault: %w", err)
	}

	// Remove legacy system: prefixed rows from earlier versions.
	for _, legacyID := range legacySystemGroups {
		if rmErr := s.repo.RemoveGroupMember(ctx, id, legacyID); rmErr != nil && !errors.Is(rmErr, errors.ErrNotFound) {
			return fmt.Errorf("removing legacy group %s: %w", legacyID, rmErr)
		}
	}

	type systemGroup struct {
		id   string
		role string
	}
	desired := []systemGroup{
		{systemGroupUsers, "builtin:vault-editor"},
		{systemGroupSuperAdmins, "builtin:vault-admin"},
	}
	for _, sg := range desired {
		existing, getErr := s.repo.GetGroupMember(ctx, id, sg.id)
		if errors.Is(getErr, errors.ErrNotFound) {
			if addErr := s.repo.AddGroupMember(ctx, &VaultGroupMember{
				VaultID: id,
				GroupID: sg.id,
				RoleID:  sg.role,
			}); addErr != nil {
				return fmt.Errorf("adding %s to shared vault: %w", sg.id, addErr)
			}
		} else if getErr == nil && existing.RoleID != sg.role {
			if updErr := s.repo.UpdateGroupMemberRole(ctx, id, sg.id, sg.role); updErr != nil {
				return fmt.Errorf("updating %s role in shared vault: %w", sg.id, updErr)
			}
		}
	}
	return nil
}

func (s *Service) createSystemVault(ctx context.Context) (*Vault, error) {
	slug := generateSlug("Shared")
	vault := &Vault{
		Name:      "Shared",
		Slug:      slug,
		Type:      VaultTypeShared,
		OwnerID:   "system",
		IsPrivate: false,
	}
	if err := s.repo.Create(ctx, vault); err != nil {
		return nil, fmt.Errorf("creating system vault: %w", err)
	}
	return vault, nil
}

// AddGroupMember adds a group to a vault.
func (s *Service) AddGroupMember(ctx context.Context, vaultID string, req AddGroupMemberRequest, addedBy string) error {
	vault, err := s.repo.GetByID(ctx, vaultID)
	if err != nil {
		return fmt.Errorf("getting vault for add group: %w", err)
	}
	if vault.IsArchived {
		return fmt.Errorf("cannot add group: %w", errors.ErrArchived)
	}

	existing, err := s.repo.GetGroupMember(ctx, vaultID, req.GroupID)
	if err != nil && !errors.Is(err, errors.ErrNotFound) {
		return fmt.Errorf("checking existing group member: %w", err)
	}
	if existing != nil {
		return fmt.Errorf("group already a member: %w", errors.ErrAlreadyExists)
	}

	addedByPtr := addedBy
	member := &VaultGroupMember{
		VaultID: vaultID,
		GroupID: req.GroupID,
		RoleID:  req.RoleID,
		AddedBy: &addedByPtr,
	}
	return s.repo.AddGroupMember(ctx, member)
}

// RemoveGroupMember removes a group from a vault.
func (s *Service) RemoveGroupMember(ctx context.Context, vaultID, groupID string) error {
	if err := s.repo.RemoveGroupMember(ctx, vaultID, groupID); err != nil {
		return fmt.Errorf("removing group member: %w", err)
	}
	return nil
}

// UpdateGroupMemberRole changes a group's vault role.
func (s *Service) UpdateGroupMemberRole(ctx context.Context, vaultID, groupID, newRoleID string) error {
	if err := s.repo.UpdateGroupMemberRole(ctx, vaultID, groupID, newRoleID); err != nil {
		return fmt.Errorf("updating group member role: %w", err)
	}
	return nil
}

// ListGroupMembers returns all group members of a vault.
func (s *Service) ListGroupMembers(ctx context.Context, vaultID string) ([]*VaultGroupMember, error) {
	members, err := s.repo.ListGroupMembers(ctx, vaultID)
	if err != nil {
		return nil, fmt.Errorf("listing group members: %w", err)
	}
	return members, nil
}

func generateSlug(_ string) string {
	id, err := shortid.Generate()
	if err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	return id
}
