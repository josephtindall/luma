package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/recoverytoken"
)

// Repository implements recoverytoken.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL recovery token repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

// Upsert inserts or replaces a user's recovery token hash.
func (r *Repository) Upsert(ctx context.Context, userID, tokenHash string) error {
	const q = `
		INSERT INTO auth.recovery_tokens (user_id, token_hash)
		VALUES ($1, $2)
		ON CONFLICT (user_id) DO UPDATE
		  SET token_hash = EXCLUDED.token_hash, updated_at = NOW()`
	_, err := r.db.Exec(ctx, q, userID, tokenHash)
	if err != nil {
		return fmt.Errorf("recoverytoken.postgres.Upsert: %w", err)
	}
	return nil
}

// GetByUserID returns the stored recovery token for a user, or nil if absent.
func (r *Repository) GetByUserID(ctx context.Context, userID string) (*recoverytoken.Token, error) {
	const q = `SELECT user_id, token_hash, created_at, updated_at FROM auth.recovery_tokens WHERE user_id = $1`
	var t recoverytoken.Token
	err := r.db.QueryRow(ctx, q, userID).Scan(&t.UserID, &t.TokenHash, &t.CreatedAt, &t.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("recoverytoken.postgres.GetByUserID: %w", err)
	}
	return &t, nil
}

// DeleteByUserID removes a user's recovery token after it has been used.
func (r *Repository) DeleteByUserID(ctx context.Context, userID string) error {
	const q = `DELETE FROM auth.recovery_tokens WHERE user_id = $1`
	_, err := r.db.Exec(ctx, q, userID)
	if err != nil {
		return fmt.Errorf("recoverytoken.postgres.DeleteByUserID: %w", err)
	}
	return nil
}
