package postgres

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/preferences"
)

// Repository implements preferences.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL preferences repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) Get(ctx context.Context, userID string) (*preferences.Preferences, error) {
	const q = `
		SELECT user_id, theme, language, timezone, date_format, time_format,
		       notify_on_login, notify_on_revoke, compact_mode, updated_at
		FROM auth.user_preferences
		WHERE user_id = $1`

	p := &preferences.Preferences{}
	err := r.db.QueryRow(ctx, q, userID).Scan(
		&p.UserID, &p.Theme, &p.Language, &p.Timezone,
		&p.DateFormat, &p.TimeFormat,
		&p.NotifyOnLogin, &p.NotifyOnRevoke, &p.CompactMode,
		&p.UpdatedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("preferences.postgres.Get: %w", err)
	}
	return p, nil
}

func (r *Repository) Update(ctx context.Context, userID string, params preferences.UpdateParams) error {
	// Build a partial update using COALESCE — only overwrite non-nil fields.
	const q = `
		UPDATE auth.user_preferences SET
		    theme           = COALESCE($2, theme),
		    language        = COALESCE($3, language),
		    timezone        = COALESCE($4, timezone),
		    date_format     = COALESCE($5, date_format),
		    time_format     = COALESCE($6, time_format),
		    notify_on_login  = COALESCE($7, notify_on_login),
		    notify_on_revoke = COALESCE($8, notify_on_revoke),
		    compact_mode     = COALESCE($9, compact_mode),
		    updated_at       = NOW()
		WHERE user_id = $1`

	_, err := r.db.Exec(ctx, q,
		userID,
		params.Theme,
		params.Language,
		params.Timezone,
		params.DateFormat,
		params.TimeFormat,
		params.NotifyOnLogin,
		params.NotifyOnRevoke,
		params.CompactMode,
	)
	if err != nil {
		return fmt.Errorf("preferences.postgres.Update: %w", err)
	}
	return nil
}
