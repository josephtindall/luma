package vaults

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

// Handler handles HTTP requests for vaults.
type Handler struct {
	service *Service
	authz   *authz.Authorizer
}

// NewHandler creates a new vault handler.
func NewHandler(service *Service, authorizer *authz.Authorizer) *Handler {
	return &Handler{service: service, authz: authorizer}
}

// Routes returns a chi router with all vault routes.
func (h *Handler) Routes() chi.Router {
	r := chi.NewRouter()

	r.Get("/", h.listVaults)
	r.Post("/", h.createVault)
	r.Get("/{id}", h.getVault)
	r.Patch("/{id}", h.updateVault)
	r.Delete("/{id}", h.archiveVault)

	r.Get("/{id}/members", h.listMembers)
	r.Post("/{id}/members", h.addMember)
	r.Patch("/{id}/members/{userId}", h.updateMemberRole)
	r.Delete("/{id}/members/{userId}", h.removeMember)

	return r
}

// listVaults returns all vaults the caller is a member of. Access control is
// enforced by the vault_members JOIN in the repository query — a user can only
// see vaults they have been explicitly added to, so no RequireCan call is needed.
func (h *Handler) listVaults(w http.ResponseWriter, r *http.Request) {
	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	includeArchived := r.URL.Query().Get("include_archived") == "true"
	vaults, err := h.service.ListVaults(r.Context(), identity.UserID, includeArchived)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, vaults)
}

func (h *Handler) createVault(w http.ResponseWriter, r *http.Request) {
	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "vault:create", authz.Resource{
		Type: "vault",
	}) {
		return
	}

	var req CreateVaultRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	vault, err := h.service.CreateSharedVault(r.Context(), identity.UserID, req)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusCreated, vault)
}

func (h *Handler) getVault(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	// Check permission before querying the DB to avoid leaking existence info.
	if !h.authz.RequireCan(r.Context(), w, "vault:read", authz.Resource{
		Type:    "vault",
		ID:      id,
		VaultID: id,
	}) {
		return
	}

	vault, err := h.service.GetVault(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, vault)
}

func (h *Handler) updateVault(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	if !h.authz.RequireCan(r.Context(), w, "vault:edit", authz.Resource{
		Type:    "vault",
		ID:      id,
		VaultID: id,
	}) {
		return
	}

	var req UpdateVaultRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	vault, err := h.service.UpdateVault(r.Context(), id, req)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, vault)
}

func (h *Handler) archiveVault(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "vault:archive", authz.Resource{
		Type:    "vault",
		ID:      id,
		VaultID: id,
	}) {
		return
	}

	if err := h.service.ArchiveVault(r.Context(), id, identity.UserID); err != nil {
		writeError(r.Context(), w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) listMembers(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	if !h.authz.RequireCan(r.Context(), w, "vault:read", authz.Resource{
		Type:    "vault",
		ID:      id,
		VaultID: id,
	}) {
		return
	}

	members, err := h.service.ListMembers(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, members)
}

func (h *Handler) addMember(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	if !h.authz.RequireCan(r.Context(), w, "vault:manage-members", authz.Resource{
		Type:    "vault",
		ID:      id,
		VaultID: id,
	}) {
		return
	}

	var req AddMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if err := h.service.AddMember(r.Context(), id, req, identity.UserID); err != nil {
		writeError(r.Context(), w, err)
		return
	}

	w.WriteHeader(http.StatusCreated)
}

func (h *Handler) updateMemberRole(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	userID := chi.URLParam(r, "userId")

	if !h.authz.RequireCan(r.Context(), w, "vault:manage-roles", authz.Resource{
		Type:    "vault",
		ID:      id,
		VaultID: id,
	}) {
		return
	}

	var req UpdateMemberRoleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}

	if err := h.service.UpdateMemberRole(r.Context(), id, userID, req.RoleID); err != nil {
		writeError(r.Context(), w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) removeMember(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	userID := chi.URLParam(r, "userId")

	if !h.authz.RequireCan(r.Context(), w, "vault:manage-members", authz.Resource{
		Type:    "vault",
		ID:      id,
		VaultID: id,
	}) {
		return
	}

	if err := h.service.RemoveMember(r.Context(), id, userID); err != nil {
		writeError(r.Context(), w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
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
	default:
		slog.ErrorContext(ctx, "internal server error", "error", err)
		http.Error(w, `{"error":"internal server error"}`, http.StatusInternalServerError)
	}
}
