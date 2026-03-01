package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/invitation"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// Repository implements invitation.Repository against PostgreSQL.
// Requires migration 0004_invitations.sql.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL invitation repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Create(ctx context.Context, inv *invitation.Invitation) error {
	const q = `
		INSERT INTO haven.invitations
		    (inviter_id, email, note, token_hash, status, expires_at)
		VALUES ($1, NULLIF($2,''), NULLIF($3,''), $4, $5, $6)
		RETURNING id, created_at`

	err := r.db.QueryRow(ctx, q,
		inv.InviterID, inv.Email, inv.Note,
		inv.TokenHash, inv.Status, inv.ExpiresAt,
	).Scan(&inv.ID, &inv.CreatedAt)
	if err != nil {
		return fmt.Errorf("invitation.postgres.Create: %w", err)
	}
	return nil
}

func (r *Repository) GetByHash(ctx context.Context, tokenHash string) (*invitation.Invitation, error) {
	const q = `
		SELECT id, inviter_id, email, note, token_hash, status,
		       expires_at, accepted_at, revoked_at, created_at
		FROM haven.invitations
		WHERE token_hash = $1`

	inv, err := scan(r.db.QueryRow(ctx, q, tokenHash))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, pkgerrors.ErrTokenInvalid
	}
	if err != nil {
		return nil, fmt.Errorf("invitation.postgres.GetByHash: %w", err)
	}
	return inv, nil
}

func (r *Repository) GetByID(ctx context.Context, id string) (*invitation.Invitation, error) {
	const q = `
		SELECT id, inviter_id, email, note, token_hash, status,
		       expires_at, accepted_at, revoked_at, created_at
		FROM haven.invitations
		WHERE id = $1`

	inv, err := scan(r.db.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, pkgerrors.ErrTokenInvalid
	}
	if err != nil {
		return nil, fmt.Errorf("invitation.postgres.GetByID: %w", err)
	}
	return inv, nil
}

func (r *Repository) List(ctx context.Context) ([]*invitation.Invitation, error) {
	const q = `
		SELECT id, inviter_id, email, note, token_hash, status,
		       expires_at, accepted_at, revoked_at, created_at
		FROM haven.invitations
		WHERE status = 'pending'
		ORDER BY created_at DESC`

	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, fmt.Errorf("invitation.postgres.List: %w", err)
	}
	defer rows.Close()

	var result []*invitation.Invitation
	for rows.Next() {
		inv, err := scan(rows)
		if err != nil {
			return nil, fmt.Errorf("invitation.postgres.List scan: %w", err)
		}
		result = append(result, inv)
	}
	return result, rows.Err()
}

func (r *Repository) Accept(ctx context.Context, id string) error {
	const q = `
		UPDATE haven.invitations
		SET status = 'accepted', accepted_at = NOW()
		WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	return err
}

func (r *Repository) Revoke(ctx context.Context, id string) error {
	const q = `
		UPDATE haven.invitations
		SET status = 'revoked', revoked_at = NOW()
		WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	return err
}

func scan(row pgx.Row) (*invitation.Invitation, error) {
	inv := &invitation.Invitation{}
	var status string
	err := row.Scan(
		&inv.ID,
		&inv.InviterID,
		&inv.Email,
		&inv.Note,
		&inv.TokenHash,
		&status,
		&inv.ExpiresAt,
		&inv.AcceptedAt,
		&inv.RevokedAt,
		&inv.CreatedAt,
	)
	inv.Status = invitation.Status(status)
	return inv, err
}
