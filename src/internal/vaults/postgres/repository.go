package postgres

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/josephtindall/luma/internal/vaults"
	"github.com/josephtindall/luma/pkg/errors"
)

// Repository implements vaults.Repository using PostgreSQL.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a new PostgreSQL vaults repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) Create(ctx context.Context, vault *vaults.Vault) error {
	err := r.pool.QueryRow(ctx,
		`INSERT INTO luma.vaults (name, slug, type, owner_id, description, icon, color)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING id, created_at, updated_at`,
		vault.Name, vault.Slug, vault.Type, vault.OwnerID,
		vault.Description, vault.Icon, vault.Color,
	).Scan(&vault.ID, &vault.CreatedAt, &vault.UpdatedAt)
	if err != nil {
		return fmt.Errorf("inserting vault: %w", err)
	}
	return nil
}

func (r *Repository) GetByID(ctx context.Context, id string) (*vaults.Vault, error) {
	v := &vaults.Vault{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, name, slug, type, owner_id, description, icon, color,
		        is_archived, archived_at, archived_by, created_at, updated_at
		 FROM luma.vaults WHERE id = $1`, id,
	).Scan(
		&v.ID, &v.Name, &v.Slug, &v.Type, &v.OwnerID,
		&v.Description, &v.Icon, &v.Color,
		&v.IsArchived, &v.ArchivedAt, &v.ArchivedBy,
		&v.CreatedAt, &v.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("vault %s: %w", id, errors.ErrNotFound)
		}
		return nil, fmt.Errorf("querying vault: %w", err)
	}
	return v, nil
}

func (r *Repository) ListByUser(ctx context.Context, userID string, includeArchived bool) ([]*vaults.Vault, error) {
	query := `SELECT v.id, v.name, v.slug, v.type, v.owner_id, v.description, v.icon, v.color,
	                 v.is_archived, v.archived_at, v.archived_by, v.created_at, v.updated_at
	          FROM luma.vaults v
	          JOIN luma.vault_members vm ON vm.vault_id = v.id
	          WHERE vm.user_id = $1`
	if !includeArchived {
		query += ` AND v.is_archived = false`
	}
	query += ` ORDER BY v.updated_at DESC`

	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, fmt.Errorf("querying user vaults: %w", err)
	}
	defer rows.Close()

	var result []*vaults.Vault
	for rows.Next() {
		v := &vaults.Vault{}
		if err := rows.Scan(
			&v.ID, &v.Name, &v.Slug, &v.Type, &v.OwnerID,
			&v.Description, &v.Icon, &v.Color,
			&v.IsArchived, &v.ArchivedAt, &v.ArchivedBy,
			&v.CreatedAt, &v.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scanning vault row: %w", err)
		}
		result = append(result, v)
	}
	return result, rows.Err()
}

func (r *Repository) Update(ctx context.Context, vault *vaults.Vault) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE luma.vaults
		 SET name = $2, description = $3, icon = $4, color = $5, updated_at = $6
		 WHERE id = $1`,
		vault.ID, vault.Name, vault.Description, vault.Icon, vault.Color, vault.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("updating vault: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("vault %s: %w", vault.ID, errors.ErrNotFound)
	}
	return nil
}

func (r *Repository) Archive(ctx context.Context, id string, archivedBy string) error {
	now := time.Now()
	tag, err := r.pool.Exec(ctx,
		`UPDATE luma.vaults
		 SET is_archived = true, archived_at = $2, archived_by = $3, updated_at = $2
		 WHERE id = $1 AND is_archived = false`,
		id, now, archivedBy,
	)
	if err != nil {
		return fmt.Errorf("archiving vault: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("vault %s: %w", id, errors.ErrNotFound)
	}
	return nil
}

func (r *Repository) AddMember(ctx context.Context, member *vaults.VaultMember) error {
	_, err := r.pool.Exec(ctx,
		`INSERT INTO luma.vault_members (vault_id, user_id, role_id, added_by)
		 VALUES ($1, $2, $3, $4)`,
		member.VaultID, member.UserID, member.RoleID, member.AddedBy,
	)
	if err != nil {
		return fmt.Errorf("inserting vault member: %w", err)
	}
	return nil
}

func (r *Repository) RemoveMember(ctx context.Context, vaultID, userID string) error {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM luma.vault_members WHERE vault_id = $1 AND user_id = $2`,
		vaultID, userID,
	)
	if err != nil {
		return fmt.Errorf("removing vault member: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("member %s in vault %s: %w", userID, vaultID, errors.ErrNotFound)
	}
	return nil
}

func (r *Repository) UpdateMemberRole(ctx context.Context, vaultID, userID, roleID string) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE luma.vault_members SET role_id = $3 WHERE vault_id = $1 AND user_id = $2`,
		vaultID, userID, roleID,
	)
	if err != nil {
		return fmt.Errorf("updating member role: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("member %s in vault %s: %w", userID, vaultID, errors.ErrNotFound)
	}
	return nil
}

func (r *Repository) ListMembers(ctx context.Context, vaultID string) ([]*vaults.VaultMember, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT vault_id, user_id, role_id, added_by, added_at
		 FROM luma.vault_members WHERE vault_id = $1 ORDER BY added_at`,
		vaultID,
	)
	if err != nil {
		return nil, fmt.Errorf("querying vault members: %w", err)
	}
	defer rows.Close()

	var result []*vaults.VaultMember
	for rows.Next() {
		m := &vaults.VaultMember{}
		if err := rows.Scan(&m.VaultID, &m.UserID, &m.RoleID, &m.AddedBy, &m.AddedAt); err != nil {
			return nil, fmt.Errorf("scanning member row: %w", err)
		}
		result = append(result, m)
	}
	return result, rows.Err()
}

func (r *Repository) GetMember(ctx context.Context, vaultID, userID string) (*vaults.VaultMember, error) {
	m := &vaults.VaultMember{}
	err := r.pool.QueryRow(ctx,
		`SELECT vault_id, user_id, role_id, added_by, added_at
		 FROM luma.vault_members WHERE vault_id = $1 AND user_id = $2`,
		vaultID, userID,
	).Scan(&m.VaultID, &m.UserID, &m.RoleID, &m.AddedBy, &m.AddedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("member %s in vault %s: %w", userID, vaultID, errors.ErrNotFound)
		}
		return nil, fmt.Errorf("querying vault member: %w", err)
	}
	return m, nil
}

func (r *Repository) HasPersonalVault(ctx context.Context, userID string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM luma.vaults WHERE owner_id = $1 AND type = 'personal')`,
		userID,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("checking personal vault: %w", err)
	}
	return exists, nil
}

func (r *Repository) CountAdmins(ctx context.Context, vaultID string) (int, error) {
	var count int
	err := r.pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM luma.vault_members
		 WHERE vault_id = $1 AND role_id = 'builtin:vault-admin'`,
		vaultID,
	).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("counting admins: %w", err)
	}
	return count, nil
}
