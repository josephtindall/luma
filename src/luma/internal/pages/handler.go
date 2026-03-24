package pages

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/josephtindall/luma/internal/auth"
	"github.com/josephtindall/luma/pkg/authz"
	"github.com/josephtindall/luma/pkg/errors"
)

// VaultChecker allows the page handler to determine vault visibility and
// look up the caller's vault membership role without a direct dependency
// on the vaults package.
type VaultChecker interface {
	IsVaultPrivate(ctx context.Context, vaultID string) (bool, error)
	// GetVaultMemberRole returns the user's vault role (e.g. "builtin:vault-admin")
	// or "" if the user is not a direct member.
	GetVaultMemberRole(ctx context.Context, vaultID, userID string) string
}

// Handler handles HTTP requests for pages.
type Handler struct {
	service      *Service
	authz        *authz.Authorizer
	vaultChecker VaultChecker
}

// NewHandler creates a new page handler.
func NewHandler(service *Service, authorizer *authz.Authorizer, vaultChecker VaultChecker) *Handler {
	return &Handler{service: service, authz: authorizer, vaultChecker: vaultChecker}
}

// Routes returns a chi router with all page routes.
func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()

	r.Get("/", h.listPages)
	r.Post("/", h.createPage)
	r.Get("/{shortId}", h.getPage)
	r.Put("/{shortId}", h.updatePage)
	r.Patch("/{shortId}", h.patchPage)
	r.Delete("/{shortId}", h.archivePage)

	r.Get("/{shortId}/revisions", h.listRevisions)
	r.Post("/{shortId}/revisions", h.createRevision)
	r.Get("/{shortId}/revisions/{revId}", h.getRevision)
	r.Post("/{shortId}/revisions/{revId}/restore", h.restoreRevision)

	r.Get("/{shortId}/transclusions", h.listTransclusions)

	return r
}

// isPrivateVault returns true if the vault requires explicit membership.
// Defaults to true (private) on error to fail-safe.
func (h *Handler) isPrivateVault(ctx context.Context, vaultID string) bool {
	if h.vaultChecker == nil {
		return true
	}
	priv, err := h.vaultChecker.IsVaultPrivate(ctx, vaultID)
	if err != nil {
		return true
	}
	return priv
}

// vaultResource builds an authz.Resource populated with the caller's vault role.
func (h *Handler) vaultResource(ctx context.Context, resourceType, resourceID, vaultID string) authz.Resource {
	role := ""
	if h.vaultChecker != nil {
		identity := auth.IdentityFromContext(ctx)
		if identity != nil {
			role = h.vaultChecker.GetVaultMemberRole(ctx, vaultID, identity.UserID)
		}
	}
	return authz.Resource{
		Type:      resourceType,
		ID:        resourceID,
		VaultID:   vaultID,
		VaultRole: role,
	}
}

// listPages returns all pages in a vault.
func (h *Handler) listPages(w http.ResponseWriter, r *http.Request) {
	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	vaultID := r.URL.Query().Get("vault_id")
	if vaultID == "" {
		http.Error(w, `{"error":"vault_id query parameter required"}`, http.StatusBadRequest)
		return
	}

	if h.isPrivateVault(r.Context(), vaultID) {
		if !h.authz.RequireCan(r.Context(), w, "page:read", h.vaultResource(r.Context(), "vault", vaultID, vaultID)) {
			return
		}
	}

	includeArchived := r.URL.Query().Get("include_archived") == "true"
	pages, err := h.service.ListPages(r.Context(), vaultID, includeArchived)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, pages)
}

func (h *Handler) createPage(w http.ResponseWriter, r *http.Request) {
	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var req CreatePageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "page:create", h.vaultResource(r.Context(), "vault", req.VaultID, req.VaultID)) {
		return
	}

	page, err := h.service.CreatePage(r.Context(), identity.UserID, req)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusCreated, page)
}

func (h *Handler) getPage(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if h.isPrivateVault(r.Context(), page.VaultID) {
		if !h.authz.RequireCan(r.Context(), w, "page:read", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
			return
		}
	}

	writeJSON(w, http.StatusOK, page)
}

func (h *Handler) updatePage(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "page:edit", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
		return
	}

	var req UpdatePageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	updated, err := h.service.UpdatePage(r.Context(), shortID, identity.UserID, req)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, updated)
}

func (h *Handler) patchPage(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "page:edit", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
		return
	}

	var req PatchPageRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	updated, err := h.service.PatchPage(r.Context(), shortID, identity.UserID, req)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, updated)
}

func (h *Handler) archivePage(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "page:archive", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
		return
	}

	if err := h.service.ArchivePage(r.Context(), shortID, identity.UserID); err != nil {
		writeError(r.Context(), w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) listRevisions(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if h.isPrivateVault(r.Context(), page.VaultID) {
		if !h.authz.RequireCan(r.Context(), w, "page:version", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
			return
		}
	}

	revs, err := h.service.ListRevisions(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	// Map to summary view — omit content field.
	type revisionSummary struct {
		ID        string  `json:"id"`
		PageID    string  `json:"page_id"`
		CreatedBy string  `json:"created_by"`
		CreatedAt string  `json:"created_at"`
		IsManual  bool    `json:"is_manual"`
		Label     *string `json:"label,omitempty"`
	}
	summaries := make([]revisionSummary, len(revs))
	for i, rev := range revs {
		summaries[i] = revisionSummary{
			ID:        rev.ID,
			PageID:    rev.PageID,
			CreatedBy: rev.CreatedBy,
			CreatedAt: rev.CreatedAt.UTC().Format("2006-01-02T15:04:05Z"),
			IsManual:  rev.IsManual,
			Label:     rev.Label,
		}
	}

	writeJSON(w, http.StatusOK, summaries)
}

func (h *Handler) createRevision(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "page:version", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
		return
	}

	var req CreateRevisionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	rev, err := h.service.CreateManualRevision(r.Context(), shortID, identity.UserID, req)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusCreated, rev)
}

func (h *Handler) getRevision(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")
	revID := chi.URLParam(r, "revId")

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if h.isPrivateVault(r.Context(), page.VaultID) {
		if !h.authz.RequireCan(r.Context(), w, "page:version", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
			return
		}
	}

	rev, err := h.service.GetRevision(r.Context(), shortID, revID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, rev)
}

func (h *Handler) restoreRevision(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")
	revID := chi.URLParam(r, "revId")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "page:restore-version", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
		return
	}

	restored, err := h.service.RestoreRevision(r.Context(), shortID, revID, identity.UserID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, restored)
}

func (h *Handler) listTransclusions(w http.ResponseWriter, r *http.Request) {
	shortID := chi.URLParam(r, "shortId")

	page, err := h.service.GetPage(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if h.isPrivateVault(r.Context(), page.VaultID) {
		if !h.authz.RequireCan(r.Context(), w, "page:read", h.vaultResource(r.Context(), "page", shortID, page.VaultID)) {
			return
		}
	}

	pages, err := h.service.ListTransclusions(r.Context(), shortID)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, pages)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v) //nolint:errcheck
}

func writeError(ctx context.Context, w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, errors.ErrNotFound):
		http.Error(w, `{"error":"not found"}`, http.StatusNotFound)
	case errors.Is(err, errors.ErrValidation):
		http.Error(w, `{"error":"validation error"}`, http.StatusBadRequest)
	case errors.Is(err, errors.ErrAlreadyExists):
		http.Error(w, `{"error":"already exists"}`, http.StatusConflict)
	case errors.Is(err, errors.ErrConflict):
		http.Error(w, `{"error":"conflict"}`, http.StatusConflict)
	case errors.Is(err, errors.ErrArchived):
		http.Error(w, `{"error":"resource is archived"}`, http.StatusConflict)
	case errors.Is(err, errors.ErrShortIDExhausted):
		slog.ErrorContext(ctx, "short id exhausted", "error", err)
		http.Error(w, `{"error":"internal server error"}`, http.StatusInternalServerError)
	default:
		slog.ErrorContext(ctx, "internal server error", "error", err)
		http.Error(w, `{"error":"internal server error"}`, http.StatusInternalServerError)
	}
}
