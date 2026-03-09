package customrole

import (
	"context"
	"time"
)

// CustomRole is the base custom role record.
type CustomRole struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Priority  *int      `json:"priority"` // nil = lowest precedence
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// CustomRolePermission is one permission entry on a role.
type CustomRolePermission struct {
	Action string `json:"action"`
	Effect string `json:"effect"` // "allow" | "allow_cascade" | "deny"
}

// CustomRoleWithDetails is a CustomRole plus its permissions and assignment counts.
type CustomRoleWithDetails struct {
	CustomRole
	Permissions []CustomRolePermission `json:"permissions"`
	UserCount   int                    `json:"user_count"`
	GroupCount  int                    `json:"group_count"`
}

// Repository is the data access interface for custom roles.
type Repository interface {
	Create(ctx context.Context, name string, priority *int) (*CustomRole, error)
	Update(ctx context.Context, id, name string, priority *int) (*CustomRole, error)
	Delete(ctx context.Context, id string) error
	Get(ctx context.Context, id string) (*CustomRoleWithDetails, error)
	List(ctx context.Context) ([]*CustomRoleWithDetails, error)
	SetPermission(ctx context.Context, roleID, action, effect string) error
	RemovePermission(ctx context.Context, roleID, action string) error
	AssignToUser(ctx context.Context, roleID, userID string) error
	RemoveFromUser(ctx context.Context, roleID, userID string) error
	GetUserCustomRoles(ctx context.Context, userID string) ([]*CustomRole, error)
}
