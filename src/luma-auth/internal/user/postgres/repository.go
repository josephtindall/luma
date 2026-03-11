package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/user"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// Repository implements user.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL user repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) GetByID(ctx context.Context, id string) (*user.User, error) {
	const q = `
		SELECT id, email, display_name, password_hash, instance_role_id,
		       COALESCE(avatar_seed, ''), mfa_enabled, force_password_change,
		       failed_login_attempts, locked_at,
		       COALESCE(locked_reason, ''), created_at, updated_at
		FROM auth.users
		WHERE id = $1`

	u, err := scanUser(r.db.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, pkgerrors.ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("user.postgres.GetByID: %w", err)
	}
	return u, nil
}

func (r *Repository) GetByEmail(ctx context.Context, email string) (*user.User, error) {
	const q = `
		SELECT id, email, display_name, password_hash, instance_role_id,
		       COALESCE(avatar_seed, ''), mfa_enabled, force_password_change,
		       failed_login_attempts, locked_at,
		       COALESCE(locked_reason, ''), created_at, updated_at
		FROM auth.users
		WHERE email = $1`

	u, err := scanUser(r.db.QueryRow(ctx, q, email))
	if errors.Is(err, pgx.ErrNoRows) {
		// Return ErrUserNotFound — but the service maps it to ErrInvalidCredentials
		// so the caller never distinguishes "not found" from "wrong password".
		return nil, pkgerrors.ErrUserNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("user.postgres.GetByEmail: %w", err)
	}
	return u, nil
}

func (r *Repository) Create(ctx context.Context, u *user.User) error {
	const q = `
		INSERT INTO auth.users
		    (id, email, display_name, password_hash, instance_role_id, avatar_seed, force_password_change)
		VALUES ($1, $2, $3, $4, $5, $6, $7)`

	_, err := r.db.Exec(ctx, q,
		u.ID, u.Email, u.DisplayName, u.PasswordHash, u.InstanceRoleID, u.AvatarSeed, u.ForcePasswordChange)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return pkgerrors.ErrEmailTaken
		}
		return fmt.Errorf("user.postgres.Create: %w", err)
	}

	// Enrol the new user in the "Users" system group (best-effort).
	const addToUsers = `
		INSERT INTO auth.group_members (group_id, member_type, member_id)
		VALUES ('00000000-0000-0000-0000-000000000003', 'user', $1)
		ON CONFLICT DO NOTHING`
	_, _ = r.db.Exec(ctx, addToUsers, u.ID)

	return nil
}

func (r *Repository) UpdateProfile(ctx context.Context, id string, params user.UpdateProfileParams) error {
	const q = `
		UPDATE auth.users
		SET display_name = COALESCE(NULLIF($2, ''), display_name),
		    email        = COALESCE(NULLIF($3, ''), email),
		    updated_at   = NOW()
		WHERE id = $1`

	_, err := r.db.Exec(ctx, q, id, params.DisplayName, params.Email)
	if err != nil {
		return fmt.Errorf("user.postgres.UpdateProfile: %w", err)
	}
	return nil
}

func (r *Repository) UpdatePassword(ctx context.Context, id, passwordHash string) error {
	const q = `UPDATE auth.users SET password_hash = $2, updated_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id, passwordHash)
	if err != nil {
		return fmt.Errorf("user.postgres.UpdatePassword: %w", err)
	}
	return nil
}

func (r *Repository) IncrementFailedLogins(ctx context.Context, id string) (int, error) {
	const q = `
		UPDATE auth.users
		SET failed_login_attempts = failed_login_attempts + 1, updated_at = NOW()
		WHERE id = $1
		RETURNING failed_login_attempts`

	var count int
	err := r.db.QueryRow(ctx, q, id).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("user.postgres.IncrementFailedLogins: %w", err)
	}
	return count, nil
}

func (r *Repository) ResetFailedLogins(ctx context.Context, id string) error {
	const q = `
		UPDATE auth.users
		SET failed_login_attempts = 0, updated_at = NOW()
		WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("user.postgres.ResetFailedLogins: %w", err)
	}
	return nil
}

func (r *Repository) LockAccount(ctx context.Context, id, reason string) error {
	const q = `
		UPDATE auth.users
		SET locked_at = NOW(), locked_reason = $2, updated_at = NOW()
		WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id, reason)
	if err != nil {
		return fmt.Errorf("user.postgres.LockAccount: %w", err)
	}
	return nil
}

func (r *Repository) UnlockAccount(ctx context.Context, id string) error {
	const q = `
		UPDATE auth.users
		SET locked_at = NULL, locked_reason = NULL,
		    failed_login_attempts = 0, updated_at = NOW()
		WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("user.postgres.UnlockAccount: %w", err)
	}
	return nil
}

func (r *Repository) SetMFAEnabled(ctx context.Context, id string, enabled bool) error {
	const q = `UPDATE auth.users SET mfa_enabled = $2, updated_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id, enabled)
	if err != nil {
		return fmt.Errorf("user.postgres.SetMFAEnabled: %w", err)
	}
	return nil
}

func (r *Repository) SetForcePasswordChange(ctx context.Context, id string, force bool) error {
	const q = `UPDATE auth.users SET force_password_change = $2, updated_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id, force)
	if err != nil {
		return fmt.Errorf("user.postgres.SetForcePasswordChange: %w", err)
	}
	return nil
}

// RegisterAtomic creates a new member user, their preferences row, and marks
// the invitation as accepted — all inside a single transaction.
func (r *Repository) RegisterAtomic(ctx context.Context, params user.RegisterParams) (string, error) {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return "", fmt.Errorf("user.postgres.RegisterAtomic begin: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	const insertUser = `
		INSERT INTO auth.users (email, display_name, password_hash, instance_role_id)
		VALUES ($1, $2, $3, 'builtin:instance-member')
		RETURNING id`

	var userID string
	err = tx.QueryRow(ctx, insertUser, params.Email, params.DisplayName, params.PasswordHash).Scan(&userID)
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" {
			return "", pkgerrors.ErrEmailTaken
		}
		return "", fmt.Errorf("user.postgres.RegisterAtomic insert user: %w", err)
	}

	const insertPrefs = `INSERT INTO auth.user_preferences (user_id) VALUES ($1)`
	if _, err := tx.Exec(ctx, insertPrefs, userID); err != nil {
		return "", fmt.Errorf("user.postgres.RegisterAtomic insert prefs: %w", err)
	}

	const acceptInv = `
		UPDATE auth.invitations
		SET status = 'accepted', accepted_at = NOW()
		WHERE id = $1 AND status = 'pending'`
	tag, err := tx.Exec(ctx, acceptInv, params.InvitationID)
	if err != nil {
		return "", fmt.Errorf("user.postgres.RegisterAtomic accept invitation: %w", err)
	}
	if tag.RowsAffected() != 1 {
		return "", pkgerrors.ErrTokenInvalid
	}

	// Enrol the new user in the "Users" system group (best-effort).
	const addToUsers = `
		INSERT INTO auth.group_members (group_id, member_type, member_id)
		VALUES ('00000000-0000-0000-0000-000000000003', 'user', $1)
		ON CONFLICT DO NOTHING`
	_, _ = tx.Exec(ctx, addToUsers, userID)

	if err := tx.Commit(ctx); err != nil {
		return "", fmt.Errorf("user.postgres.RegisterAtomic commit: %w", err)
	}
	return userID, nil
}

// List returns all users ordered by created_at descending.
func (r *Repository) List(ctx context.Context, limit, offset int) ([]*user.User, error) {
	const q = `
		SELECT id, email, display_name, password_hash, instance_role_id,
		       COALESCE(avatar_seed, ''), mfa_enabled, force_password_change,
		       failed_login_attempts, locked_at,
		       COALESCE(locked_reason, ''), created_at, updated_at
		FROM auth.users
		ORDER BY created_at DESC
		LIMIT $1 OFFSET $2`

	rows, err := r.db.Query(ctx, q, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("user.postgres.List: %w", err)
	}
	defer rows.Close()

	var users []*user.User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, fmt.Errorf("user.postgres.List scan: %w", err)
		}
		users = append(users, u)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("user.postgres.List rows: %w", err)
	}
	return users, nil
}

// ListWithCounts returns all users as AdminUser projections, including per-user
// TOTP and passkey counts computed via LEFT JOINs.
func (r *Repository) ListWithCounts(ctx context.Context, limit, offset int) ([]*user.AdminUser, error) {
	const q = `
		SELECT u.id, u.email, u.display_name, u.instance_role_id,
		       COALESCE(u.avatar_seed, ''), u.mfa_enabled, u.force_password_change,
		       u.locked_at IS NOT NULL AS is_locked, u.created_at,
		       COUNT(DISTINCT ts.id) FILTER (WHERE ts.verified = true) AS totp_count,
		       COUNT(DISTINCT p.id)  FILTER (WHERE p.revoked_at IS NULL) AS passkey_count
		FROM auth.users u
		LEFT JOIN auth.totp_secrets ts ON ts.user_id = u.id
		LEFT JOIN auth.passkeys     p  ON p.user_id  = u.id
		GROUP BY u.id, u.email, u.display_name, u.instance_role_id,
		         u.avatar_seed, u.mfa_enabled, u.force_password_change,
		         u.locked_at, u.created_at
		ORDER BY u.created_at DESC
		LIMIT $1 OFFSET $2`

	rows, err := r.db.Query(ctx, q, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("user.postgres.ListWithCounts: %w", err)
	}
	defer rows.Close()

	var out []*user.AdminUser
	for rows.Next() {
		au := &user.AdminUser{}
		err := rows.Scan(
			&au.ID,
			&au.Email,
			&au.DisplayName,
			&au.InstanceRoleID,
			&au.AvatarSeed,
			&au.MFAEnabled,
			&au.ForcePasswordChange,
			&au.IsLocked,
			&au.CreatedAt,
			&au.TOTPCount,
			&au.PasskeyCount,
		)
		if err != nil {
			return nil, fmt.Errorf("user.postgres.ListWithCounts scan: %w", err)
		}
		out = append(out, au)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("user.postgres.ListWithCounts rows: %w", err)
	}
	return out, nil
}

func (r *Repository) AddPasswordHistory(ctx context.Context, userID, hash string) error {
	const q = `INSERT INTO auth.password_history (user_id, hash) VALUES ($1, $2)`
	if _, err := r.db.Exec(ctx, q, userID, hash); err != nil {
		return fmt.Errorf("user.postgres.AddPasswordHistory: %w", err)
	}
	return nil
}

func (r *Repository) GetRecentPasswordHashes(ctx context.Context, userID string, count int) ([]string, error) {
	const q = `
		SELECT hash FROM auth.password_history
		WHERE user_id = $1
		ORDER BY created_at DESC
		LIMIT $2`

	rows, err := r.db.Query(ctx, q, userID, count)
	if err != nil {
		return nil, fmt.Errorf("user.postgres.GetRecentPasswordHashes: %w", err)
	}
	defer rows.Close()

	var hashes []string
	for rows.Next() {
		var h string
		if err := rows.Scan(&h); err != nil {
			return nil, fmt.Errorf("user.postgres.GetRecentPasswordHashes scan: %w", err)
		}
		hashes = append(hashes, h)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("user.postgres.GetRecentPasswordHashes rows: %w", err)
	}
	return hashes, nil
}

// scanUser reads a auth.users row from a pgx.Row.
func scanUser(row pgx.Row) (*user.User, error) {
	u := &user.User{}
	err := row.Scan(
		&u.ID,
		&u.Email,
		&u.DisplayName,
		&u.PasswordHash,
		&u.InstanceRoleID,
		&u.AvatarSeed,
		&u.MFAEnabled,
		&u.ForcePasswordChange,
		&u.FailedLoginAttempts,
		&u.LockedAt,
		&u.LockedReason,
		&u.CreatedAt,
		&u.UpdatedAt,
	)
	return u, err
}
