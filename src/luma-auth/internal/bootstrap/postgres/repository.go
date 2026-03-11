package postgres

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/bootstrap"
)

// Repository implements bootstrap.StateRepository against PostgreSQL.
// There is always exactly one row in auth.instance.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL bootstrap repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Get(ctx context.Context) (*bootstrap.InstanceState, error) {
	const q = `
		SELECT id, name, locale, timezone, setup_state,
		       setup_token_hash, setup_token_expires_at, setup_token_failures,
		       activated_at, version,
		       password_min_length, password_require_uppercase,
		       password_require_lowercase, password_require_numbers,
		       password_require_symbols, password_history_count,
		       content_width, show_github_button, show_donate_button
		FROM auth.instance
		LIMIT 1`

	s := &bootstrap.InstanceState{}
	err := r.db.QueryRow(ctx, q).Scan(
		&s.ID,
		&s.Name,
		&s.Locale,
		&s.Timezone,
		(*string)(&s.SetupState),
		&s.SetupTokenHash,
		&s.SetupTokenExpiresAt,
		&s.SetupTokenFailures,
		&s.ActivatedAt,
		&s.Version,
		&s.PasswordMinLength,
		&s.PasswordRequireUppercase,
		&s.PasswordRequireLowercase,
		&s.PasswordRequireNumbers,
		&s.PasswordRequireSymbols,
		&s.PasswordHistoryCount,
		&s.ContentWidth,
		&s.ShowGithubButton,
		&s.ShowDonateButton,
	)
	if err == pgx.ErrNoRows {
		// Row hasn't been seeded yet — EnsureRow will create it.
		return &bootstrap.InstanceState{SetupState: bootstrap.StateUnclaimed}, nil
	}
	if err != nil {
		return nil, fmt.Errorf("bootstrap.postgres.Get: %w", err)
	}
	return s, nil
}

func (r *Repository) UpdateSettings(ctx context.Context, params bootstrap.InstanceSettingsParams) error {
	// Build a dynamic UPDATE touching only the provided fields.
	setClauses := []string{}
	args := []any{}
	i := 1

	if params.Name != nil {
		setClauses = append(setClauses, fmt.Sprintf("name = $%d", i))
		args = append(args, *params.Name)
		i++
	}
	if params.PasswordMinLength != nil {
		setClauses = append(setClauses, fmt.Sprintf("password_min_length = $%d", i))
		args = append(args, *params.PasswordMinLength)
		i++
	}
	if params.PasswordRequireUppercase != nil {
		setClauses = append(setClauses, fmt.Sprintf("password_require_uppercase = $%d", i))
		args = append(args, *params.PasswordRequireUppercase)
		i++
	}
	if params.PasswordRequireLowercase != nil {
		setClauses = append(setClauses, fmt.Sprintf("password_require_lowercase = $%d", i))
		args = append(args, *params.PasswordRequireLowercase)
		i++
	}
	if params.PasswordRequireNumbers != nil {
		setClauses = append(setClauses, fmt.Sprintf("password_require_numbers = $%d", i))
		args = append(args, *params.PasswordRequireNumbers)
		i++
	}
	if params.PasswordRequireSymbols != nil {
		setClauses = append(setClauses, fmt.Sprintf("password_require_symbols = $%d", i))
		args = append(args, *params.PasswordRequireSymbols)
		i++
	}
	if params.PasswordHistoryCount != nil {
		setClauses = append(setClauses, fmt.Sprintf("password_history_count = $%d", i))
		args = append(args, *params.PasswordHistoryCount)
		i++
	}
	if params.ContentWidth != nil {
		setClauses = append(setClauses, fmt.Sprintf("content_width = $%d", i))
		args = append(args, *params.ContentWidth)
		i++
	}
	if params.ShowGithubButton != nil {
		setClauses = append(setClauses, fmt.Sprintf("show_github_button = $%d", i))
		args = append(args, *params.ShowGithubButton)
		i++
	}
	if params.ShowDonateButton != nil {
		setClauses = append(setClauses, fmt.Sprintf("show_donate_button = $%d", i))
		args = append(args, *params.ShowDonateButton)
		i++
	}

	if len(setClauses) == 0 {
		return nil // nothing to update
	}

	q := "UPDATE auth.instance SET " + joinStrings(setClauses, ", ")
	_, err := r.db.Exec(ctx, q, args...)
	if err != nil {
		return fmt.Errorf("bootstrap.postgres.UpdateSettings: %w", err)
	}
	return nil
}

func joinStrings(ss []string, sep string) string {
	result := ""
	for k, s := range ss {
		if k > 0 {
			result += sep
		}
		result += s
	}
	return result
}

func (r *Repository) EnsureRow(ctx context.Context) error {
	const q = `
		INSERT INTO auth.instance (name)
		VALUES ('Luma')
		ON CONFLICT DO NOTHING`

	_, err := r.db.Exec(ctx, q)
	if err != nil {
		return fmt.Errorf("bootstrap.postgres.EnsureRow: %w", err)
	}
	return nil
}

func (r *Repository) StoreSetupToken(ctx context.Context, tokenHash string, expiresAt time.Time) error {
	const q = `
		UPDATE auth.instance
		SET setup_token_hash       = $1,
		    setup_token_expires_at = $2,
		    setup_token_failures   = 0`

	_, err := r.db.Exec(ctx, q, tokenHash, expiresAt)
	if err != nil {
		return fmt.Errorf("bootstrap.postgres.StoreSetupToken: %w", err)
	}
	return nil
}

func (r *Repository) TransitionToSetup(ctx context.Context, setupWindowExpiresAt time.Time) error {
	const q = `
		UPDATE auth.instance
		SET setup_state            = 'setup',
		    setup_token_expires_at = $1,
		    setup_token_failures   = 0
		WHERE setup_state = 'unclaimed'`

	tag, err := r.db.Exec(ctx, q, setupWindowExpiresAt)
	if err != nil {
		return fmt.Errorf("bootstrap.postgres.TransitionToSetup: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("bootstrap.postgres.TransitionToSetup: state was not unclaimed")
	}
	return nil
}

func (r *Repository) IncrementTokenFailures(ctx context.Context) (int, error) {
	const q = `
		UPDATE auth.instance
		SET setup_token_failures = setup_token_failures + 1
		RETURNING setup_token_failures`

	var count int
	err := r.db.QueryRow(ctx, q).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("bootstrap.postgres.IncrementTokenFailures: %w", err)
	}
	return count, nil
}

func (r *Repository) ResetToUnclaimed(ctx context.Context, newTokenHash string, newExpiresAt time.Time) error {
	const q = `
		UPDATE auth.instance
		SET setup_state            = 'unclaimed',
		    setup_token_hash       = $1,
		    setup_token_expires_at = $2,
		    setup_token_failures   = 0`

	_, err := r.db.Exec(ctx, q, newTokenHash, newExpiresAt)
	if err != nil {
		return fmt.Errorf("bootstrap.postgres.ResetToUnclaimed: %w", err)
	}
	return nil
}

func (r *Repository) ConfigureInstance(ctx context.Context, name, locale, timezone string) error {
	const q = `
		UPDATE auth.instance
		SET name     = $1,
		    locale   = $2,
		    timezone = $3`

	_, err := r.db.Exec(ctx, q, name, locale, timezone)
	if err != nil {
		return fmt.Errorf("bootstrap.postgres.ConfigureInstance: %w", err)
	}
	return nil
}

// CreateOwnerAtomic runs a single transaction:
//  1. INSERT auth.users (role = builtin:instance-owner)
//  2. INSERT auth.user_preferences (all defaults)
//  3. UPDATE auth.instance (state = active, token cleared)
//
// Returns the new user UUID.
func (r *Repository) CreateOwnerAtomic(ctx context.Context, params bootstrap.CreateOwnerParams) (string, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return "", fmt.Errorf("bootstrap.postgres.CreateOwnerAtomic begin: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var userID string
	const insertUser = `
		INSERT INTO auth.users
		    (email, display_name, password_hash, instance_role_id)
		VALUES ($1, $2, $3, 'builtin:instance-owner')
		RETURNING id`

	err = tx.QueryRow(ctx, insertUser,
		params.Email,
		params.DisplayName,
		params.PasswordHash,
	).Scan(&userID)
	if err != nil {
		return "", fmt.Errorf("bootstrap.postgres.CreateOwnerAtomic insert user: %w", err)
	}

	const insertPrefs = `INSERT INTO auth.user_preferences (user_id) VALUES ($1)`
	if _, err := tx.Exec(ctx, insertPrefs, userID); err != nil {
		return "", fmt.Errorf("bootstrap.postgres.CreateOwnerAtomic insert prefs: %w", err)
	}

	const activateInstance = `
		UPDATE auth.instance
		SET setup_state            = 'active',
		    name                   = CASE WHEN $1 <> '' THEN $1 ELSE name END,
		    locale                 = CASE WHEN $2 <> '' THEN $2 ELSE locale END,
		    timezone               = CASE WHEN $3 <> '' THEN $3 ELSE timezone END,
		    activated_at           = NOW(),
		    setup_token_hash       = NULL,
		    setup_token_expires_at = NULL,
		    setup_token_failures   = 0
		WHERE setup_state = 'setup'`

	tag, err := tx.Exec(ctx, activateInstance,
		params.InstanceName, params.Locale, params.Timezone)
	if err != nil {
		return "", fmt.Errorf("bootstrap.postgres.CreateOwnerAtomic activate: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return "", fmt.Errorf("bootstrap.postgres.CreateOwnerAtomic: instance was not in SETUP state")
	}

	// Add the owner to the "Super Admins" system group (best-effort — group may
	// not exist yet on fresh installs that haven't run migration 0011).
	const addToSuperAdmins = `
		INSERT INTO auth.group_members (group_id, member_type, member_id)
		VALUES ('00000000-0000-0000-0000-000000000002', 'user', $1)
		ON CONFLICT DO NOTHING`
	_, _ = tx.Exec(ctx, addToSuperAdmins, userID)

	// Add the owner to the "Users" system group (best-effort — group may
	// not exist yet on fresh installs that haven't run migration 0012).
	const addToUsers = `
		INSERT INTO auth.group_members (group_id, member_type, member_id)
		VALUES ('00000000-0000-0000-0000-000000000003', 'user', $1)
		ON CONFLICT DO NOTHING`
	_, _ = tx.Exec(ctx, addToUsers, userID)

	if err := tx.Commit(ctx); err != nil {
		return "", fmt.Errorf("bootstrap.postgres.CreateOwnerAtomic commit: %w", err)
	}
	return userID, nil
}
