package group

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// Handler serves group admin endpoints. All endpoints are owner-only.
type Handler struct {
	svc *Service
}

// NewHandler constructs the group handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) requireOwner(w http.ResponseWriter, r *http.Request) bool {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return false
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return false
	}
	return true
}

// ListGroups handles GET /api/auth/admin/groups.
func (h *Handler) ListGroups(w http.ResponseWriter, r *http.Request) {
	if !h.requireOwner(w, r) {
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
	if !h.requireOwner(w, r) {
		return
	}
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name is required")
		return
	}
	g, err := h.svc.Create(r.Context(), req.Name)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusCreated, g)
}

// GetGroup handles GET /api/auth/admin/groups/{id}.
func (h *Handler) GetGroup(w http.ResponseWriter, r *http.Request) {
	if !h.requireOwner(w, r) {
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
	if !h.requireOwner(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Name == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name is required")
		return
	}
	g, err := h.svc.Rename(r.Context(), id, req.Name)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, g)
}

// DeleteGroup handles DELETE /api/auth/admin/groups/{id}.
func (h *Handler) DeleteGroup(w http.ResponseWriter, r *http.Request) {
	if !h.requireOwner(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	if err := h.svc.Delete(r.Context(), id); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// AddMember handles POST /api/auth/admin/groups/{id}/members.
func (h *Handler) AddMember(w http.ResponseWriter, r *http.Request) {
	if !h.requireOwner(w, r) {
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
	w.WriteHeader(http.StatusNoContent)
}

// RemoveMember handles DELETE /api/auth/admin/groups/{id}/members/{type}/{memberID}.
func (h *Handler) RemoveMember(w http.ResponseWriter, r *http.Request) {
	if !h.requireOwner(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	memberType := chi.URLParam(r, "type")
	memberID := chi.URLParam(r, "memberID")
	if err := h.svc.RemoveMember(r.Context(), id, memberType, memberID); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// AssignRole handles POST /api/auth/admin/groups/{id}/roles/{roleID}.
func (h *Handler) AssignRole(w http.ResponseWriter, r *http.Request) {
	if !h.requireOwner(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	roleID := chi.URLParam(r, "roleID")
	if err := h.svc.AssignRole(r.Context(), id, roleID); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// RemoveRole handles DELETE /api/auth/admin/groups/{id}/roles/{roleID}.
func (h *Handler) RemoveRole(w http.ResponseWriter, r *http.Request) {
	if !h.requireOwner(w, r) {
		return
	}
	id := chi.URLParam(r, "id")
	roleID := chi.URLParam(r, "roleID")
	if err := h.svc.RemoveRole(r.Context(), id, roleID); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
