package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/device"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// Repository implements device.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL device repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) GetByID(ctx context.Context, id string) (*device.Device, error) {
	const q = `
		SELECT id, user_id, name, platform, fingerprint,
		       COALESCE(user_agent, ''), last_seen_at, revoked_at, created_at
		FROM haven.devices
		WHERE id = $1`

	d, err := scanDevice(r.db.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, pkgerrors.ErrDeviceNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("device.postgres.GetByID: %w", err)
	}
	return d, nil
}

func (r *Repository) GetByFingerprint(ctx context.Context, userID, fingerprint string) (*device.Device, error) {
	const q = `
		SELECT id, user_id, name, platform, fingerprint,
		       COALESCE(user_agent, ''), last_seen_at, revoked_at, created_at
		FROM haven.devices
		WHERE user_id = $1 AND fingerprint = $2`

	d, err := scanDevice(r.db.QueryRow(ctx, q, userID, fingerprint))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil // not found is not an error here
	}
	if err != nil {
		return nil, fmt.Errorf("device.postgres.GetByFingerprint: %w", err)
	}
	return d, nil
}

func (r *Repository) ListForUser(ctx context.Context, userID string) ([]*device.Device, error) {
	const q = `
		SELECT id, user_id, name, platform, fingerprint,
		       COALESCE(user_agent, ''), last_seen_at, revoked_at, created_at
		FROM haven.devices
		WHERE user_id = $1 AND revoked_at IS NULL
		ORDER BY created_at DESC`

	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("device.postgres.ListForUser: %w", err)
	}
	defer rows.Close()

	var devices []*device.Device
	for rows.Next() {
		d, err := scanDevice(rows)
		if err != nil {
			return nil, fmt.Errorf("device.postgres.ListForUser scan: %w", err)
		}
		devices = append(devices, d)
	}
	return devices, rows.Err()
}

func (r *Repository) Create(ctx context.Context, params device.RegisterParams) (*device.Device, error) {
	const q = `
		INSERT INTO haven.devices (user_id, name, platform, fingerprint, user_agent)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, user_id, name, platform, fingerprint, user_agent,
		          last_seen_at, revoked_at, created_at`

	d, err := scanDevice(r.db.QueryRow(ctx, q,
		params.UserID, params.Name, params.Platform, params.Fingerprint, params.UserAgent))
	if err != nil {
		return nil, fmt.Errorf("device.postgres.Create: %w", err)
	}
	return d, nil
}

func (r *Repository) UpdateLastSeen(ctx context.Context, id string) error {
	const q = `UPDATE haven.devices SET last_seen_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("device.postgres.UpdateLastSeen: %w", err)
	}
	return nil
}

func (r *Repository) Revoke(ctx context.Context, id string) error {
	const q = `UPDATE haven.devices SET revoked_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("device.postgres.Revoke: %w", err)
	}
	return nil
}

func scanDevice(row pgx.Row) (*device.Device, error) {
	d := &device.Device{}
	var platform string
	err := row.Scan(
		&d.ID,
		&d.UserID,
		&d.Name,
		&platform,
		&d.Fingerprint,
		&d.UserAgent,
		&d.LastSeenAt,
		&d.RevokedAt,
		&d.CreatedAt,
	)
	d.Platform = device.Platform(platform)
	return d, err
}
