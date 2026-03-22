package user

import (
	"context"
	"time"
)

// User is the canonical user record. Password hashes are never returned in
// any API response — strip them in the handler before writing JSON.
type User struct {
	ID                  string
	Email               string
	DisplayName         string
	PasswordHash        string // Argon2id PHC string — never expose to callers
	InstanceRoleID      string // e.g. "builtin:instance-owner", "builtin:instance-member"
	AvatarSeed          string
	MFAEnabled          bool
	ForcePasswordChange bool
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

// IsLockExpired returns true if the account was locked more than `d` ago.
// Returns false if the account is not locked.
func (u *User) IsLockExpired(d time.Duration) bool {
	return u.LockedAt != nil && time.Since(*u.LockedAt) > d
}

// PublicUser is the API-safe projection of a user. No password hash, no lock
// details. Returned on GET /api/auth/users/{id} and in token validation.
type PublicUser struct {
	ID             string    `json:"id"`
	Email          string    `json:"email"`
	DisplayName    string    `json:"display_name"`
	InstanceRoleID string    `json:"instance_role_id"`
	AvatarSeed     string    `json:"avatar_seed,omitempty"`
	MFAEnabled     bool      `json:"mfa_enabled"`
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
		MFAEnabled:     u.MFAEnabled,
		CreatedAt:      u.CreatedAt,
	}
}

// AdminUser is the admin-facing projection of a user. Includes lock status,
// force-password-change flag, and MFA method counts.
// Returned on GET /api/auth/admin/users.
type AdminUser struct {
	ID                  string    `json:"id"`
	Email               string    `json:"email"`
	DisplayName         string    `json:"display_name"`
	InstanceRoleID      string    `json:"instance_role_id"`
	AvatarSeed          string    `json:"avatar_seed,omitempty"`
	MFAEnabled          bool      `json:"mfa_enabled"`
	IsLocked            bool      `json:"is_locked"`
	ForcePasswordChange bool      `json:"force_password_change"`
	HideFromSearch      bool      `json:"hide_from_search"`
	TOTPCount           int       `json:"totp_count"`
	PasskeyCount        int       `json:"passkey_count"`
	CreatedAt           time.Time `json:"created_at"`
}

// DirectoryUser is the minimal user info returned by the non-admin directory
// search endpoint. Does not expose lock status or admin fields.
type DirectoryUser struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	AvatarSeed  string `json:"avatar_seed,omitempty"`
}

// ToAdmin converts a User to its admin-facing form.
// TOTPCount and PasskeyCount must be set separately (from a JOIN query).
func (u *User) ToAdmin() *AdminUser {
	return &AdminUser{
		ID:                  u.ID,
		Email:               u.Email,
		DisplayName:         u.DisplayName,
		InstanceRoleID:      u.InstanceRoleID,
		AvatarSeed:          u.AvatarSeed,
		MFAEnabled:          u.MFAEnabled,
		IsLocked:            u.IsLocked(),
		ForcePasswordChange: u.ForcePasswordChange,
		CreatedAt:           u.CreatedAt,
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

// AdminCreateParams holds the validated inputs for admin-initiated user creation.
type AdminCreateParams struct {
	Email               string
	DisplayName         string
	Password            string
	ForcePasswordChange bool
}

// PasswordPolicy describes the instance-level password requirements.
type PasswordPolicy struct {
	MinLength        int
	RequireUppercase bool
	RequireLowercase bool
	RequireNumbers   bool
	RequireSymbols   bool
	HistoryCount     int
}

// PasswordPolicyProvider is satisfied by bootstrap.Service.
// Injected into user.Service to avoid a direct import of bootstrap.
type PasswordPolicyProvider interface {
	GetPasswordPolicy(ctx context.Context) (*PasswordPolicy, error)
}
