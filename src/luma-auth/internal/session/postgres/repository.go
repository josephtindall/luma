package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/session"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// Repository implements session.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL session repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, t *session.RefreshToken) error {
	const q = `
		INSERT INTO haven.refresh_tokens (device_id, token_hash, expires_at)
		VALUES ($1, $2, $3)
		RETURNING id, created_at`

	err := r.db.QueryRow(ctx, q, t.DeviceID, t.TokenHash, t.ExpiresAt).
		Scan(&t.ID, &t.CreatedAt)
	if err != nil {
		return fmt.Errorf("session.postgres.Create: %w", err)
	}
	return nil
}

func (r *Repository) GetByHash(ctx context.Context, hash string) (*session.RefreshToken, error) {
	const q = `
		SELECT id, device_id, token_hash, expires_at, consumed_at, revoked_at, created_at
		FROM haven.refresh_tokens
		WHERE token_hash = $1`

	t := &session.RefreshToken{}
	err := r.db.QueryRow(ctx, q, hash).Scan(
		&t.ID, &t.DeviceID, &t.TokenHash, &t.ExpiresAt,
		&t.ConsumedAt, &t.RevokedAt, &t.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, pkgerrors.ErrTokenInvalid
	}
	if err != nil {
		return nil, fmt.Errorf("session.postgres.GetByHash: %w", err)
	}
	return t, nil
}

func (r *Repository) Consume(ctx context.Context, id string) error {
	const q = `
		UPDATE haven.refresh_tokens
		SET consumed_at = NOW()
		WHERE id = $1 AND consumed_at IS NULL AND revoked_at IS NULL`

	tag, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("session.postgres.Consume: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return pkgerrors.ErrTokenInvalid
	}
	return nil
}

func (r *Repository) RevokeAllForUser(ctx context.Context, userID string) error {
	const q = `
		UPDATE haven.refresh_tokens rt
		SET revoked_at = NOW()
		FROM haven.devices d
		WHERE rt.device_id = d.id
		  AND d.user_id    = $1
		  AND rt.revoked_at IS NULL`

	_, err := r.db.Exec(ctx, q, userID)
	if err != nil {
		return fmt.Errorf("session.postgres.RevokeAllForUser: %w", err)
	}
	return nil
}

func (r *Repository) RevokeAllForDevice(ctx context.Context, deviceID string) error {
	const q = `
		UPDATE haven.refresh_tokens
		SET revoked_at = NOW()
		WHERE device_id = $1 AND revoked_at IS NULL`

	_, err := r.db.Exec(ctx, q, deviceID)
	if err != nil {
		return fmt.Errorf("session.postgres.RevokeAllForDevice: %w", err)
	}
	return nil
}
