package customrole

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/josephtindall/luma-auth/internal/authz"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// Handler serves custom role admin endpoints.
type Handler struct {
	svc      *Service
	authzSvc authz.Authorizer
}

// NewHandler constructs the custom role handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// SetAuthorizer injects the authz evaluator (called after construction in main).
func (h *Handler) SetAuthorizer(a authz.Authorizer) { h.authzSvc = a }

func (h *Handler) requirePerm(w http.ResponseWriter, r *http.Request, action string) bool {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return false
	}
	if claims.Role == "builtin:instance-owner" {
		return true
	}
	if h.authzSvc == nil {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "forbidden")
		return false
	}
	result, err := h.authzSvc.Check(r.Context(), authz.CheckRequest{
		UserID: claims.Subject,
		Action: action,
	})
	if err != nil || !result.Allowed {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "forbidden")
		return false
	}
	return true
}

// ListRoles handles GET /api/auth/admin/custom-roles.
func (h *Handler) ListRoles(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:read") {
		return
	}
	roles, err := h.svc.List(r.Context())
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if roles == nil {
		roles = []*CustomRoleWithDetails{}
	}
	httputil.WriteJSON(w, http.StatusOK, roles)
}

// CreateRole handles POST /api/auth/admin/custom-roles.
func (h *Handler) CreateRole(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:create") {
		return
	}
	var req struct {
		Name        string  `json:"name"`
		Priority    *int    `json:"priority"`
		Description *string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name is required")
		return
	}
	cr, err := h.svc.Create(r.Context(), req.Name, req.Priority, req.Description)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusCreated, cr)
}

// GetRole handles GET /api/auth/admin/custom-roles/{id}.
func (h *Handler) GetRole(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:read") {
		return
	}
	id := chi.URLParam(r, "id")
	cr, err := h.svc.Get(r.Context(), id)
	if err != nil {
		httputil.WriteError(w, http.StatusNotFound, "NOT_FOUND", "custom role not found")
		return
	}
	httputil.WriteJSON(w, http.StatusOK, cr)
}

// UpdateRole handles PATCH /api/auth/admin/custom-roles/{id}.
func (h *Handler) UpdateRole(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:update") {
		return
	}
	id := chi.URLParam(r, "id")
	var req struct {
		Name        string  `json:"name"`
		Priority    *int    `json:"priority"`
		Description *string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name is required")
		return
	}
	cr, err := h.svc.Update(r.Context(), id, req.Name, req.Priority, req.Description)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, cr)
}

// DeleteRole handles DELETE /api/auth/admin/custom-roles/{id}.
func (h *Handler) DeleteRole(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:delete") {
		return
	}
	id := chi.URLParam(r, "id")
	if err := h.svc.Delete(r.Context(), id); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// SetPermission handles PUT /api/auth/admin/custom-roles/{id}/permissions/{action}.
func (h *Handler) SetPermission(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:set-permission") {
		return
	}
	id := chi.URLParam(r, "id")
	action := chi.URLParam(r, "action")
	var req struct {
		Effect string `json:"effect"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.Effect != "allow" && req.Effect != "allow_cascade" && req.Effect != "deny" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "effect must be allow, allow_cascade, or deny")
		return
	}
	if err := h.svc.SetPermission(r.Context(), id, action, req.Effect); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// RemovePermission handles DELETE /api/auth/admin/custom-roles/{id}/permissions/{action}.
func (h *Handler) RemovePermission(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:remove-permission") {
		return
	}
	id := chi.URLParam(r, "id")
	action := chi.URLParam(r, "action")
	if err := h.svc.RemovePermission(r.Context(), id, action); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ListUserCustomRoles handles GET /api/auth/admin/users/{id}/custom-roles.
// Requires role:read permission or owner role.
func (h *Handler) ListUserCustomRoles(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:read") {
		return
	}
	userID := chi.URLParam(r, "id")
	roles, err := h.svc.GetUserCustomRoles(r.Context(), userID)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if roles == nil {
		roles = []*CustomRole{}
	}
	httputil.WriteJSON(w, http.StatusOK, roles)
}

// AssignToUser handles POST /api/auth/admin/users/{id}/custom-roles/{roleID}.
func (h *Handler) AssignToUser(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:assign-user") {
		return
	}
	userID := chi.URLParam(r, "id")
	roleID := chi.URLParam(r, "roleID")
	if err := h.svc.AssignToUser(r.Context(), roleID, userID); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// RemoveFromUser handles DELETE /api/auth/admin/users/{id}/custom-roles/{roleID}.
func (h *Handler) RemoveFromUser(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "role:unassign-user") {
		return
	}
	userID := chi.URLParam(r, "id")
	roleID := chi.URLParam(r, "roleID")
	if err := h.svc.RemoveFromUser(r.Context(), roleID, userID); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
