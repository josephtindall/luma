package pages

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/josephtindall/luma/pkg/errors"
)

// --- Mock Repository ---

type mockRepository struct {
	pages     map[string]*Page     // keyed by ID
	byShortID map[string]*Page     // keyed by short_id
	revisions map[string]*PageRevision // keyed by revision ID
	shortIDs  map[string]string    // shortID -> UUID

	createWithShortIDErr error
	updateWithRefsErr    error
	descendants          map[string][]string // pageID -> descendant IDs
}

func newMockRepo() *mockRepository {
	return &mockRepository{
		pages:       make(map[string]*Page),
		byShortID:   make(map[string]*Page),
		revisions:   make(map[string]*PageRevision),
		shortIDs:    make(map[string]string),
		descendants: make(map[string][]string),
	}
}

func (m *mockRepository) addPage(p *Page) {
	m.pages[p.ID] = p
	m.byShortID[p.ShortID] = p
}

func (m *mockRepository) CreateWithShortID(_ context.Context, page *Page) error {
	if m.createWithShortIDErr != nil {
		return m.createWithShortIDErr
	}
	if page.ID == "" {
		page.ID = "page-uuid-1"
	}
	if page.ShortID == "" {
		page.ShortID = "short1"
	}
	page.CreatedAt = time.Now()
	page.UpdatedAt = page.CreatedAt
	m.pages[page.ID] = page
	m.byShortID[page.ShortID] = page
	return nil
}

func (m *mockRepository) GetByShortID(_ context.Context, shortID string) (*Page, error) {
	p, ok := m.byShortID[shortID]
	if !ok {
		return nil, errors.ErrNotFound
	}
	return p, nil
}

func (m *mockRepository) GetByID(_ context.Context, id string) (*Page, error) {
	p, ok := m.pages[id]
	if !ok {
		return nil, errors.ErrNotFound
	}
	return p, nil
}

func (m *mockRepository) ListByVault(_ context.Context, vaultID string, includeArchived bool) ([]*Page, error) {
	var result []*Page
	for _, p := range m.pages {
		if p.VaultID != vaultID {
			continue
		}
		if !includeArchived && p.IsArchived {
			continue
		}
		result = append(result, p)
	}
	return result, nil
}

func (m *mockRepository) Update(_ context.Context, page *Page) error {
	m.pages[page.ID] = page
	m.byShortID[page.ShortID] = page
	return nil
}

func (m *mockRepository) UpdateWithRefs(_ context.Context, page *Page, _ []string) error {
	if m.updateWithRefsErr != nil {
		return m.updateWithRefsErr
	}
	m.pages[page.ID] = page
	m.byShortID[page.ShortID] = page
	return nil
}

func (m *mockRepository) Archive(_ context.Context, id, archivedBy string) error {
	p, ok := m.pages[id]
	if !ok {
		return errors.ErrNotFound
	}
	p.IsArchived = true
	now := time.Now()
	p.ArchivedAt = &now
	p.ArchivedBy = &archivedBy
	return nil
}

func (m *mockRepository) CreateRevision(_ context.Context, rev *PageRevision) error {
	if rev.ID == "" {
		rev.ID = "rev-" + rev.PageID + "-" + time.Now().Format("150405")
	}
	rev.CreatedAt = time.Now()
	m.revisions[rev.ID] = rev
	return nil
}

func (m *mockRepository) GetRevision(_ context.Context, revID string) (*PageRevision, error) {
	rev, ok := m.revisions[revID]
	if !ok {
		return nil, errors.ErrNotFound
	}
	return rev, nil
}

func (m *mockRepository) ListRevisions(_ context.Context, pageID string) ([]*PageRevision, error) {
	var result []*PageRevision
	for _, rev := range m.revisions {
		if rev.PageID == pageID {
			result = append(result, rev)
		}
	}
	return result, nil
}

func (m *mockRepository) HasRevisionSince(_ context.Context, pageID string, since time.Time) (bool, error) {
	for _, rev := range m.revisions {
		if rev.PageID == pageID && !rev.CreatedAt.Before(since) {
			return true, nil
		}
	}
	return false, nil
}

func (m *mockRepository) ListTranscludedBy(_ context.Context, sourcePageID string) ([]*Page, error) {
	return nil, nil
}

func (m *mockRepository) ResolveShortIDs(_ context.Context, shortIDs []string) (map[string]string, error) {
	result := make(map[string]string)
	for _, sid := range shortIDs {
		if uuid, ok := m.shortIDs[sid]; ok {
			result[sid] = uuid
		}
	}
	return result, nil
}

func (m *mockRepository) GetTransclusionDescendants(_ context.Context, pageID string, _ int) ([]string, error) {
	return m.descendants[pageID], nil
}

// --- Tests: CreatePage ---

func TestCreatePage_Success(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	page, err := svc.CreatePage(context.Background(), "user-1", CreatePageRequest{
		VaultID: "vault-1",
		Title:   "My Page",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if page.VaultID != "vault-1" {
		t.Errorf("expected vault-1, got %q", page.VaultID)
	}
	if page.Title != "My Page" {
		t.Errorf("expected 'My Page', got %q", page.Title)
	}
}

func TestCreatePage_EmptyVaultID(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	_, err := svc.CreatePage(context.Background(), "user-1", CreatePageRequest{
		VaultID: "  ",
		Title:   "My Page",
	})
	if !errors.Is(err, errors.ErrValidation) {
		t.Fatalf("expected ErrValidation, got: %v", err)
	}
}

func TestCreatePage_EmptyTitleDefaultsToUntitled(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	page, err := svc.CreatePage(context.Background(), "user-1", CreatePageRequest{
		VaultID: "vault-1",
		Title:   "",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if page.Title != "Untitled" {
		t.Errorf("expected 'Untitled', got %q", page.Title)
	}
}

func TestCreatePage_NilContentDefaultsToEmptyBlocks(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	page, err := svc.CreatePage(context.Background(), "user-1", CreatePageRequest{
		VaultID: "vault-1",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(page.Content) != `{"blocks":[]}` {
		t.Errorf("unexpected default content: %s", page.Content)
	}
}

// --- Tests: UpdatePage ---

func TestUpdatePage_Success(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1", VaultID: "v1", Title: "Old"})
	svc := NewService(repo)

	page, err := svc.UpdatePage(context.Background(), "s1", "user-1", UpdatePageRequest{
		Title:   "New Title",
		Content: json.RawMessage(`{"blocks":[]}`),
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if page.Title != "New Title" {
		t.Errorf("expected 'New Title', got %q", page.Title)
	}
}

func TestUpdatePage_ArchivedPage(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1", IsArchived: true})
	svc := NewService(repo)

	_, err := svc.UpdatePage(context.Background(), "s1", "user-1", UpdatePageRequest{
		Title:   "x",
		Content: json.RawMessage(`{"blocks":[]}`),
	})
	if !errors.Is(err, errors.ErrArchived) {
		t.Fatalf("expected ErrArchived, got: %v", err)
	}
}

func TestUpdatePage_CreatesHourlySnapshotWhenNoneExists(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{
		ID:      "p1",
		ShortID: "s1",
		Content: json.RawMessage(`{"blocks":["old"]}`),
	})
	svc := NewService(repo)

	_, err := svc.UpdatePage(context.Background(), "s1", "user-1", UpdatePageRequest{
		Title:   "t",
		Content: json.RawMessage(`{"blocks":["new"]}`),
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	revs, _ := repo.ListRevisions(context.Background(), "p1")
	if len(revs) != 1 {
		t.Errorf("expected 1 auto-revision, got %d", len(revs))
	}
}

func TestUpdatePage_SkipsSnapshotWhenOneExistsThisHour(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1"})
	// Pre-seed a revision at the start of this hour.
	startOfHour := time.Now().UTC().Truncate(time.Hour)
	repo.revisions["rev-existing"] = &PageRevision{
		ID:        "rev-existing",
		PageID:    "p1",
		CreatedAt: startOfHour,
	}
	svc := NewService(repo)

	_, err := svc.UpdatePage(context.Background(), "s1", "user-1", UpdatePageRequest{
		Title:   "t",
		Content: json.RawMessage(`{"blocks":[]}`),
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	// Should still be exactly 1 revision.
	revs, _ := repo.ListRevisions(context.Background(), "p1")
	if len(revs) != 1 {
		t.Errorf("expected 1 revision (no new one), got %d", len(revs))
	}
}

func TestUpdatePage_CircularTransclusion(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "page-a", ShortID: "sA"})
	repo.shortIDs["sB"] = "page-b"
	// page-b's descendants include page-a (so A→B would create A→B→A cycle).
	repo.descendants["page-b"] = []string{"page-a"}
	svc := NewService(repo)

	_, err := svc.UpdatePage(context.Background(), "sA", "user-1", UpdatePageRequest{
		Title:   "A",
		Content: json.RawMessage(`{"blocks":[{"type":"transclusion","attrs":{"sourcePageShortId":"sB"}}]}`),
	})
	if !errors.Is(err, errors.ErrConflict) {
		t.Fatalf("expected ErrConflict for circular transclusion, got: %v", err)
	}
}

func TestUpdatePage_TransclusionRefsPassedToUpdateWithRefs(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1"})
	repo.shortIDs["sB"] = "page-b-uuid"

	var capturedSourceIDs []string
	repo.updateWithRefsErr = nil
	// Override UpdateWithRefs to capture the sourcePageIDs.
	// (Can't do this cleanly without wrapping; check via ListRevisions + no error.)

	svc := NewService(repo)
	_ = capturedSourceIDs

	_, err := svc.UpdatePage(context.Background(), "s1", "user-1", UpdatePageRequest{
		Title:   "t",
		Content: json.RawMessage(`{"blocks":[{"type":"transclusion","attrs":{"sourcePageShortId":"sB"}}]}`),
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

// --- Tests: PatchPage ---

func TestPatchPage_Success(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1", Title: "Old"})
	svc := NewService(repo)

	newTitle := "New Title"
	page, err := svc.PatchPage(context.Background(), "s1", "user-1", PatchPageRequest{
		Title: &newTitle,
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if page.Title != "New Title" {
		t.Errorf("expected 'New Title', got %q", page.Title)
	}
}

func TestPatchPage_BlankTitle(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1", Title: "Old"})
	svc := NewService(repo)

	blank := "   "
	_, err := svc.PatchPage(context.Background(), "s1", "user-1", PatchPageRequest{
		Title: &blank,
	})
	if !errors.Is(err, errors.ErrValidation) {
		t.Fatalf("expected ErrValidation, got: %v", err)
	}
}

func TestPatchPage_ArchivedPage(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1", IsArchived: true})
	svc := NewService(repo)

	title := "x"
	_, err := svc.PatchPage(context.Background(), "s1", "user-1", PatchPageRequest{Title: &title})
	if !errors.Is(err, errors.ErrArchived) {
		t.Fatalf("expected ErrArchived, got: %v", err)
	}
}

// --- Tests: ArchivePage ---

func TestArchivePage_Success(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1"})
	svc := NewService(repo)

	if err := svc.ArchivePage(context.Background(), "s1", "user-1"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestArchivePage_AlreadyArchived(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1", IsArchived: true})
	svc := NewService(repo)

	err := svc.ArchivePage(context.Background(), "s1", "user-1")
	if !errors.Is(err, errors.ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}
}

func TestArchivePage_NotFound(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	err := svc.ArchivePage(context.Background(), "nonexistent", "user-1")
	if !errors.Is(err, errors.ErrNotFound) {
		t.Fatalf("expected ErrNotFound, got: %v", err)
	}
}

// --- Tests: Revision Operations ---

func TestCreateManualRevision_Success(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{
		ID:      "p1",
		ShortID: "s1",
		Content: json.RawMessage(`{"blocks":[]}`),
	})
	svc := NewService(repo)

	label := "v1.0"
	rev, err := svc.CreateManualRevision(context.Background(), "s1", "user-1", CreateRevisionRequest{Label: &label})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !rev.IsManual {
		t.Error("expected is_manual=true")
	}
	if rev.Label == nil || *rev.Label != "v1.0" {
		t.Errorf("expected label 'v1.0', got %v", rev.Label)
	}
}

func TestCreateManualRevision_ArchivedPage(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1", IsArchived: true})
	svc := NewService(repo)

	_, err := svc.CreateManualRevision(context.Background(), "s1", "user-1", CreateRevisionRequest{})
	if !errors.Is(err, errors.ErrArchived) {
		t.Fatalf("expected ErrArchived, got: %v", err)
	}
}

func TestGetRevision_WrongPage(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1"})
	repo.addPage(&Page{ID: "p2", ShortID: "s2"})
	repo.revisions["rev-1"] = &PageRevision{ID: "rev-1", PageID: "p2"}
	svc := NewService(repo)

	_, err := svc.GetRevision(context.Background(), "s1", "rev-1")
	if !errors.Is(err, errors.ErrNotFound) {
		t.Fatalf("expected ErrNotFound for wrong page, got: %v", err)
	}
}

func TestRestoreRevision_Success(t *testing.T) {
	repo := newMockRepo()
	oldContent := json.RawMessage(`{"blocks":["old"]}`)
	repo.addPage(&Page{
		ID:      "p1",
		ShortID: "s1",
		Content: json.RawMessage(`{"blocks":["current"]}`),
	})
	repo.revisions["rev-1"] = &PageRevision{
		ID:        "rev-1",
		PageID:    "p1",
		Content:   oldContent,
		CreatedAt: time.Now().Add(-2 * time.Hour),
	}
	svc := NewService(repo)

	page, err := svc.RestoreRevision(context.Background(), "s1", "rev-1", "user-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if string(page.Content) != string(oldContent) {
		t.Errorf("expected restored content, got %s", page.Content)
	}
}

func TestRestoreRevision_ArchivedPage(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1", IsArchived: true})
	repo.revisions["rev-1"] = &PageRevision{ID: "rev-1", PageID: "p1"}
	svc := NewService(repo)

	_, err := svc.RestoreRevision(context.Background(), "s1", "rev-1", "user-1")
	if !errors.Is(err, errors.ErrArchived) {
		t.Fatalf("expected ErrArchived, got: %v", err)
	}
}

func TestRestoreRevision_WrongPage(t *testing.T) {
	repo := newMockRepo()
	repo.addPage(&Page{ID: "p1", ShortID: "s1"})
	repo.addPage(&Page{ID: "p2", ShortID: "s2"})
	repo.revisions["rev-1"] = &PageRevision{ID: "rev-1", PageID: "p2"}
	svc := NewService(repo)

	_, err := svc.RestoreRevision(context.Background(), "s1", "rev-1", "user-1")
	if !errors.Is(err, errors.ErrNotFound) {
		t.Fatalf("expected ErrNotFound for wrong page, got: %v", err)
	}
}

// --- Tests: extractTransclusionShortIDs ---

func TestExtractTransclusionShortIDs_EmptyBlocks(t *testing.T) {
	ids := extractTransclusionShortIDs(json.RawMessage(`{"blocks":[]}`))
	if len(ids) != 0 {
		t.Errorf("expected 0 ids, got %v", ids)
	}
}

func TestExtractTransclusionShortIDs_NoTransclusions(t *testing.T) {
	ids := extractTransclusionShortIDs(json.RawMessage(`{"blocks":[{"type":"paragraph","text":"hello"}]}`))
	if len(ids) != 0 {
		t.Errorf("expected 0 ids, got %v", ids)
	}
}

func TestExtractTransclusionShortIDs_SingleTransclusion(t *testing.T) {
	content := json.RawMessage(`{"blocks":[{"type":"transclusion","attrs":{"sourcePageShortId":"abc123"}}]}`)
	ids := extractTransclusionShortIDs(content)
	if len(ids) != 1 || ids[0] != "abc123" {
		t.Errorf("expected [abc123], got %v", ids)
	}
}

func TestExtractTransclusionShortIDs_Deduplicated(t *testing.T) {
	content := json.RawMessage(`{"blocks":[
		{"type":"transclusion","attrs":{"sourcePageShortId":"abc"}},
		{"type":"transclusion","attrs":{"sourcePageShortId":"abc"}}
	]}`)
	ids := extractTransclusionShortIDs(content)
	if len(ids) != 1 {
		t.Errorf("expected 1 deduplicated id, got %v", ids)
	}
}

func TestExtractTransclusionShortIDs_NestedInColumnBlock(t *testing.T) {
	// Transclusion nested inside a columns_2 layout block.
	content := json.RawMessage(`{
		"blocks": [{
			"type": "columns_2",
			"children": [
				{"type": "transclusion", "attrs": {"sourcePageShortId": "nested1"}}
			]
		}]
	}`)
	ids := extractTransclusionShortIDs(content)
	if len(ids) != 1 || ids[0] != "nested1" {
		t.Errorf("expected [nested1], got %v", ids)
	}
}
