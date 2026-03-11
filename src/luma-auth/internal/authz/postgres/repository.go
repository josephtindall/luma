package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/josephtindall/luma-auth/internal/authz"
)

// Repository implements authz.Repository against PostgreSQL.
type Repository struct {
	db    *pgxpool.Pool
	cache *redis.Client
}

// New constructs the PostgreSQL authz repository.
func New(db *pgxpool.Pool, cache *redis.Client) *Repository {
	return &Repository{db: db, cache: cache}
}

// GetInstanceRole returns ordered policy statements for the user's instance role.
func (r *Repository) GetInstanceRole(ctx context.Context, userID string) ([]authz.PolicyStatement, error) {
	const q = `
		SELECT ps.effect, ps.actions, ps.resource_types
		FROM auth.users u
		JOIN auth.roles ro ON u.instance_role_id = ro.id
		JOIN auth.role_policies rp ON ro.id = rp.role_id
		JOIN auth.policy_statements ps ON rp.policy_id = ps.policy_id
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
		FROM auth.resource_permissions
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
		FROM auth.instance
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

// IsOwner returns true if the user holds the instance-owner role.
func (r *Repository) IsOwner(ctx context.Context, userID string) (bool, error) {
	const q = `
		SELECT EXISTS(
			SELECT 1 FROM auth.users WHERE id=$1 AND instance_role_id='builtin:instance-owner'
		)`
	var isOwner bool
	err := r.db.QueryRow(ctx, q, userID).Scan(&isOwner)
	if err != nil {
		return false, fmt.Errorf("authz.postgres.IsOwner: %w", err)
	}
	return isOwner, nil
}

// GetCustomRolePermissionsForUser returns all custom-role permission rows for the
// given user and action, including permissions inherited through group membership at
// all nesting depths. IsCascaded is true for depth > 0.
func (r *Repository) GetCustomRolePermissionsForUser(ctx context.Context, userID, action string) ([]authz.CustomRolePerm, error) {
	const q = `
		WITH RECURSIVE user_groups(group_id, depth) AS (
			SELECT group_id, 0
			FROM auth.group_members
			WHERE member_type = 'user' AND member_id = $1
			UNION ALL
			SELECT gm.group_id, ug.depth + 1
			FROM auth.group_members gm
			JOIN user_groups ug ON gm.member_id = ug.group_id AND gm.member_type = 'group'
		)
		-- Group-assigned permissions
		SELECT cr.priority, crp.effect, (ug.depth > 0) AS is_cascaded
		FROM user_groups ug
		JOIN auth.group_custom_roles gcr ON gcr.group_id = ug.group_id
		JOIN auth.custom_roles cr ON cr.id = gcr.role_id
		JOIN auth.custom_role_permissions crp ON crp.role_id = cr.id AND crp.action = $2
		UNION ALL
		-- Directly assigned permissions
		SELECT cr.priority, crp.effect, false
		FROM auth.user_custom_roles ucr
		JOIN auth.custom_roles cr ON cr.id = ucr.role_id
		JOIN auth.custom_role_permissions crp ON crp.role_id = cr.id AND crp.action = $2
		WHERE ucr.user_id = $1`

	rows, err := r.db.Query(ctx, q, userID, action)
	if err != nil {
		return nil, fmt.Errorf("authz.postgres.GetCustomRolePermissionsForUser: %w", err)
	}
	defer rows.Close()

	var perms []authz.CustomRolePerm
	for rows.Next() {
		var p authz.CustomRolePerm
		if err := rows.Scan(&p.Priority, &p.Effect, &p.IsCascaded); err != nil {
			return nil, fmt.Errorf("authz.postgres.GetCustomRolePermissionsForUser scan: %w", err)
		}
		perms = append(perms, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("authz.postgres.GetCustomRolePermissionsForUser rows: %w", err)
	}
	return perms, nil
}

// InvalidateUserCache removes all cached authz results for a user.
func (r *Repository) InvalidateUserCache(ctx context.Context, userID string) error {
	if r.cache == nil {
		return nil
	}
	pattern := fmt.Sprintf("authz:%s:*", userID)
	var cursor uint64
	for {
		keys, nextCursor, err := r.cache.Scan(ctx, cursor, pattern, 100).Result()
		if err != nil {
			return fmt.Errorf("authz.postgres.InvalidateUserCache scan: %w", err)
		}
		if len(keys) > 0 {
			if err := r.cache.Del(ctx, keys...).Err(); err != nil {
				return fmt.Errorf("authz.postgres.InvalidateUserCache del: %w", err)
			}
		}
		cursor = nextCursor
		if cursor == 0 {
			break
		}
	}
	return nil
}
