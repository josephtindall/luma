package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/passwordreset"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// Repository implements passwordreset.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL password reset repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, t *passwordreset.Token) error {
	const q = `
		INSERT INTO auth.password_reset_tokens
		    (user_id, token_hash, source, expires_at)
		VALUES ($1, $2, $3, $4)
		RETURNING id, created_at`

	err := r.db.QueryRow(ctx, q, t.UserID, t.TokenHash, t.Source, t.ExpiresAt).
		Scan(&t.ID, &t.CreatedAt)
	if err != nil {
		return fmt.Errorf("passwordreset.postgres.Create: %w", err)
	}
	return nil
}

func (r *Repository) GetByHash(ctx context.Context, tokenHash string) (*passwordreset.Token, error) {
	const q = `
		SELECT id, user_id, token_hash, source, expires_at, consumed_at, created_at
		FROM auth.password_reset_tokens
		WHERE token_hash = $1`

	t := &passwordreset.Token{}
	err := r.db.QueryRow(ctx, q, tokenHash).Scan(
		&t.ID, &t.UserID, &t.TokenHash, &t.Source,
		&t.ExpiresAt, &t.ConsumedAt, &t.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, pkgerrors.ErrTokenInvalid
	}
	if err != nil {
		return nil, fmt.Errorf("passwordreset.postgres.GetByHash: %w", err)
	}
	return t, nil
}

func (r *Repository) Consume(ctx context.Context, id string) error {
	const q = `
		UPDATE auth.password_reset_tokens
		SET consumed_at = NOW()
		WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("passwordreset.postgres.Consume: %w", err)
	}
	return nil
}
