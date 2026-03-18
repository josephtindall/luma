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

// vaultAuthClient is a minimal interface for resolving user/group display info.
type vaultAuthClient interface {
	GetUser(ctx context.Context, userID string) (*auth.User, error)
	GetGroup(ctx context.Context, groupID string) (*auth.Group, error)
}

// Handler handles HTTP requests for vaults.
type Handler struct {
	service    *Service
	authz      *authz.Authorizer
	authClient vaultAuthClient
}

// NewHandler creates a new vault handler.
func NewHandler(service *Service, authorizer *authz.Authorizer, client vaultAuthClient) *Handler {
	return &Handler{service: service, authz: authorizer, authClient: client}
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

	r.Get("/{id}/groups", h.listGroupMembers)
	r.Post("/{id}/groups", h.addGroupMember)
	r.Patch("/{id}/groups/{groupId}", h.updateGroupMemberRole)
	r.Delete("/{id}/groups/{groupId}", h.removeGroupMember)

	r.Get("/{id}/my-permissions", h.myVaultPermissions)

	return r
}

// AdminRoutes returns a chi router for admin-privileged vault operations.
// All routes require instance:read permission (i.e. instance admin access).
func (h *Handler) AdminRoutes() chi.Router {
	r := chi.NewRouter()

	r.Get("/", h.adminListVaults)
	r.Patch("/{id}", h.adminUpdateVault)
	r.Delete("/{id}", h.adminArchiveVault)
	r.Get("/{id}/members", h.adminListMembers)
	r.Post("/{id}/members", h.adminAddMember)
	r.Patch("/{id}/members/{userId}", h.adminUpdateMemberRole)
	r.Delete("/{id}/members/{userId}", h.adminRemoveMember)

	r.Get("/{id}/groups", h.adminListGroupMembers)
	r.Post("/{id}/groups", h.adminAddGroupMember)
	r.Patch("/{id}/groups/{groupId}", h.adminUpdateGroupMemberRole)
	r.Delete("/{id}/groups/{groupId}", h.adminRemoveGroupMember)

	return r
}

// requireAdmin checks that the caller has instance:read (admin) access.
func (h *Handler) requireAdmin(w http.ResponseWriter, r *http.Request) bool {
	return h.authz.RequireCan(r.Context(), w, "instance:read", authz.Resource{Type: "instance"})
}

// listVaults returns all vaults the caller is a member of (plus non-private vaults).
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

	vault, err := h.service.GetVault(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	// Private vaults require explicit membership; public vaults are open to all.
	if vault.IsPrivate {
		if !h.authz.RequireCan(r.Context(), w, "vault:read", authz.Resource{
			Type:    "vault",
			ID:      id,
			VaultID: id,
		}) {
			return
		}
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

	vault, err := h.service.GetVault(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	if vault.IsPrivate {
		if !h.authz.RequireCan(r.Context(), w, "vault:read", authz.Resource{
			Type:    "vault",
			ID:      id,
			VaultID: id,
		}) {
			return
		}
	}

	members, err := h.service.ListMembers(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, h.enrichMembers(r.Context(), members))
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

// ── Admin handlers ────────────────────────────────────────────────────────────

func (h *Handler) adminListVaults(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}

	includeArchived := r.URL.Query().Get("include_archived") == "true"
	vaults, err := h.service.ListAllVaults(r.Context(), includeArchived)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, vaults)
}

func (h *Handler) adminUpdateVault(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}

	id := chi.URLParam(r, "id")

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

func (h *Handler) adminArchiveVault(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}

	id := chi.URLParam(r, "id")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}

	if err := h.service.ArchiveVault(r.Context(), id, identity.UserID); err != nil {
		writeError(r.Context(), w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) adminListMembers(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}

	id := chi.URLParam(r, "id")

	members, err := h.service.ListMembers(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}

	writeJSON(w, http.StatusOK, h.enrichMembers(r.Context(), members))
}

func (h *Handler) adminAddMember(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}

	id := chi.URLParam(r, "id")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
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

func (h *Handler) adminUpdateMemberRole(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}

	id := chi.URLParam(r, "id")
	userID := chi.URLParam(r, "userId")

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

func (h *Handler) adminRemoveMember(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}

	id := chi.URLParam(r, "id")
	userID := chi.URLParam(r, "userId")

	if err := h.service.RemoveMember(r.Context(), id, userID); err != nil {
		writeError(r.Context(), w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ── Group member handlers ─────────────────────────────────────────────────────

func (h *Handler) listGroupMembers(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	vault, err := h.service.GetVault(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}
	if vault.IsPrivate {
		if !h.authz.RequireCan(r.Context(), w, "vault:read", authz.Resource{
			Type: "vault", ID: id, VaultID: id,
		}) {
			return
		}
	}

	members, err := h.service.ListGroupMembers(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}
	writeJSON(w, http.StatusOK, h.enrichGroupMembers(r.Context(), members))
}

func (h *Handler) addGroupMember(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")

	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}
	if !h.authz.RequireCan(r.Context(), w, "vault:manage-members", authz.Resource{
		Type: "vault", ID: id, VaultID: id,
	}) {
		return
	}

	var req AddGroupMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if err := h.service.AddGroupMember(r.Context(), id, req, identity.UserID); err != nil {
		writeError(r.Context(), w, err)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func (h *Handler) updateGroupMemberRole(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	groupID := chi.URLParam(r, "groupId")

	if !h.authz.RequireCan(r.Context(), w, "vault:manage-roles", authz.Resource{
		Type: "vault", ID: id, VaultID: id,
	}) {
		return
	}

	var req UpdateMemberRoleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if err := h.service.UpdateGroupMemberRole(r.Context(), id, groupID, req.RoleID); err != nil {
		writeError(r.Context(), w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) removeGroupMember(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	groupID := chi.URLParam(r, "groupId")

	if !h.authz.RequireCan(r.Context(), w, "vault:manage-members", authz.Resource{
		Type: "vault", ID: id, VaultID: id,
	}) {
		return
	}
	if err := h.service.RemoveGroupMember(r.Context(), id, groupID); err != nil {
		writeError(r.Context(), w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ── Admin group member handlers ────────────────────────────────────────────────

func (h *Handler) adminListGroupMembers(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	members, err := h.service.ListGroupMembers(r.Context(), id)
	if err != nil {
		writeError(r.Context(), w, err)
		return
	}
	writeJSON(w, http.StatusOK, h.enrichGroupMembers(r.Context(), members))
}

func (h *Handler) adminAddGroupMember(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	identity := auth.IdentityFromContext(r.Context())
	if identity == nil {
		http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
		return
	}
	var req AddGroupMemberRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if err := h.service.AddGroupMember(r.Context(), id, req, identity.UserID); err != nil {
		writeError(r.Context(), w, err)
		return
	}
	w.WriteHeader(http.StatusCreated)
}

func (h *Handler) adminUpdateGroupMemberRole(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	groupID := chi.URLParam(r, "groupId")
	var req UpdateMemberRoleRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid request body"}`, http.StatusBadRequest)
		return
	}
	if err := h.service.UpdateGroupMemberRole(r.Context(), id, groupID, req.RoleID); err != nil {
		writeError(r.Context(), w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) adminRemoveGroupMember(w http.ResponseWriter, r *http.Request) {
	if !h.requireAdmin(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	groupID := chi.URLParam(r, "groupId")
	if err := h.service.RemoveGroupMember(r.Context(), id, groupID); err != nil {
		writeError(r.Context(), w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ── Permissions endpoint ──────────────────────────────────────────────────────

func (h *Handler) myVaultPermissions(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	res := authz.Resource{Type: "vault", ID: id, VaultID: id}
	writeJSON(w, http.StatusOK, map[string]bool{
		"can_edit":           h.authz.Can(r.Context(), "vault:edit", res),
		"can_archive":        h.authz.Can(r.Context(), "vault:archive", res),
		"can_manage_members": h.authz.Can(r.Context(), "vault:manage-members", res),
		"can_manage_roles":   h.authz.Can(r.Context(), "vault:manage-roles", res),
	})
}

// ── Helpers ───────────────────────────────────────────────────────────────────

// enrichMembers adds display info from the auth service to each member record.
func (h *Handler) enrichMembers(ctx context.Context, members []*VaultMember) []*VaultMemberDetail {
	details := make([]*VaultMemberDetail, 0, len(members))
	for _, m := range members {
		d := &VaultMemberDetail{
			VaultID:     m.VaultID,
			UserID:      m.UserID,
			DisplayName: m.UserID, // fallback
			RoleID:      m.RoleID,
			AddedAt:     m.AddedAt,
		}
		if h.authClient != nil {
			if user, err := h.authClient.GetUser(ctx, m.UserID); err == nil {
				d.Email = user.Email
				d.DisplayName = user.DisplayName
				d.AvatarSeed = user.AvatarSeed
			}
		}
		details = append(details, d)
	}
	return details
}

// enrichGroupMembers adds group display info from the auth service.
func (h *Handler) enrichGroupMembers(ctx context.Context, members []*VaultGroupMember) []*VaultGroupMemberDetail {
	details := make([]*VaultGroupMemberDetail, 0, len(members))
	for _, m := range members {
		d := &VaultGroupMemberDetail{
			VaultID:   m.VaultID,
			GroupID:   m.GroupID,
			GroupName: m.GroupID, // fallback
			RoleID:    m.RoleID,
			AddedAt:   m.AddedAt,
		}
		if h.authClient != nil {
			if group, err := h.authClient.GetGroup(ctx, m.GroupID); err == nil {
				d.GroupName = group.Name
			}
		}
		details = append(details, d)
	}
	return details
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
