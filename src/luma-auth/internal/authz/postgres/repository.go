package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/authz"
)

// Repository implements authz.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL authz repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

// GetInstanceRole returns ordered policy statements for the user's instance role.
func (r *Repository) GetInstanceRole(ctx context.Context, userID string) ([]authz.PolicyStatement, error) {
	const q = `
		SELECT ps.effect, ps.actions, ps.resource_types
		FROM haven.users u
		JOIN haven.roles ro ON u.instance_role_id = ro.id
		JOIN haven.role_policies rp ON ro.id = rp.role_id
		JOIN haven.policy_statements ps ON rp.policy_id = ps.policy_id
		WHERE u.id = $1
		ORDER BY ps.position`

	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("authz.postgres.GetInstanceRole: %w", err)
	}
	defer rows.Close()

	var stmts []authz.PolicyStatement
	for rows.Next() {
		var s authz.PolicyStatement
		if err := rows.Scan(&s.Effect, &s.Actions, &s.ResourceTypes); err != nil {
			return nil, fmt.Errorf("authz.postgres.GetInstanceRole scan: %w", err)
		}
		stmts = append(stmts, s)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("authz.postgres.GetInstanceRole rows: %w", err)
	}
	return stmts, nil
}

// GetVaultRole returns policy statements for the user's role in a vault.
// Not yet implemented (no vault_members table) — always returns nil.
func (r *Repository) GetVaultRole(ctx context.Context, userID, vaultID string) ([]authz.PolicyStatement, error) {
	return nil, nil
}

// GetResourcePermission returns an explicit allow/deny for the user on a
// specific resource, or nil if no such record exists.
func (r *Repository) GetResourcePermission(ctx context.Context, userID, resourceType, resourceID string) (*authz.ResourcePermission, error) {
	const q = `
		SELECT effect, actions
		FROM haven.resource_permissions
		WHERE subject_type = 'user'
		  AND subject_id   = $1
		  AND resource_type = $2
		  AND resource_id   = $3
		  AND (expires_at IS NULL OR expires_at > NOW())
		LIMIT 1`

	var rp authz.ResourcePermission
	err := r.db.QueryRow(ctx, q, userID, resourceType, resourceID).Scan(&rp.Effect, &rp.Actions)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("authz.postgres.GetResourcePermission: %w", err)
	}
	return &rp, nil
}

// IsFeatureEnabled returns whether the named feature is enabled on the instance.
// Absent keys are treated as enabled (COALESCE to true).
func (r *Repository) IsFeatureEnabled(ctx context.Context, feature string) (bool, error) {
	const q = `
		SELECT COALESCE((features->>$1)::boolean, true)
		FROM haven.instance
		LIMIT 1`

	var enabled bool
	err := r.db.QueryRow(ctx, q, feature).Scan(&enabled)
	if errors.Is(err, pgx.ErrNoRows) {
		return true, nil
	}
	if err != nil {
		return true, fmt.Errorf("authz.postgres.IsFeatureEnabled: %w", err)
	}
	return enabled, nil
}
