package group

import (
	"context"
	"time"
)

// Group is the base group record.
type Group struct {
	ID              string    `json:"id"`
	Name            string    `json:"name"`
	Description     *string   `json:"description"`
	IsSystem        bool      `json:"is_system"`
	NoMemberControl bool      `json:"no_member_control"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

// GroupMember is one member entry (user or sub-group).
type GroupMember struct {
	MemberType string    `json:"member_type"` // "user" | "group"
	MemberID   string    `json:"member_id"`
	AddedAt    time.Time `json:"added_at"`
}

// GroupWithDetails is a Group plus its members and assigned custom-role IDs.
type GroupWithDetails struct {
	Group
	Members     []GroupMember `json:"members"`
	RoleIDs     []string      `json:"role_ids"`
	MemberCount int           `json:"member_count"`
}

// Repository is the data access interface for groups.
type Repository interface {
	Create(ctx context.Context, name string, description *string) (*Group, error)
	Rename(ctx context.Context, id, name string, description *string) (*Group, error)
	Delete(ctx context.Context, id string) error
	Get(ctx context.Context, id string) (*GroupWithDetails, error)
	List(ctx context.Context) ([]*GroupWithDetails, error)
	AddMember(ctx context.Context, groupID, memberType, memberID string) error
	RemoveMember(ctx context.Context, groupID, memberType, memberID string) error
	WouldCycle(ctx context.Context, parentGroupID, candidateChildID string) (bool, error)
	AssignRole(ctx context.Context, groupID, roleID string) error
	RemoveRole(ctx context.Context, groupID, roleID string) error
	// GetUserGroupIDs returns all group IDs the user belongs to, including
	// groups inherited through nested group membership at any depth.
	GetUserGroupIDs(ctx context.Context, userID string) ([]string, error)
}
