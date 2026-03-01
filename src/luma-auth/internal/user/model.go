package user

import "time"

// User is the canonical user record. Password hashes are never returned in
// any API response — strip them in the handler before writing JSON.
type User struct {
	ID                  string
	Email               string
	DisplayName         string
	PasswordHash        string // Argon2id PHC string — never expose to callers
	InstanceRoleID      string // e.g. "builtin:instance-owner", "builtin:instance-member"
	AvatarSeed          string
	FailedLoginAttempts int
	LockedAt            *time.Time
	LockedReason        string
	CreatedAt           time.Time
	UpdatedAt           time.Time
}

// IsLocked returns true if the user's account has been locked.
func (u *User) IsLocked() bool {
	return u.LockedAt != nil
}

// PublicUser is the API-safe projection of a user. No password hash, no lock
// details. Returned on GET /api/auth/users/{id} and in token validation.
type PublicUser struct {
	ID             string    `json:"id"`
	Email          string    `json:"email"`
	DisplayName    string    `json:"display_name"`
	InstanceRoleID string    `json:"instance_role_id"`
	AvatarSeed     string    `json:"avatar_seed,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

// ToPublic converts a User to its API-safe form.
func (u *User) ToPublic() *PublicUser {
	return &PublicUser{
		ID:             u.ID,
		Email:          u.Email,
		DisplayName:    u.DisplayName,
		InstanceRoleID: u.InstanceRoleID,
		AvatarSeed:     u.AvatarSeed,
		CreatedAt:      u.CreatedAt,
	}
}

// UpdateProfileParams holds validated fields for PUT /api/auth/users/me/profile.
type UpdateProfileParams struct {
	DisplayName string
	Email       string
}

// ChangePasswordParams holds validated fields for POST /api/auth/users/me/password.
type ChangePasswordParams struct {
	CurrentPassword string
	NewPassword     string
}

// RegisterParams holds the validated inputs for invitation-gated registration.
type RegisterParams struct {
	Email        string
	DisplayName  string
	PasswordHash string
	InvitationID string
}
