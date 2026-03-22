package group

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/josephtindall/luma-auth/internal/audit"
	"github.com/josephtindall/luma-auth/internal/authz"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// Handler serves group admin endpoints.
type Handler struct {
	svc      *Service
	authzSvc authz.Authorizer
	audit    audit.Service
}

// NewHandler constructs the group handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// SetAuthorizer injects the authz evaluator (called after construction in main).
func (h *Handler) SetAuthorizer(a authz.Authorizer) { h.authzSvc = a }

// SetAuditor injects the audit service.
func (h *Handler) SetAuditor(a audit.Service) { h.audit = a }

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

// ListGroups handles GET /api/auth/admin/groups.
func (h *Handler) ListGroups(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:read") {
		return
	}
	groups, err := h.svc.List(r.Context())
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if groups == nil {
		groups = []*GroupWithDetails{}
	}
	httputil.WriteJSON(w, http.StatusOK, groups)
}

// CreateGroup handles POST /api/auth/admin/groups.
func (h *Handler) CreateGroup(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:create") {
		return
	}
	var req struct {
		Name        string  `json:"name"`
		Description *string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name is required")
		return
	}
	g, err := h.svc.Create(r.Context(), req.Name, req.Description)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if h.audit != nil {
		claims := middleware.ClaimsFromContext(r.Context())
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventGroupCreated,
			Metadata: map[string]any{
				"group_id":   g.ID,
				"group_name": g.Name,
			},
		})
	}
	httputil.WriteJSON(w, http.StatusCreated, g)
}

// GetGroup handles GET /api/auth/admin/groups/{id}.
func (h *Handler) GetGroup(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:read") {
		return
	}
	id := chi.URLParam(r, "id")
	g, err := h.svc.Get(r.Context(), id)
	if err != nil {
		httputil.WriteError(w, http.StatusNotFound, "NOT_FOUND", "group not found")
		return
	}
	httputil.WriteJSON(w, http.StatusOK, g)
}

// RenameGroup handles PATCH /api/auth/admin/groups/{id}.
func (h *Handler) RenameGroup(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:rename") {
		return
	}
	id := chi.URLParam(r, "id")
	var req struct {
		Name        string  `json:"name"`
		Description *string `json:"description"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name is required")
		return
	}
	g, err := h.svc.Rename(r.Context(), id, req.Name, req.Description)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if h.audit != nil {
		claims := middleware.ClaimsFromContext(r.Context())
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventGroupRenamed,
			Metadata: map[string]any{
				"group_id":   id,
				"group_name": req.Name,
			},
		})
	}
	httputil.WriteJSON(w, http.StatusOK, g)
}

// DeleteGroup handles DELETE /api/auth/admin/groups/{id}.
func (h *Handler) DeleteGroup(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:delete") {
		return
	}
	id := chi.URLParam(r, "id")
	if err := h.svc.Delete(r.Context(), id); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	if h.audit != nil {
		claims := middleware.ClaimsFromContext(r.Context())
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventGroupDeleted,
			Metadata: map[string]any{
				"group_id": id,
			},
		})
	}
	w.WriteHeader(http.StatusNoContent)
}

// AddMember handles POST /api/auth/admin/groups/{id}/members.
func (h *Handler) AddMember(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:add-member") {
		return
	}
	id := chi.URLParam(r, "id")
	var req struct {
		MemberType string `json:"member_type"`
		MemberID   string `json:"member_id"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.MemberType != "user" && req.MemberType != "group" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "member_type must be 'user' or 'group'")
		return
	}
	if req.MemberID == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "member_id is required")
		return
	}
	if err := h.svc.AddMember(r.Context(), id, req.MemberType, req.MemberID); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	if h.audit != nil {
		claims := middleware.ClaimsFromContext(r.Context())
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventGroupMemberAdded,
			Metadata: map[string]any{
				"group_id":    id,
				"member_type": req.MemberType,
				"member_id":   req.MemberID,
			},
		})
	}
	w.WriteHeader(http.StatusNoContent)
}

// RemoveMember handles DELETE /api/auth/admin/groups/{id}/members/{type}/{memberID}.
func (h *Handler) RemoveMember(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:remove-member") {
		return
	}
	id := chi.URLParam(r, "id")
	memberType := chi.URLParam(r, "type")
	memberID := chi.URLParam(r, "memberID")
	if err := h.svc.RemoveMember(r.Context(), id, memberType, memberID); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if h.audit != nil {
		claims := middleware.ClaimsFromContext(r.Context())
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventGroupMemberRemoved,
			Metadata: map[string]any{
				"group_id":    id,
				"member_type": memberType,
				"member_id":   memberID,
			},
		})
	}
	w.WriteHeader(http.StatusNoContent)
}

// AssignRole handles POST /api/auth/admin/groups/{id}/roles/{roleID}.
func (h *Handler) AssignRole(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:assign-role") {
		return
	}
	id := chi.URLParam(r, "id")
	roleID := chi.URLParam(r, "roleID")
	if err := h.svc.AssignRole(r.Context(), id, roleID); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if h.audit != nil {
		claims := middleware.ClaimsFromContext(r.Context())
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventGroupRoleAssigned,
			Metadata: map[string]any{
				"group_id": id,
				"role_id":  roleID,
			},
		})
	}
	w.WriteHeader(http.StatusNoContent)
}

// GetUserGroups handles GET /api/auth/users/{id}/groups.
// Returns all group IDs the specified user belongs to (direct + nested).
// Any authenticated user may call this for themselves; owners/admins can call it for any user.
func (h *Handler) GetUserGroups(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	userID := chi.URLParam(r, "id")
	// Allow own lookup, or require admin permission for cross-user lookups.
	if claims.Subject != userID && claims.Role != "builtin:instance-owner" {
		if h.authzSvc == nil {
			httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "forbidden")
			return
		}
		result, err := h.authzSvc.Check(r.Context(), authz.CheckRequest{
			UserID: claims.Subject,
			Action: "user:read",
		})
		if err != nil || !result.Allowed {
			httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "forbidden")
			return
		}
	}
	groupIDs, err := h.svc.GetUserGroupIDs(r.Context(), userID)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if groupIDs == nil {
		groupIDs = []string{}
	}
	httputil.WriteJSON(w, http.StatusOK, map[string][]string{"group_ids": groupIDs})
}

// RemoveRole handles DELETE /api/auth/admin/groups/{id}/roles/{roleID}.
func (h *Handler) RemoveRole(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:unassign-role") {
		return
	}
	id := chi.URLParam(r, "id")
	roleID := chi.URLParam(r, "roleID")
	if err := h.svc.RemoveRole(r.Context(), id, roleID); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if h.audit != nil {
		claims := middleware.ClaimsFromContext(r.Context())
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventGroupRoleRemoved,
			Metadata: map[string]any{
				"group_id": id,
				"role_id":  roleID,
			},
		})
	}
	w.WriteHeader(http.StatusNoContent)
}

// SearchDirectory handles GET /api/auth/directory/groups?search=.
// Any authenticated user may call this. Returns non-hidden groups.
func (h *Handler) SearchDirectory(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	q := r.URL.Query().Get("search")
	groups, err := h.svc.SearchDirectory(r.Context(), q)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "search failed")
		return
	}
	if groups == nil {
		groups = []*Group{}
	}
	httputil.WriteJSON(w, http.StatusOK, groups)
}

// SetHideFromSearch handles PATCH /api/auth/admin/groups/{id}/hide-from-search.
// Requires group:rename permission. Body: {"hide": true|false}.
func (h *Handler) SetHideFromSearch(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "group:rename") {
		return
	}
	id := chi.URLParam(r, "id")
	var req struct {
		Hide bool `json:"hide"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if err := h.svc.SetHideFromSearch(r.Context(), id, req.Hide); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
