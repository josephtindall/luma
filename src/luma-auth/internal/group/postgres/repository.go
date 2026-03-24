package postgres

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/group"
)

// Repository implements group.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL group repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

// Create inserts a new group.
func (r *Repository) Create(ctx context.Context, name string, description *string) (*group.Group, error) {
	const q = `
		INSERT INTO auth.groups (name, description)
		VALUES ($1, $2)
		RETURNING id, name, description, is_system, no_member_control, hide_from_search, created_at, updated_at`
	var g group.Group
	err := r.db.QueryRow(ctx, q, name, description).Scan(&g.ID, &g.Name, &g.Description, &g.IsSystem, &g.NoMemberControl, &g.HideFromSearch, &g.CreatedAt, &g.UpdatedAt)
	if err != nil {
		return nil, fmt.Errorf("group.postgres.Create: %w", err)
	}
	return &g, nil
}

// Rename updates a group's name and optional description.
func (r *Repository) Rename(ctx context.Context, id, name string, description *string) (*group.Group, error) {
	const q = `
		UPDATE auth.groups SET name = $2, description = $3, updated_at = NOW()
		WHERE id = $1
		RETURNING id, name, description, is_system, no_member_control, hide_from_search, created_at, updated_at`
	var g group.Group
	err := r.db.QueryRow(ctx, q, id, name, description).Scan(&g.ID, &g.Name, &g.Description, &g.IsSystem, &g.NoMemberControl, &g.HideFromSearch, &g.CreatedAt, &g.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("group not found")
	}
	if err != nil {
		return nil, fmt.Errorf("group.postgres.Rename: %w", err)
	}
	return &g, nil
}

// Delete removes a group (members cascade via FK).
func (r *Repository) Delete(ctx context.Context, id string) error {
	const q = `DELETE FROM auth.groups WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("group.postgres.Delete: %w", err)
	}
	return nil
}

// Get returns full group details including members and role IDs.
func (r *Repository) Get(ctx context.Context, id string) (*group.GroupWithDetails, error) {
	const q = `
		SELECT id, name, description, is_system, no_member_control, hide_from_search, created_at, updated_at
		FROM auth.groups WHERE id = $1`
	var g group.GroupWithDetails
	err := r.db.QueryRow(ctx, q, id).Scan(&g.ID, &g.Name, &g.Description, &g.IsSystem, &g.NoMemberControl, &g.HideFromSearch, &g.CreatedAt, &g.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, fmt.Errorf("group not found")
	}
	if err != nil {
		return nil, fmt.Errorf("group.postgres.Get: %w", err)
	}

	members, err := r.listMembers(ctx, id)
	if err != nil {
		return nil, err
	}
	g.Members = members
	g.MemberCount = len(members)

	roleIDs, err := r.listRoleIDs(ctx, id)
	if err != nil {
		return nil, err
	}
	g.RoleIDs = roleIDs
	return &g, nil
}

// List returns all groups with details.
func (r *Repository) List(ctx context.Context) ([]*group.GroupWithDetails, error) {
	const q = `SELECT id, name, description, is_system, no_member_control, hide_from_search, created_at, updated_at FROM auth.groups ORDER BY name`
	rows, err := r.db.Query(ctx, q)
	if err != nil {
		return nil, fmt.Errorf("group.postgres.List: %w", err)
	}
	defer rows.Close()

	var groups []*group.GroupWithDetails
	for rows.Next() {
		var g group.GroupWithDetails
		if err := rows.Scan(&g.ID, &g.Name, &g.Description, &g.IsSystem, &g.NoMemberControl, &g.HideFromSearch, &g.CreatedAt, &g.UpdatedAt); err != nil {
			return nil, fmt.Errorf("group.postgres.List scan: %w", err)
		}
		groups = append(groups, &g)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("group.postgres.List rows: %w", err)
	}

	for _, g := range groups {
		members, err := r.listMembers(ctx, g.ID)
		if err != nil {
			return nil, err
		}
		g.Members = members
		g.MemberCount = len(members)

		roleIDs, err := r.listRoleIDs(ctx, g.ID)
		if err != nil {
			return nil, err
		}
		g.RoleIDs = roleIDs
	}
	return groups, nil
}

// SearchDirectory returns non-hidden groups whose name contains the query (case-insensitive).
func (r *Repository) SearchDirectory(ctx context.Context, query string) ([]*group.Group, error) {
	const q = `
		SELECT id, name, description, is_system, no_member_control, hide_from_search, created_at, updated_at
		FROM auth.groups
		WHERE hide_from_search = false
		  AND name ILIKE '%' || $1 || '%'
		ORDER BY name
		LIMIT 50`

	rows, err := r.db.Query(ctx, q, query)
	if err != nil {
		return nil, fmt.Errorf("group.postgres.SearchDirectory: %w", err)
	}
	defer rows.Close()

	var out []*group.Group
	for rows.Next() {
		g := &group.Group{}
		if err := rows.Scan(&g.ID, &g.Name, &g.Description, &g.IsSystem, &g.NoMemberControl, &g.HideFromSearch, &g.CreatedAt, &g.UpdatedAt); err != nil {
			return nil, fmt.Errorf("group.postgres.SearchDirectory scan: %w", err)
		}
		out = append(out, g)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("group.postgres.SearchDirectory rows: %w", err)
	}
	return out, nil
}

// SetHideFromSearch sets or clears the hide_from_search flag for a group.
func (r *Repository) SetHideFromSearch(ctx context.Context, id string, hide bool) error {
	const q = `UPDATE auth.groups SET hide_from_search = $2, updated_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id, hide)
	if err != nil {
		return fmt.Errorf("group.postgres.SetHideFromSearch: %w", err)
	}
	return nil
}

func (r *Repository) listMembers(ctx context.Context, groupID string) ([]group.GroupMember, error) {
	const q = `SELECT member_type, member_id, added_at FROM auth.group_members WHERE group_id = $1`
	rows, err := r.db.Query(ctx, q, groupID)
	if err != nil {
		return nil, fmt.Errorf("group.postgres.listMembers: %w", err)
	}
	defer rows.Close()

	var members []group.GroupMember
	for rows.Next() {
		var m group.GroupMember
		if err := rows.Scan(&m.MemberType, &m.MemberID, &m.AddedAt); err != nil {
			return nil, fmt.Errorf("group.postgres.listMembers scan: %w", err)
		}
		members = append(members, m)
	}
	return members, rows.Err()
}

func (r *Repository) listRoleIDs(ctx context.Context, groupID string) ([]string, error) {
	const q = `SELECT role_id FROM auth.group_custom_roles WHERE group_id = $1`
	rows, err := r.db.Query(ctx, q, groupID)
	if err != nil {
		return nil, fmt.Errorf("group.postgres.listRoleIDs: %w", err)
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("group.postgres.listRoleIDs scan: %w", err)
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// AddMember inserts a group member row.
func (r *Repository) AddMember(ctx context.Context, groupID, memberType, memberID string) error {
	const q = `
		INSERT INTO auth.group_members (group_id, member_type, member_id)
		VALUES ($1, $2, $3)
		ON CONFLICT DO NOTHING`
	_, err := r.db.Exec(ctx, q, groupID, memberType, memberID)
	if err != nil {
		return fmt.Errorf("group.postgres.AddMember: %w", err)
	}
	return nil
}

// RemoveMember deletes a group member row.
func (r *Repository) RemoveMember(ctx context.Context, groupID, memberType, memberID string) error {
	const q = `DELETE FROM auth.group_members WHERE group_id=$1 AND member_type=$2 AND member_id=$3`
	_, err := r.db.Exec(ctx, q, groupID, memberType, memberID)
	if err != nil {
		return fmt.Errorf("group.postgres.RemoveMember: %w", err)
	}
	return nil
}

// WouldCycle checks if adding candidateChildID as a member of parentGroupID would create a cycle.
// Uses a recursive CTE to walk all ancestors of parentGroupID.
func (r *Repository) WouldCycle(ctx context.Context, parentGroupID, candidateChildID string) (bool, error) {
	// If they are the same group, trivially a cycle.
	if parentGroupID == candidateChildID {
		return true, nil
	}
	const q = `
		WITH RECURSIVE ancestors(group_id) AS (
			SELECT group_id FROM auth.group_members
			WHERE member_type = 'group' AND member_id = $1
			UNION ALL
			SELECT gm.group_id FROM auth.group_members gm
			JOIN ancestors a ON gm.member_id = a.group_id AND gm.member_type = 'group'
		)
		SELECT EXISTS(SELECT 1 FROM ancestors WHERE group_id = $2)`
	var cycle bool
	err := r.db.QueryRow(ctx, q, parentGroupID, candidateChildID).Scan(&cycle)
	if err != nil {
		return false, fmt.Errorf("group.postgres.WouldCycle: %w", err)
	}
	return cycle, nil
}

// GetUserGroupIDs returns all group IDs the user belongs to (direct and
// inherited through nested group membership at any depth).
func (r *Repository) GetUserGroupIDs(ctx context.Context, userID string) ([]string, error) {
	const q = `
		WITH RECURSIVE user_groups(group_id) AS (
			SELECT group_id
			FROM auth.group_members
			WHERE member_type = 'user' AND member_id = $1
			UNION ALL
			SELECT gm.group_id
			FROM auth.group_members gm
			JOIN user_groups ug ON gm.member_id = ug.group_id AND gm.member_type = 'group'
		)
		SELECT DISTINCT group_id::text FROM user_groups`

	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("group.postgres.GetUserGroupIDs: %w", err)
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("group.postgres.GetUserGroupIDs scan: %w", err)
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("group.postgres.GetUserGroupIDs rows: %w", err)
	}
	return ids, nil
}

// AssignRole assigns a custom role to a group.
func (r *Repository) AssignRole(ctx context.Context, groupID, roleID string) error {
	const q = `
		INSERT INTO auth.group_custom_roles (group_id, role_id)
		VALUES ($1, $2) ON CONFLICT DO NOTHING`
	_, err := r.db.Exec(ctx, q, groupID, roleID)
	if err != nil {
		return fmt.Errorf("group.postgres.AssignRole: %w", err)
	}
	return nil
}

// RemoveRole removes a custom role from a group.
func (r *Repository) RemoveRole(ctx context.Context, groupID, roleID string) error {
	const q = `DELETE FROM auth.group_custom_roles WHERE group_id=$1 AND role_id=$2`
	_, err := r.db.Exec(ctx, q, groupID, roleID)
	if err != nil {
		return fmt.Errorf("group.postgres.RemoveRole: %w", err)
	}
	return nil
}
