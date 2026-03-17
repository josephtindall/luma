package pages

import (
	"encoding/json"
	"time"
)

// Page represents a block-based document stored in a vault.
type Page struct {
	ID         string          `json:"id"`
	ShortID    string          `json:"short_id"`
	VaultID    string          `json:"vault_id"`
	Title      string          `json:"title"`
	Content    json.RawMessage `json:"content"`
	CreatedBy  string          `json:"created_by"`
	UpdatedBy  string          `json:"updated_by"`
	IsArchived bool            `json:"is_archived"`
	ArchivedAt *time.Time      `json:"archived_at,omitempty"`
	ArchivedBy *string         `json:"archived_by,omitempty"`
	CreatedAt  time.Time       `json:"created_at"`
	UpdatedAt  time.Time       `json:"updated_at"`
}

// PageRevision is a point-in-time snapshot of a page's content.
type PageRevision struct {
	ID        string          `json:"id"`
	PageID    string          `json:"page_id"`
	Content   json.RawMessage `json:"content,omitempty"`
	CreatedBy string          `json:"created_by"`
	CreatedAt time.Time       `json:"created_at"`
	IsManual  bool            `json:"is_manual"`
	Label     *string         `json:"label,omitempty"`
}

// CreatePageRequest is the input for creating a new page.
type CreatePageRequest struct {
	VaultID string          `json:"vault_id"`
	Title   string          `json:"title"`
	Content json.RawMessage `json:"content,omitempty"`
}

// UpdatePageRequest is the input for a full content save (auto-save).
type UpdatePageRequest struct {
	Title   string          `json:"title"`
	Content json.RawMessage `json:"content"`
}

// PatchPageRequest is the input for updating page metadata only.
type PatchPageRequest struct {
	Title *string `json:"title,omitempty"`
}

// CreateRevisionRequest is the input for creating a manual snapshot.
type CreateRevisionRequest struct {
	Label *string `json:"label,omitempty"`
}

// transclusionBlock and transclusionBlockAttrs are unexported types used only
// inside extractTransclusionShortIDs to parse transclusion block attrs.
type transclusionBlock struct {
	Type  string                 `json:"type"`
	Attrs transclusionBlockAttrs `json:"attrs"`
}

type transclusionBlockAttrs struct {
	SourcePageShortID string `json:"sourcePageShortId"`
}
