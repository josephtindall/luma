package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/customrole"
)

// Repository implements customrole.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL custom role repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

// Create inserts a new custom role.
func (r *Repository) Create(ctx context.Context, name string, priority *int) (*customrole.CustomRole, error) {
	const q = `
		INSERT INTO auth.custom_roles (name, priority)
		VALUES ($1, $2)
		RETURNING id, name, priority, created_at, updated_at`
	var cr customrole.CustomRole
	err := r.db.QueryRow(ctx, q, name, priority).Scan(&cr.ID, &cr.Name, &cr.Priority, &cr.CreatedAt, &cr.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("customrole.postgres.Create: %w", err)
	}
	return &cr, nil
}

// Update renames a custom role and/or changes its priority.
func (r *Repository) Update(ctx context.Context, id, name string, priority *int) (*customrole.CustomRole, error) {
	const q = `
		UPDATE auth.custom_roles SET name=$2, priority=$3, updated_at=NOW()
		WHERE id=$1
		RETURNING id, name, priority, created_at, updated_at`
	var cr customrole.CustomRole
	err := r.db.QueryRow(ctx, q, id, name, priority).Scan(&cr.ID, &cr.Name, &cr.Priority, &cr.CreatedAt, &cr.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("custom role not found")
	}
	if err != nil {
		return nil, fmt.Errorf("customrole.postgres.Update: %w", err)
	}
	return &cr, nil
}

// Delete removes a custom role (permission + assignment rows cascade via FK).
func (r *Repository) Delete(ctx context.Context, id string) error {
	const q = `DELETE FROM auth.custom_roles WHERE id=$1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("customrole.postgres.Delete: %w", err)
	}
	return nil
}

// Get returns full role details including permissions and counts.
func (r *Repository) Get(ctx context.Context, id string) (*customrole.CustomRoleWithDetails, error) {
	const q = `
		SELECT cr.id, cr.name, cr.priority, cr.created_at, cr.updated_at,
		       COUNT(DISTINCT ucr.user_id) AS user_count,
		       COUNT(DISTINCT gcr.group_id) AS group_count
		FROM auth.custom_roles cr
		LEFT JOIN auth.user_custom_roles ucr ON ucr.role_id = cr.id
		LEFT JOIN auth.group_custom_roles gcr ON gcr.role_id = cr.id
		WHERE cr.id = $1
		GROUP BY cr.id`
	var cr customrole.CustomRoleWithDetails
	err := r.db.QueryRow(ctx, q, id).Scan(
		&cr.ID, &cr.Name, &cr.Priority, &cr.CreatedAt, &cr.UpdatedAt,
		&cr.UserCount, &cr.GroupCount,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("custom role not found")
	}
	if err != nil {
		return nil, fmt.Errorf("customrole.postgres.Get: %w", err)
	}

	perms, err := r.listPermissions(ctx, id)
	if err != nil {
		return nil, err
	}
	cr.Permissions = perms
	return &cr, nil
}

// List returns all custom roles with details.
func (r *Repository) List(ctx context.Context) ([]*customrole.CustomRoleWithDetails, error) {
	const q = `
		SELECT cr.id, cr.name, cr.priority, cr.created_at, cr.updated_at,
		       COUNT(DISTINCT ucr.user_id) AS user_count,
		       COUNT(DISTINCT gcr.group_id) AS group_count
		FROM auth.custom_roles cr
		LEFT JOIN auth.user_custom_roles ucr ON ucr.role_id = cr.id
		LEFT JOIN auth.group_custom_roles gcr ON gcr.role_id = cr.id
		GROUP BY cr.id
		ORDER BY cr.name`
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, fmt.Errorf("customrole.postgres.List: %w", err)
	}
	defer rows.Close()

	var roles []*customrole.CustomRoleWithDetails
	for rows.Next() {
		var cr customrole.CustomRoleWithDetails
		if err := rows.Scan(
			&cr.ID, &cr.Name, &cr.Priority, &cr.CreatedAt, &cr.UpdatedAt,
			&cr.UserCount, &cr.GroupCount,
		); err != nil {
			return nil, fmt.Errorf("customrole.postgres.List scan: %w", err)
		}
		roles = append(roles, &cr)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("customrole.postgres.List rows: %w", err)
	}

	for _, cr := range roles {
		perms, err := r.listPermissions(ctx, cr.ID)
		if err != nil {
			return nil, err
		}
		cr.Permissions = perms
	}
	return roles, nil
}

func (r *Repository) listPermissions(ctx context.Context, roleID string) ([]customrole.CustomRolePermission, error) {
	const q = `SELECT action, effect FROM auth.custom_role_permissions WHERE role_id=$1`
	rows, err := r.db.Query(ctx, q, roleID)
	if err != nil {
		return nil, fmt.Errorf("customrole.postgres.listPermissions: %w", err)
	}
	defer rows.Close()

	var perms []customrole.CustomRolePermission
	for rows.Next() {
		var p customrole.CustomRolePermission
		if err := rows.Scan(&p.Action, &p.Effect); err != nil {
			return nil, fmt.Errorf("customrole.postgres.listPermissions scan: %w", err)
		}
		perms = append(perms, p)
	}
	return perms, rows.Err()
}

// SetPermission upserts a permission on a role.
func (r *Repository) SetPermission(ctx context.Context, roleID, action, effect string) error {
	const q = `
		INSERT INTO auth.custom_role_permissions (role_id, action, effect)
		VALUES ($1, $2, $3)
		ON CONFLICT (role_id, action) DO UPDATE SET effect=EXCLUDED.effect`
	_, err := r.db.Exec(ctx, q, roleID, action, effect)
	if err != nil {
		return fmt.Errorf("customrole.postgres.SetPermission: %w", err)
	}
	return nil
}

// RemovePermission deletes a permission from a role.
func (r *Repository) RemovePermission(ctx context.Context, roleID, action string) error {
	const q = `DELETE FROM auth.custom_role_permissions WHERE role_id=$1 AND action=$2`
	_, err := r.db.Exec(ctx, q, roleID, action)
	if err != nil {
		return fmt.Errorf("customrole.postgres.RemovePermission: %w", err)
	}
	return nil
}

// AssignToUser assigns a custom role to a user.
func (r *Repository) AssignToUser(ctx context.Context, roleID, userID string) error {
	const q = `
		INSERT INTO auth.user_custom_roles (user_id, role_id)
		VALUES ($1, $2) ON CONFLICT DO NOTHING`
	_, err := r.db.Exec(ctx, q, userID, roleID)
	if err != nil {
		return fmt.Errorf("customrole.postgres.AssignToUser: %w", err)
	}
	return nil
}

// RemoveFromUser removes a custom role from a user.
func (r *Repository) RemoveFromUser(ctx context.Context, roleID, userID string) error {
	const q = `DELETE FROM auth.user_custom_roles WHERE user_id=$1 AND role_id=$2`
	_, err := r.db.Exec(ctx, q, userID, roleID)
	if err != nil {
		return fmt.Errorf("customrole.postgres.RemoveFromUser: %w", err)
	}
	return nil
}

// GetUserCustomRoles returns all custom roles directly assigned to a user.
func (r *Repository) GetUserCustomRoles(ctx context.Context, userID string) ([]*customrole.CustomRole, error) {
	const q = `
		SELECT cr.id, cr.name, cr.priority, cr.created_at, cr.updated_at
		FROM auth.custom_roles cr
		JOIN auth.user_custom_roles ucr ON ucr.role_id = cr.id
		WHERE ucr.user_id = $1
		ORDER BY cr.name`
	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("customrole.postgres.GetUserCustomRoles: %w", err)
	}
	defer rows.Close()

	var roles []*customrole.CustomRole
	for rows.Next() {
		var cr customrole.CustomRole
		if err := rows.Scan(&cr.ID, &cr.Name, &cr.Priority, &cr.CreatedAt, &cr.UpdatedAt); err != nil {
			return nil, fmt.Errorf("customrole.postgres.GetUserCustomRoles scan: %w", err)
		}
		roles = append(roles, &cr)
	}
	return roles, rows.Err()
}
