package vaults

import "context"

// Repository defines the persistence interface for vaults.
type Repository interface {
	Create(ctx context.Context, vault *Vault) error
	GetByID(ctx context.Context, id string) (*Vault, error)
	ListByUser(ctx context.Context, userID string, includeArchived bool) ([]*Vault, error)
	Update(ctx context.Context, vault *Vault) error
	Archive(ctx context.Context, id string, archivedBy string) error
	HasPersonalVault(ctx context.Context, userID string) (bool, error)

	AddMember(ctx context.Context, member *VaultMember) error
	RemoveMember(ctx context.Context, vaultID, userID string) error
	UpdateMemberRole(ctx context.Context, vaultID, userID, roleID string) error
	ListMembers(ctx context.Context, vaultID string) ([]*VaultMember, error)
	GetMember(ctx context.Context, vaultID, userID string) (*VaultMember, error)
	CountAdmins(ctx context.Context, vaultID string) (int, error)
}
