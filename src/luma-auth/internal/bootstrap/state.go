package bootstrap

import (
	"context"
	"time"
)

// State represents the bootstrap lifecycle of the Haven instance.
// Enforced simultaneously at three independent layers:
//   - DB column (haven.instance.setup_state)
//   - HTTP middleware (BootstrapGate)
//   - Handler (explicit State check inside each setup handler)
type State string

const (
	StateUnclaimed State = "unclaimed"
	StateSetup     State = "setup"
	StateActive    State = "active"
)

// InstanceState is the runtime representation of the haven.instance row.
type InstanceState struct {
	ID                  string
	Name                string
	Locale              string
	Timezone            string
	SetupState          State
	SetupTokenHash      *string
	SetupTokenExpiresAt *time.Time
	SetupTokenFailures  int
	ActivatedAt         *time.Time
	Version             string
}

// CreateOwnerParams carries all fields required to atomically create the
// owner user and transition the instance to ACTIVE in one transaction.
type CreateOwnerParams struct {
	DisplayName  string
	Email        string
	PasswordHash string // Argon2id PHC string — already hashed
	InstanceName string
	Locale       string
	Timezone     string
}

// StateRepository is the persistence interface for bootstrap state.
// All write methods operate on the single haven.instance row.
type StateRepository interface {
	// Get returns the current instance state.
	Get(ctx context.Context) (*InstanceState, error)

	// EnsureRow inserts the haven.instance row with defaults if it doesn't exist.
	// Safe to call on every startup — idempotent.
	EnsureRow(ctx context.Context) error

	// StoreSetupToken writes a new token hash and expiry, setting failures to 0.
	// Called once at startup when state is UNCLAIMED and no valid token exists.
	StoreSetupToken(ctx context.Context, tokenHash string, expiresAt time.Time) error

	// TransitionToSetup clears the setup token (consumed) and records the 30-minute
	// SETUP window expiry. Called when the setup token is successfully verified.
	TransitionToSetup(ctx context.Context, setupWindowExpiresAt time.Time) error

	// IncrementTokenFailures bumps the failure counter and returns the new count.
	// Caller calls ResetToUnclaimed when count reaches 3.
	IncrementTokenFailures(ctx context.Context) (int, error)

	// ResetToUnclaimed stores a freshly generated token (after 3 failures or
	// 30-minute SETUP timeout) and resets state back to UNCLAIMED.
	ResetToUnclaimed(ctx context.Context, newTokenHash string, newExpiresAt time.Time) error

	// ConfigureInstance updates name, locale, and timezone. Called during Step 2.
	ConfigureInstance(ctx context.Context, name, locale, timezone string) error

	// CreateOwnerAtomic runs a single DB transaction that:
	//   1. INSERTs haven.users with role builtin:instance-owner
	//   2. INSERTs haven.user_preferences with defaults
	//   3. UPDATEs haven.instance: state=active, activated_at=NOW(), token cleared
	// Returns the new user's UUID on success.
	CreateOwnerAtomic(ctx context.Context, params CreateOwnerParams) (userID string, err error)
}
