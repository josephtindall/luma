package pages

import (
	"context"
	"time"
)

// Repository defines the persistence interface for pages.
type Repository interface {
	// CreateWithShortID allocates a short_id and inserts the page atomically.
	CreateWithShortID(ctx context.Context, page *Page) error

	GetByShortID(ctx context.Context, shortID string) (*Page, error)
	GetByID(ctx context.Context, id string) (*Page, error)
	ListByVault(ctx context.Context, vaultID string, includeArchived bool) ([]*Page, error)

	// Update performs a metadata-only update (title, updated_by, updated_at).
	Update(ctx context.Context, page *Page) error

	// UpdateWithRefs atomically replaces the page content and rebuilds the
	// transclusion_refs rows for this page in a single transaction.
	UpdateWithRefs(ctx context.Context, page *Page, sourcePageIDs []string) error

	Archive(ctx context.Context, id, archivedBy string) error

	CreateRevision(ctx context.Context, rev *PageRevision) error
	GetRevision(ctx context.Context, revID string) (*PageRevision, error)
	// ListRevisions returns revision summaries — Content field is nil.
	ListRevisions(ctx context.Context, pageID string) ([]*PageRevision, error)
	// HasRevisionSince reports whether a revision exists on or after since.
	HasRevisionSince(ctx context.Context, pageID string, since time.Time) (bool, error)

	// ListTranscludedBy returns pages that have a transclusion_ref pointing to sourcePageID.
	ListTranscludedBy(ctx context.Context, sourcePageID string) ([]*Page, error)

	// ResolveShortIDs maps page short IDs to their UUIDs.
	ResolveShortIDs(ctx context.Context, shortIDs []string) (map[string]string, error)

	// GetTransclusionDescendants returns UUIDs of all pages that pageID embeds,
	// recursively up to maxDepth levels. Used for circular transclusion detection.
	GetTransclusionDescendants(ctx context.Context, pageID string, maxDepth int) ([]string, error)
}
