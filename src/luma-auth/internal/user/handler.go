package user

import (
	"context"
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
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
}

// NewHandler constructs the user handler.
func NewHandler(svc *Service, sessions SessionTerminator) *Handler {
	return &Handler{svc: svc, sessions: sessions}
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

// ListUsers handles GET /api/auth/admin/users — owner only.
// Returns {"users":[...],"total":N}.
func (h *Handler) ListUsers(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
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

// AdminCreate handles POST /api/auth/admin/users — owner only.
// Creates a user without an invitation. Returns 201 with the AdminUser projection.
func (h *Handler) AdminCreate(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}

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

// LockUser handles POST /api/auth/admin/users/{id}/lock — owner only.
func (h *Handler) LockUser(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}

	id := chi.URLParam(r, "id")
	if err := h.svc.LockAccount(r.Context(), id, claims.Subject); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	// Revoke all sessions for the locked user immediately.
	_ = h.sessions.LogoutAll(r.Context(), id)

	w.WriteHeader(http.StatusNoContent)
}

// UnlockUser handles DELETE /api/auth/admin/users/{id}/lock — owner only.
func (h *Handler) UnlockUser(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}
	id := chi.URLParam(r, "id")
	if err := h.svc.UnlockAccount(r.Context(), id, claims.Subject); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ForcePasswordChange handles POST /api/auth/admin/users/{id}/force-password-change — owner only.
// Sets force_password_change = true and revokes all sessions for the user.
func (h *Handler) ForcePasswordChange(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}
	id := chi.URLParam(r, "id")
	if err := h.svc.SetForcePasswordChange(r.Context(), id, claims.Subject, true); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
