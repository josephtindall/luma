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
	IsPrivate   bool       `json:"is_private"`
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

// VaultMemberDetail enriches VaultMember with user display information.
type VaultMemberDetail struct {
	VaultID     string    `json:"vault_id"`
	UserID      string    `json:"user_id"`
	Email       string    `json:"email"`
	DisplayName string    `json:"display_name"`
	AvatarSeed  string    `json:"avatar_seed"`
	RoleID      string    `json:"role_id"`
	AddedAt     time.Time `json:"added_at"`
}

// CreateVaultRequest is the input for creating a new shared vault.
type CreateVaultRequest struct {
	Name        string  `json:"name"`
	IsPrivate   bool    `json:"is_private"`
	Description *string `json:"description,omitempty"`
	Icon        *string `json:"icon,omitempty"`
	Color       *string `json:"color,omitempty"`
}

// UpdateVaultRequest is the input for updating a vault.
type UpdateVaultRequest struct {
	Name        *string `json:"name,omitempty"`
	IsPrivate   *bool   `json:"is_private,omitempty"`
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

// VaultGroupMember represents a group's membership in a vault.
type VaultGroupMember struct {
	VaultID string    `json:"vault_id"`
	GroupID string    `json:"group_id"`
	RoleID  string    `json:"role_id"`
	AddedBy *string   `json:"added_by,omitempty"`
	AddedAt time.Time `json:"added_at"`
}

// VaultGroupMemberDetail enriches VaultGroupMember with group display info.
type VaultGroupMemberDetail struct {
	VaultID   string    `json:"vault_id"`
	GroupID   string    `json:"group_id"`
	GroupName string    `json:"group_name"`
	RoleID    string    `json:"role_id"`
	AddedAt   time.Time `json:"added_at"`
}

// AddGroupMemberRequest is the input for adding a group to a vault.
type AddGroupMemberRequest struct {
	GroupID string `json:"group_id"`
	RoleID  string `json:"role_id"`
}
