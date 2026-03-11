package user

import "context"

// Repository is the persistence interface for users.
// The concrete PostgreSQL implementation lives in internal/user/postgres.
type Repository interface {
	// GetByID returns the user with the given UUID.
	GetByID(ctx context.Context, id string) (*User, error)

	// GetByEmail looks up a user by email. Used during login —
	// MUST NOT reveal whether the email exists (see service layer).
	GetByEmail(ctx context.Context, email string) (*User, error)

	// Create inserts a new user row. Must be called inside a transaction
	// when creating the owner during bootstrap (atomic with state transition).
	Create(ctx context.Context, u *User) error

	// UpdateProfile updates display_name and/or email.
	UpdateProfile(ctx context.Context, id string, params UpdateProfileParams) error

	// UpdatePassword sets a new password_hash and bumps updated_at.
	UpdatePassword(ctx context.Context, id, passwordHash string) error

	// IncrementFailedLogins increments failed_login_attempts and returns
	// the new count. Caller locks the account when count reaches the threshold.
	IncrementFailedLogins(ctx context.Context, id string) (int, error)

	// ResetFailedLogins zeroes the counter after a successful login.
	ResetFailedLogins(ctx context.Context, id string) error

	// LockAccount sets locked_at and locked_reason.
	LockAccount(ctx context.Context, id, reason string) error

	// UnlockAccount clears locked_at, locked_reason, and failed_login_attempts.
	UnlockAccount(ctx context.Context, id string) error

	// SetMFAEnabled updates the mfa_enabled flag on the user.
	SetMFAEnabled(ctx context.Context, id string, enabled bool) error

	// SetForcePasswordChange sets or clears the force_password_change flag.
	SetForcePasswordChange(ctx context.Context, id string, force bool) error

	// RegisterAtomic creates a new user, their preferences row, and marks the
	// invitation as accepted — all inside a single transaction.
	// Returns the new user's UUID.
	RegisterAtomic(ctx context.Context, params RegisterParams) (string, error)

	// List returns all users ordered by created_at descending.
	// Used by admin endpoints only.
	List(ctx context.Context, limit, offset int) ([]*User, error)

	// ListWithCounts returns all users with per-user TOTP and passkey counts.
	// Used by the admin ListUsers endpoint.
	ListWithCounts(ctx context.Context, limit, offset int) ([]*AdminUser, error)

	// AddPasswordHistory records a hashed password in the history table.
	AddPasswordHistory(ctx context.Context, userID, hash string) error

	// GetRecentPasswordHashes returns the most recent `count` password hashes for
	// a user, ordered newest first. Used to enforce password reuse prevention.
	GetRecentPasswordHashes(ctx context.Context, userID string, count int) ([]string, error)
}
