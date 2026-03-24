package pages

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/josephtindall/luma/pkg/errors"
)

const maxTransclusionDepth = 10

var defaultContent = json.RawMessage(`{"blocks":[]}`)

// Service contains all business logic for pages.
type Service struct {
	repo Repository
}

// NewService creates a new page service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// CreatePage creates a new page in the given vault.
func (s *Service) CreatePage(ctx context.Context, createdBy string, req CreatePageRequest) (*Page, error) {
	if strings.TrimSpace(req.VaultID) == "" {
		return nil, fmt.Errorf("vault_id: %w", errors.ErrValidation)
	}

	title := strings.TrimSpace(req.Title)
	if title == "" {
		title = "Untitled"
	}

	content := req.Content
	if len(content) == 0 {
		content = defaultContent
	}

	page := &Page{
		VaultID:   req.VaultID,
		Title:     title,
		Content:   content,
		CreatedBy: createdBy,
		UpdatedBy: createdBy,
	}

	if err := s.repo.CreateWithShortID(ctx, page); err != nil {
		return nil, fmt.Errorf("creating page: %w", err)
	}

	// TODO: audit page_created
	// TODO: mention registry notify

	return page, nil
}

// GetPage returns a page by short ID.
func (s *Service) GetPage(ctx context.Context, shortID string) (*Page, error) {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return nil, fmt.Errorf("getting page: %w", err)
	}
	return page, nil
}

// ListPages returns pages in a vault.
func (s *Service) ListPages(ctx context.Context, vaultID string, includeArchived bool) ([]*Page, error) {
	pages, err := s.repo.ListByVault(ctx, vaultID, includeArchived)
	if err != nil {
		return nil, fmt.Errorf("listing pages: %w", err)
	}
	return pages, nil
}

// UpdatePage performs a full content save (auto-save path).
// It creates an hourly snapshot of the pre-update content if none exists yet
// this hour, validates transclusion refs for cycles, then saves.
func (s *Service) UpdatePage(ctx context.Context, shortID, updatedBy string, req UpdatePageRequest) (*Page, error) {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return nil, fmt.Errorf("getting page for update: %w", err)
	}
	if page.IsArchived {
		return nil, fmt.Errorf("cannot update: %w", errors.ErrArchived)
	}

	// Hourly auto-snapshot: capture current content before overwriting.
	startOfHour := time.Now().UTC().Truncate(time.Hour)
	hasRevision, err := s.repo.HasRevisionSince(ctx, page.ID, startOfHour)
	if err != nil {
		return nil, fmt.Errorf("checking revision: %w", err)
	}
	if !hasRevision {
		rev := &PageRevision{
			PageID:    page.ID,
			Content:   page.Content,
			CreatedBy: updatedBy,
			IsManual:  false,
		}
		if err := s.repo.CreateRevision(ctx, rev); err != nil {
			return nil, fmt.Errorf("creating auto-revision: %w", err)
		}
	}

	// Resolve transclusion short IDs to UUIDs.
	shortIDs := extractTransclusionShortIDs(req.Content)
	shortIDToUUID, err := s.repo.ResolveShortIDs(ctx, shortIDs)
	if err != nil {
		return nil, fmt.Errorf("resolving transclusion short ids: %w", err)
	}

	// Cycle detection: for each transcluded page, check that this page is not
	// reachable from that page's descendants.
	sourcePageIDs := make([]string, 0, len(shortIDToUUID))
	for _, sourceID := range shortIDToUUID {
		sourcePageIDs = append(sourcePageIDs, sourceID)

		descendants, err := s.repo.GetTransclusionDescendants(ctx, sourceID, maxTransclusionDepth)
		if err != nil {
			return nil, fmt.Errorf("checking transclusion descendants: %w", err)
		}
		for _, d := range descendants {
			if d == page.ID {
				return nil, fmt.Errorf("circular transclusion detected: %w", errors.ErrConflict)
			}
		}
		if len(descendants) >= maxTransclusionDepth {
			return nil, fmt.Errorf("transclusion depth limit reached: %w", errors.ErrConflict)
		}
	}

	title := strings.TrimSpace(req.Title)
	if title == "" {
		title = "Untitled"
	}

	page.Title = title
	page.Content = req.Content
	page.UpdatedBy = updatedBy
	page.UpdatedAt = time.Now()

	if err := s.repo.UpdateWithRefs(ctx, page, sourcePageIDs); err != nil {
		return nil, fmt.Errorf("saving page: %w", err)
	}

	// TODO: audit page_updated

	return page, nil
}

// PatchPage updates page metadata (title only) without touching content or transclusion refs.
func (s *Service) PatchPage(ctx context.Context, shortID, updatedBy string, req PatchPageRequest) (*Page, error) {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return nil, fmt.Errorf("getting page for patch: %w", err)
	}
	if page.IsArchived {
		return nil, fmt.Errorf("cannot patch: %w", errors.ErrArchived)
	}

	if req.Title != nil {
		title := strings.TrimSpace(*req.Title)
		if title == "" {
			return nil, fmt.Errorf("title: %w", errors.ErrValidation)
		}
		page.Title = title
	}

	page.UpdatedBy = updatedBy
	page.UpdatedAt = time.Now()

	if err := s.repo.Update(ctx, page); err != nil {
		return nil, fmt.Errorf("patching page: %w", err)
	}
	return page, nil
}

// ArchivePage soft-deletes a page.
func (s *Service) ArchivePage(ctx context.Context, shortID, archivedBy string) error {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return fmt.Errorf("getting page for archive: %w", err)
	}
	if page.IsArchived {
		return fmt.Errorf("already archived: %w", errors.ErrConflict)
	}
	if err := s.repo.Archive(ctx, page.ID, archivedBy); err != nil {
		return fmt.Errorf("archiving page: %w", err)
	}
	return nil
}

// ListRevisions returns the revision history for a page (no content field).
func (s *Service) ListRevisions(ctx context.Context, shortID string) ([]*PageRevision, error) {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return nil, fmt.Errorf("getting page for revisions: %w", err)
	}
	revs, err := s.repo.ListRevisions(ctx, page.ID)
	if err != nil {
		return nil, fmt.Errorf("listing revisions: %w", err)
	}
	return revs, nil
}

// GetRevision returns a single revision by ID, verifying it belongs to the given page.
func (s *Service) GetRevision(ctx context.Context, shortID, revID string) (*PageRevision, error) {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return nil, fmt.Errorf("getting page for revision: %w", err)
	}
	rev, err := s.repo.GetRevision(ctx, revID)
	if err != nil {
		return nil, fmt.Errorf("getting revision: %w", err)
	}
	if rev.PageID != page.ID {
		return nil, fmt.Errorf("revision %s: %w", revID, errors.ErrNotFound)
	}
	return rev, nil
}

// CreateManualRevision creates a user-triggered snapshot of the current page content.
func (s *Service) CreateManualRevision(ctx context.Context, shortID, createdBy string, req CreateRevisionRequest) (*PageRevision, error) {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return nil, fmt.Errorf("getting page for manual revision: %w", err)
	}
	if page.IsArchived {
		return nil, fmt.Errorf("cannot revision: %w", errors.ErrArchived)
	}

	rev := &PageRevision{
		PageID:    page.ID,
		Content:   page.Content,
		CreatedBy: createdBy,
		IsManual:  true,
		Label:     req.Label,
	}
	if err := s.repo.CreateRevision(ctx, rev); err != nil {
		return nil, fmt.Errorf("creating manual revision: %w", err)
	}

	// TODO: audit page_revision_created

	return rev, nil
}

// RestoreRevision creates a new revision with the historical content and updates
// the page to that content. Does not re-run cycle detection — trust stored refs.
func (s *Service) RestoreRevision(ctx context.Context, shortID, revID, restoredBy string) (*Page, error) {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return nil, fmt.Errorf("getting page for restore: %w", err)
	}
	if page.IsArchived {
		return nil, fmt.Errorf("cannot restore: %w", errors.ErrArchived)
	}

	rev, err := s.repo.GetRevision(ctx, revID)
	if err != nil {
		return nil, fmt.Errorf("getting revision to restore: %w", err)
	}
	if rev.PageID != page.ID {
		return nil, fmt.Errorf("revision %s: %w", revID, errors.ErrNotFound)
	}

	// Create a new revision capturing the current content before overwriting.
	label := fmt.Sprintf("Restored from %s", rev.CreatedAt.UTC().Format(time.RFC3339))
	newRev := &PageRevision{
		PageID:    page.ID,
		Content:   rev.Content,
		CreatedBy: restoredBy,
		IsManual:  true,
		Label:     &label,
	}
	if err := s.repo.CreateRevision(ctx, newRev); err != nil {
		return nil, fmt.Errorf("creating restore revision: %w", err)
	}

	// Re-extract transclusion refs from the restored content.
	shortIDs := extractTransclusionShortIDs(rev.Content)
	shortIDToUUID, err := s.repo.ResolveShortIDs(ctx, shortIDs)
	if err != nil {
		return nil, fmt.Errorf("resolving transclusion refs on restore: %w", err)
	}
	sourcePageIDs := make([]string, 0, len(shortIDToUUID))
	for _, id := range shortIDToUUID {
		sourcePageIDs = append(sourcePageIDs, id)
	}

	page.Content = rev.Content
	page.UpdatedBy = restoredBy
	page.UpdatedAt = time.Now()

	if err := s.repo.UpdateWithRefs(ctx, page, sourcePageIDs); err != nil {
		return nil, fmt.Errorf("restoring page content: %w", err)
	}

	// TODO: audit page_revision_restored

	return page, nil
}

// ListTransclusions returns pages that embed the given page.
func (s *Service) ListTransclusions(ctx context.Context, shortID string) ([]*Page, error) {
	page, err := s.repo.GetByShortID(ctx, shortID)
	if err != nil {
		return nil, fmt.Errorf("getting page for transclusions: %w", err)
	}
	result, err := s.repo.ListTranscludedBy(ctx, page.ID)
	if err != nil {
		return nil, fmt.Errorf("listing transclusions: %w", err)
	}
	return result, nil
}

// extractTransclusionShortIDs recursively scans a block tree for transclusion
// blocks and returns the deduplicated list of source page short IDs.
func extractTransclusionShortIDs(content json.RawMessage) []string {
	seen := make(map[string]bool)
	var result []string
	walkBlocks(content, seen, &result)
	return result
}

func walkBlocks(data json.RawMessage, seen map[string]bool, result *[]string) {
	if len(data) == 0 {
		return
	}

	// Try as array first (e.g. top-level blocks array, or children array).
	var arr []json.RawMessage
	if json.Unmarshal(data, &arr) == nil {
		for _, item := range arr {
			walkBlocks(item, seen, result)
		}
		return
	}

	// Try as object.
	var obj map[string]json.RawMessage
	if json.Unmarshal(data, &obj) != nil {
		return
	}

	// Check if this object is a transclusion block.
	typeRaw, hasType := obj["type"]
	if hasType {
		var typeName string
		if json.Unmarshal(typeRaw, &typeName) == nil && typeName == "transclusion" {
			if attrsRaw, ok := obj["attrs"]; ok {
				var attrs transclusionBlockAttrs
				if json.Unmarshal(attrsRaw, &attrs) == nil && attrs.SourcePageShortID != "" {
					if !seen[attrs.SourcePageShortID] {
						seen[attrs.SourcePageShortID] = true
						*result = append(*result, attrs.SourcePageShortID)
					}
				}
			}
		}
	}

	// Recurse into all values (handles children, blocks, columns, etc.).
	for _, v := range obj {
		walkBlocks(v, seen, result)
	}
}
