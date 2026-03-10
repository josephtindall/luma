package user

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/josephtindall/luma-auth/internal/authz"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// SessionTerminator is a narrow interface satisfied by session.Service.
// Defined here to avoid an import cycle (session imports user).
type SessionTerminator interface {
	LogoutAll(ctx context.Context, userID string) error
}

// Handler serves all user-related HTTP endpoints.
type Handler struct {
	svc      *Service
	sessions SessionTerminator
	authzSvc authz.Authorizer
}

// NewHandler constructs the user handler.
func NewHandler(svc *Service, sessions SessionTerminator) *Handler {
	return &Handler{svc: svc, sessions: sessions}
}

// SetAuthorizer injects the authz evaluator (called after construction in main).
func (h *Handler) SetAuthorizer(a authz.Authorizer) { h.authzSvc = a }

// requirePerm returns true if the caller is allowed to perform action.
// Owners are always permitted. Non-owners are checked via the authz evaluator.
// Writes 401/403 and returns false on failure.
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

// AdminAccess handles GET /api/auth/admin/access.
// Returns 204 if the caller has user:read permission (owner or custom role), 403 otherwise.
// The frontend uses this to decide whether to show the Admin nav item.
func (h *Handler) AdminAccess(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "user:read") {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// AdminCapabilities handles GET /api/auth/admin/capabilities.
// Returns a JSON map of admin action strings to booleans.
// Used by the frontend to decide which admin tabs to show.
func (h *Handler) AdminCapabilities(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	isOwner := claims.Role == "builtin:instance-owner"
	actions := []string{"user:read", "invitation:list", "instance:read", "group:manage", "role:manage"}
	caps := map[string]any{"is_owner": isOwner}

	for _, action := range actions {
		if isOwner {
			caps[action] = true
		} else if h.authzSvc != nil {
			result, err := h.authzSvc.Check(r.Context(), authz.CheckRequest{
				UserID: claims.Subject,
				Action: action,
			})
			caps[action] = err == nil && result.Allowed
		} else {
			caps[action] = false
		}
	}
	httputil.WriteJSON(w, http.StatusOK, caps)
}

// GetUser handles GET /api/auth/users/{id}.
func (h *Handler) GetUser(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	u, err := h.svc.GetByID(r.Context(), id)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, u)
}

// UpdateProfile handles PUT /api/auth/users/me/profile.
func (h *Handler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	var req struct {
		DisplayName string `json:"display_name"`
		Email       string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}

	err := h.svc.UpdateProfile(r.Context(), claims.Subject, UpdateProfileParams{
		DisplayName: req.DisplayName,
		Email:       req.Email,
	})
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ChangePassword handles POST /api/auth/users/me/password.
func (h *Handler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	var req struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}

	err := h.svc.ChangePassword(r.Context(), claims.Subject, ChangePasswordParams{
		CurrentPassword: req.CurrentPassword,
		NewPassword:     req.NewPassword,
	})
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	// Revoke all sessions so the old password can't be used to refresh tokens.
	_ = h.sessions.LogoutAll(r.Context(), claims.Subject)

	w.WriteHeader(http.StatusNoContent)
}

// ListUsers handles GET /api/auth/admin/users.
// Returns {"users":[...],"total":N}.
func (h *Handler) ListUsers(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "user:read") {
		return
	}

	users, err := h.svc.ListUsers(r.Context(), 500, 0)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to list users")
		return
	}
	httputil.WriteJSON(w, http.StatusOK, map[string]any{
		"users": users,
		"total": len(users),
	})
}

// AdminCreate handles POST /api/auth/admin/users.
// Creates a user without an invitation. Returns 201 with the AdminUser projection.
func (h *Handler) AdminCreate(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "user:invite") {
		return
	}
	claims := middleware.ClaimsFromContext(r.Context())

	var req struct {
		Email               string `json:"email"`
		DisplayName         string `json:"display_name"`
		Password            string `json:"password"`
		ForcePasswordChange bool   `json:"force_password_change"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.Email == "" || req.Password == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "email and password are required")
		return
	}

	au, err := h.svc.AdminCreate(r.Context(), AdminCreateParams{
		Email:               req.Email,
		DisplayName:         req.DisplayName,
		Password:            req.Password,
		ForcePasswordChange: req.ForcePasswordChange,
	}, claims.Subject)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusCreated, au)
}

// LockUser handles POST /api/auth/admin/users/{id}/lock.
func (h *Handler) LockUser(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "user:lock") {
		return
	}
	claims := middleware.ClaimsFromContext(r.Context())

	id := chi.URLParam(r, "id")
	if err := h.svc.LockAccount(r.Context(), id, claims.Subject); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	// Revoke all sessions for the locked user immediately.
	_ = h.sessions.LogoutAll(r.Context(), id)

	w.WriteHeader(http.StatusNoContent)
}

// UnlockUser handles DELETE /api/auth/admin/users/{id}/lock.
func (h *Handler) UnlockUser(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "user:unlock") {
		return
	}
	claims := middleware.ClaimsFromContext(r.Context())
	id := chi.URLParam(r, "id")
	if err := h.svc.UnlockAccount(r.Context(), id, claims.Subject); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ForcePasswordChange handles POST /api/auth/admin/users/{id}/force-password-change.
// Sets force_password_change = true and revokes all sessions for the user.
func (h *Handler) ForcePasswordChange(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "user:edit") {
		return
	}
	claims := middleware.ClaimsFromContext(r.Context())
	id := chi.URLParam(r, "id")
	if err := h.svc.SetForcePasswordChange(r.Context(), id, claims.Subject, true); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
