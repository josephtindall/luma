package postgres

import (
	"context"
	"fmt"
	"strings"

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
		INSERT INTO auth.audit_log
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

// ListForUser returns filtered, paginated audit events for a single user.
func (r *Repository) ListForUser(ctx context.Context, userID string, q audit.AuditQuery) (*audit.Page, error) {
	args := []any{userID}
	where := buildWhere(&args, "a.user_id = $1", q)

	countQ := `SELECT COUNT(*) FROM auth.audit_log a WHERE ` + where
	var total int
	if err := r.db.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, fmt.Errorf("audit.postgres.ListForUser count: %w", err)
	}

	args = append(args, q.Limit, q.Offset)
	n := len(args)
	selectQ := fmt.Sprintf(`
		SELECT a.id, a.user_id, a.device_id, a.event,
		       a.ip_address::TEXT, a.user_agent, a.metadata, a.occurred_at
		FROM auth.audit_log a
		WHERE %s
		ORDER BY a.occurred_at DESC
		LIMIT $%d OFFSET $%d`, where, n-1, n)

	rows, err := r.scanUser(ctx, selectQ, args...)
	if err != nil {
		return nil, err
	}
	return &audit.Page{Rows: rows, Total: total}, nil
}

// ListAll returns filtered, paginated audit events across all users.
// Row.UserEmail and Row.UserDisplayName are populated via LEFT JOIN.
func (r *Repository) ListAll(ctx context.Context, q audit.AuditQuery) (*audit.Page, error) {
	args := []any{}
	where := buildWhere(&args, "1=1", q)

	countQ := `
		SELECT COUNT(*)
		FROM auth.audit_log a
		LEFT JOIN auth.users u ON u.id = a.user_id
		WHERE ` + where
	var total int
	if err := r.db.QueryRow(ctx, countQ, args...).Scan(&total); err != nil {
		return nil, fmt.Errorf("audit.postgres.ListAll count: %w", err)
	}

	args = append(args, q.Limit, q.Offset)
	n := len(args)
	selectQ := fmt.Sprintf(`
		SELECT a.id, a.user_id, a.device_id, a.event,
		       a.ip_address::TEXT, a.user_agent, a.metadata, a.occurred_at,
		       u.email, u.display_name
		FROM auth.audit_log a
		LEFT JOIN auth.users u ON u.id = a.user_id
		WHERE %s
		ORDER BY a.occurred_at DESC
		LIMIT $%d OFFSET $%d`, where, n-1, n)

	rows, err := r.scanAll(ctx, selectQ, args...)
	if err != nil {
		return nil, err
	}
	return &audit.Page{Rows: rows, Total: total}, nil
}

// buildWhere appends filter conditions to args and returns a WHERE clause string.
// base is the mandatory starting condition (e.g. "user_id = $1" or "1=1").
func buildWhere(args *[]any, base string, q audit.AuditQuery) string {
	parts := []string{base}

	if q.Search != "" {
		*args = append(*args, "%"+q.Search+"%")
		n := len(*args)
		parts = append(parts, fmt.Sprintf(
			"(a.event ILIKE $%d OR a.user_agent ILIKE $%d)", n, n))
	}
	if q.EventFilter != "" {
		*args = append(*args, q.EventFilter)
		parts = append(parts, fmt.Sprintf("a.event = $%d", len(*args)))
	}
	if q.Exclude != "" {
		*args = append(*args, q.Exclude)
		parts = append(parts, fmt.Sprintf("a.event != $%d", len(*args)))
	}
	if q.After != nil {
		*args = append(*args, *q.After)
		parts = append(parts, fmt.Sprintf("a.occurred_at >= $%d", len(*args)))
	}
	if q.Before != nil {
		*args = append(*args, *q.Before)
		parts = append(parts, fmt.Sprintf("a.occurred_at <= $%d", len(*args)))
	}

	return strings.Join(parts, " AND ")
}

func (r *Repository) scanUser(ctx context.Context, q string, args ...any) ([]*audit.Row, error) {
	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("audit.postgres.scanUser: %w", err)
	}
	defer rows.Close()

	var result []*audit.Row
	for rows.Next() {
		row := &audit.Row{}
		if err := rows.Scan(
			&row.ID, &row.UserID, &row.DeviceID, &row.Event,
			&row.IPAddress, &row.UserAgent, &row.Metadata, &row.OccurredAt,
		); err != nil {
			return nil, fmt.Errorf("audit.postgres.scanUser row: %w", err)
		}
		result = append(result, row)
	}
	return result, rows.Err()
}

func (r *Repository) scanAll(ctx context.Context, q string, args ...any) ([]*audit.Row, error) {
	rows, err := r.db.Query(ctx, q, args...)
	if err != nil {
		return nil, fmt.Errorf("audit.postgres.scanAll: %w", err)
	}
	defer rows.Close()

	var result []*audit.Row
	for rows.Next() {
		row := &audit.Row{}
		if err := rows.Scan(
			&row.ID, &row.UserID, &row.DeviceID, &row.Event,
			&row.IPAddress, &row.UserAgent, &row.Metadata, &row.OccurredAt,
			&row.UserEmail, &row.UserDisplayName,
		); err != nil {
			return nil, fmt.Errorf("audit.postgres.scanAll row: %w", err)
		}
		result = append(result, row)
	}
	return result, rows.Err()
}
