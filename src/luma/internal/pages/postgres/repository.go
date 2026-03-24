package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma/internal/pages"
	lumaerrors "github.com/josephtindall/luma/pkg/errors"
	"github.com/josephtindall/luma/pkg/shortid"
)

const maxShortIDAttempts = 3

// Repository implements pages.Repository using PostgreSQL.
type Repository struct {
	pool *pgxpool.Pool
}

// NewRepository creates a new PostgreSQL pages repository.
func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

func (r *Repository) CreateWithShortID(ctx context.Context, page *pages.Page) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("beginning transaction: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	// Generate the UUID ahead of time so we can insert it into short_ids
	// before the pages row is created.
	var pageID string
	if err := tx.QueryRow(ctx, `SELECT gen_random_uuid()::text`).Scan(&pageID); err != nil {
		return fmt.Errorf("generating uuid: %w", err)
	}

	// Attempt short ID allocation — retry on collision.
	var sid string
	for i := 0; i < maxShortIDAttempts; i++ {
		sid, err = shortid.Generate()
		if err != nil {
			return fmt.Errorf("generating short id: %w", err)
		}
		_, insertErr := tx.Exec(ctx,
			`INSERT INTO luma.short_ids (short_id, resource_type, resource_id) VALUES ($1, 'page', $2)`,
			sid, pageID,
		)
		if insertErr == nil {
			break
		}
		if isUniqueViolation(insertErr) && i < maxShortIDAttempts-1 {
			continue
		}
		return fmt.Errorf("inserting short id: %w", insertErr)
	}
	if sid == "" {
		return lumaerrors.ErrShortIDExhausted
	}

	err = tx.QueryRow(ctx,
		`INSERT INTO luma.pages
		    (id, short_id, vault_id, title, content, created_by, updated_by)
		 VALUES ($1, $2, $3, $4, $5, $6, $7)
		 RETURNING created_at, updated_at`,
		pageID, sid, page.VaultID, page.Title, page.Content,
		page.CreatedBy, page.UpdatedBy,
	).Scan(&page.CreatedAt, &page.UpdatedAt)
	if err != nil {
		return fmt.Errorf("inserting page: %w", err)
	}

	page.ID = pageID
	page.ShortID = sid

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("committing transaction: %w", err)
	}
	return nil
}

func (r *Repository) GetByShortID(ctx context.Context, shortID string) (*pages.Page, error) {
	p := &pages.Page{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, short_id, vault_id, title, content, created_by, updated_by,
		        is_archived, archived_at, archived_by, created_at, updated_at
		 FROM luma.pages WHERE short_id = $1`,
		shortID,
	).Scan(
		&p.ID, &p.ShortID, &p.VaultID, &p.Title, &p.Content,
		&p.CreatedBy, &p.UpdatedBy,
		&p.IsArchived, &p.ArchivedAt, &p.ArchivedBy,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("page %s: %w", shortID, lumaerrors.ErrNotFound)
		}
		return nil, fmt.Errorf("querying page: %w", err)
	}
	return p, nil
}

func (r *Repository) GetByID(ctx context.Context, id string) (*pages.Page, error) {
	p := &pages.Page{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, short_id, vault_id, title, content, created_by, updated_by,
		        is_archived, archived_at, archived_by, created_at, updated_at
		 FROM luma.pages WHERE id = $1`,
		id,
	).Scan(
		&p.ID, &p.ShortID, &p.VaultID, &p.Title, &p.Content,
		&p.CreatedBy, &p.UpdatedBy,
		&p.IsArchived, &p.ArchivedAt, &p.ArchivedBy,
		&p.CreatedAt, &p.UpdatedAt,
	)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("page %s: %w", id, lumaerrors.ErrNotFound)
		}
		return nil, fmt.Errorf("querying page by id: %w", err)
	}
	return p, nil
}

func (r *Repository) ListByVault(ctx context.Context, vaultID string, includeArchived bool) ([]*pages.Page, error) {
	query := `SELECT id, short_id, vault_id, title, content, created_by, updated_by,
	                 is_archived, archived_at, archived_by, created_at, updated_at
	          FROM luma.pages WHERE vault_id = $1`
	if !includeArchived {
		query += ` AND is_archived = false`
	}
	query += ` ORDER BY updated_at DESC`

	rows, err := r.pool.Query(ctx, query, vaultID)
	if err != nil {
		return nil, fmt.Errorf("querying vault pages: %w", err)
	}
	defer rows.Close()

	var result []*pages.Page
	for rows.Next() {
		p := &pages.Page{}
		if err := rows.Scan(
			&p.ID, &p.ShortID, &p.VaultID, &p.Title, &p.Content,
			&p.CreatedBy, &p.UpdatedBy,
			&p.IsArchived, &p.ArchivedAt, &p.ArchivedBy,
			&p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scanning page row: %w", err)
		}
		result = append(result, p)
	}
	return result, rows.Err()
}

func (r *Repository) Update(ctx context.Context, page *pages.Page) error {
	tag, err := r.pool.Exec(ctx,
		`UPDATE luma.pages
		 SET title = $2, updated_by = $3, updated_at = $4
		 WHERE id = $1 AND is_archived = false`,
		page.ID, page.Title, page.UpdatedBy, page.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("updating page: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("page %s: %w", page.ID, lumaerrors.ErrNotFound)
	}
	return nil
}

func (r *Repository) UpdateWithRefs(ctx context.Context, page *pages.Page, sourcePageIDs []string) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("beginning transaction: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	tag, err := tx.Exec(ctx,
		`UPDATE luma.pages
		 SET title = $2, content = $3, updated_by = $4, updated_at = $5
		 WHERE id = $1 AND is_archived = false`,
		page.ID, page.Title, page.Content, page.UpdatedBy, page.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("updating page content: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("page %s: %w", page.ID, lumaerrors.ErrNotFound)
	}

	if _, err := tx.Exec(ctx,
		`DELETE FROM luma.transclusion_refs WHERE containing_page_id = $1`,
		page.ID,
	); err != nil {
		return fmt.Errorf("clearing transclusion refs: %w", err)
	}

	for _, sourceID := range sourcePageIDs {
		if _, err := tx.Exec(ctx,
			`INSERT INTO luma.transclusion_refs (containing_page_id, source_page_id)
			 VALUES ($1, $2) ON CONFLICT DO NOTHING`,
			page.ID, sourceID,
		); err != nil {
			return fmt.Errorf("inserting transclusion ref: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("committing transaction: %w", err)
	}
	return nil
}

func (r *Repository) Archive(ctx context.Context, id, archivedBy string) error {
	now := time.Now()
	tag, err := r.pool.Exec(ctx,
		`UPDATE luma.pages
		 SET is_archived = true, archived_at = $2, archived_by = $3, updated_at = $2
		 WHERE id = $1 AND is_archived = false`,
		id, now, archivedBy,
	)
	if err != nil {
		return fmt.Errorf("archiving page: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return fmt.Errorf("page %s: %w", id, lumaerrors.ErrNotFound)
	}
	return nil
}

func (r *Repository) CreateRevision(ctx context.Context, rev *pages.PageRevision) error {
	err := r.pool.QueryRow(ctx,
		`INSERT INTO luma.page_revisions (page_id, content, created_by, is_manual, label)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING id, created_at`,
		rev.PageID, rev.Content, rev.CreatedBy, rev.IsManual, rev.Label,
	).Scan(&rev.ID, &rev.CreatedAt)
	if err != nil {
		return fmt.Errorf("inserting page revision: %w", err)
	}
	return nil
}

func (r *Repository) GetRevision(ctx context.Context, revID string) (*pages.PageRevision, error) {
	rev := &pages.PageRevision{}
	err := r.pool.QueryRow(ctx,
		`SELECT id, page_id, content, created_by, created_at, is_manual, label
		 FROM luma.page_revisions WHERE id = $1`,
		revID,
	).Scan(&rev.ID, &rev.PageID, &rev.Content, &rev.CreatedBy, &rev.CreatedAt, &rev.IsManual, &rev.Label)
	if err != nil {
		if err == pgx.ErrNoRows {
			return nil, fmt.Errorf("revision %s: %w", revID, lumaerrors.ErrNotFound)
		}
		return nil, fmt.Errorf("querying revision: %w", err)
	}
	return rev, nil
}

func (r *Repository) ListRevisions(ctx context.Context, pageID string) ([]*pages.PageRevision, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, page_id, created_by, created_at, is_manual, label
		 FROM luma.page_revisions WHERE page_id = $1 ORDER BY created_at DESC`,
		pageID,
	)
	if err != nil {
		return nil, fmt.Errorf("querying revisions: %w", err)
	}
	defer rows.Close()

	var result []*pages.PageRevision
	for rows.Next() {
		rev := &pages.PageRevision{}
		if err := rows.Scan(&rev.ID, &rev.PageID, &rev.CreatedBy, &rev.CreatedAt, &rev.IsManual, &rev.Label); err != nil {
			return nil, fmt.Errorf("scanning revision row: %w", err)
		}
		result = append(result, rev)
	}
	return result, rows.Err()
}

func (r *Repository) HasRevisionSince(ctx context.Context, pageID string, since time.Time) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx,
		`SELECT EXISTS(SELECT 1 FROM luma.page_revisions WHERE page_id = $1 AND created_at >= $2)`,
		pageID, since,
	).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("checking revision since: %w", err)
	}
	return exists, nil
}

func (r *Repository) ListTranscludedBy(ctx context.Context, sourcePageID string) ([]*pages.Page, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT p.id, p.short_id, p.vault_id, p.title, p.content, p.created_by, p.updated_by,
		        p.is_archived, p.archived_at, p.archived_by, p.created_at, p.updated_at
		 FROM luma.pages p
		 JOIN luma.transclusion_refs tr ON tr.containing_page_id = p.id
		 WHERE tr.source_page_id = $1 AND p.is_archived = false
		 ORDER BY p.updated_at DESC`,
		sourcePageID,
	)
	if err != nil {
		return nil, fmt.Errorf("querying transclusions: %w", err)
	}
	defer rows.Close()

	var result []*pages.Page
	for rows.Next() {
		p := &pages.Page{}
		if err := rows.Scan(
			&p.ID, &p.ShortID, &p.VaultID, &p.Title, &p.Content,
			&p.CreatedBy, &p.UpdatedBy,
			&p.IsArchived, &p.ArchivedAt, &p.ArchivedBy,
			&p.CreatedAt, &p.UpdatedAt,
		); err != nil {
			return nil, fmt.Errorf("scanning transcluded page row: %w", err)
		}
		result = append(result, p)
	}
	return result, rows.Err()
}

func (r *Repository) ResolveShortIDs(ctx context.Context, shortIDs []string) (map[string]string, error) {
	if len(shortIDs) == 0 {
		return map[string]string{}, nil
	}

	rows, err := r.pool.Query(ctx,
		`SELECT short_id, resource_id::text FROM luma.short_ids
		 WHERE short_id = ANY($1) AND resource_type = 'page'`,
		shortIDs,
	)
	if err != nil {
		return nil, fmt.Errorf("resolving short ids: %w", err)
	}
	defer rows.Close()

	result := make(map[string]string, len(shortIDs))
	for rows.Next() {
		var sid, resourceID string
		if err := rows.Scan(&sid, &resourceID); err != nil {
			return nil, fmt.Errorf("scanning short id row: %w", err)
		}
		result[sid] = resourceID
	}
	return result, rows.Err()
}

func (r *Repository) GetTransclusionDescendants(ctx context.Context, pageID string, maxDepth int) ([]string, error) {
	rows, err := r.pool.Query(ctx,
		`WITH RECURSIVE descendants AS (
		     SELECT source_page_id AS id, 1 AS depth
		     FROM luma.transclusion_refs WHERE containing_page_id = $1
		     UNION
		     SELECT tr.source_page_id, d.depth + 1
		     FROM luma.transclusion_refs tr
		     JOIN descendants d ON d.id = tr.containing_page_id
		     WHERE d.depth < $2
		 )
		 SELECT DISTINCT id::text FROM descendants`,
		pageID, maxDepth,
	)
	if err != nil {
		return nil, fmt.Errorf("querying transclusion descendants: %w", err)
	}
	defer rows.Close()

	var result []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("scanning descendant row: %w", err)
		}
		result = append(result, id)
	}
	return result, rows.Err()
}

// isUniqueViolation reports whether err is a PostgreSQL unique constraint violation.
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}
