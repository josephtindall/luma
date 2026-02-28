package vaults

import "time"

// VaultType represents the type of a vault.
type VaultType string

const (
	VaultTypePersonal VaultType = "personal"
	VaultTypeShared   VaultType = "shared"
)

// Vault represents a top-level organizational container.
type Vault struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	Slug        string     `json:"slug"`
	Type        VaultType  `json:"type"`
	OwnerID     string     `json:"owner_id"`
	Description *string    `json:"description,omitempty"`
	Icon        *string    `json:"icon,omitempty"`
	Color       *string    `json:"color,omitempty"`
	IsArchived  bool       `json:"is_archived"`
	ArchivedAt  *time.Time `json:"archived_at,omitempty"`
	ArchivedBy  *string    `json:"archived_by,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

// VaultMember represents a user's membership in a vault.
type VaultMember struct {
	VaultID string    `json:"vault_id"`
	UserID  string    `json:"user_id"`
	RoleID  string    `json:"role_id"`
	AddedBy *string   `json:"added_by,omitempty"`
	AddedAt time.Time `json:"added_at"`
}

// CreateVaultRequest is the input for creating a new shared vault.
type CreateVaultRequest struct {
	Name        string  `json:"name"`
	Description *string `json:"description,omitempty"`
	Icon        *string `json:"icon,omitempty"`
	Color       *string `json:"color,omitempty"`
}

// UpdateVaultRequest is the input for updating a vault.
type UpdateVaultRequest struct {
	Name        *string `json:"name,omitempty"`
	Description *string `json:"description,omitempty"`
	Icon        *string `json:"icon,omitempty"`
	Color       *string `json:"color,omitempty"`
}

// AddMemberRequest is the input for adding a member to a vault.
type AddMemberRequest struct {
	UserID string `json:"user_id"`
	RoleID string `json:"role_id"`
}

// UpdateMemberRoleRequest is the input for changing a member's role.
type UpdateMemberRoleRequest struct {
	RoleID string `json:"role_id"`
}
