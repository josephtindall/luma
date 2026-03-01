package postgres

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/audit"
)

// Repository implements audit.Repository against PostgreSQL.
// The DB user has INSERT + SELECT only — no UPDATE, no DELETE.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL audit repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Insert(ctx context.Context, e audit.Event) error {
	const q = `
		INSERT INTO haven.audit_log
		    (user_id, device_id, event, ip_address, user_agent, metadata)
		VALUES (
		    NULLIF($1, '')::UUID,
		    NULLIF($2, '')::UUID,
		    $3,
		    NULLIF($4, '')::INET,
		    NULLIF($5, ''),
		    $6
		)`

	_, err := r.db.Exec(ctx, q,
		e.UserID,
		e.DeviceID,
		e.Event,
		e.IPAddress,
		e.UserAgent,
		e.Metadata,
	)
	if err != nil {
		return fmt.Errorf("audit.postgres.Insert: %w", err)
	}
	return nil
}

func (r *Repository) ListForUser(ctx context.Context, userID string, limit, offset int) ([]*audit.Row, error) {
	const q = `
		SELECT id, user_id, device_id, event, ip_address::TEXT, user_agent, metadata, occurred_at
		FROM haven.audit_log
		WHERE user_id = $1
		ORDER BY occurred_at DESC
		LIMIT $2 OFFSET $3`

	return r.scan(ctx, q, userID, limit, offset)
}

func (r *Repository) ListAll(ctx context.Context, limit, offset int) ([]*audit.Row, error) {
	const q = `
		SELECT id, user_id, device_id, event, ip_address::TEXT, user_agent, metadata, occurred_at
		FROM haven.audit_log
		ORDER BY occurred_at DESC
		LIMIT $1 OFFSET $2`

	return r.scan(ctx, q, limit, offset)
}

func (r *Repository) scan(ctx context.Context, q string, args ...any) ([]*audit.Row, error) {
	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("audit.postgres.scan: %w", err)
	}
	defer rows.Close()

	var result []*audit.Row
	for rows.Next() {
		row := &audit.Row{}
		if err := rows.Scan(
			&row.ID,
			&row.UserID,
			&row.DeviceID,
			&row.Event,
			&row.IPAddress,
			&row.UserAgent,
			&row.Metadata,
			&row.OccurredAt,
		); err != nil {
			return nil, fmt.Errorf("audit.postgres.scan row: %w", err)
		}
		result = append(result, row)
	}
	return result, rows.Err()
}
