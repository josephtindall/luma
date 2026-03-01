package device

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// SessionRevoker is a narrow interface satisfied by session.Service.
// Defined here to avoid an import cycle (session imports device).
type SessionRevoker interface {
	Logout(ctx context.Context, userID, deviceID string) error
}

// Handler serves device management endpoints.
type Handler struct {
	svc      *Service
	sessions SessionRevoker
}

// NewHandler constructs the device handler.
func NewHandler(svc *Service, sessions SessionRevoker) *Handler {
	return &Handler{svc: svc, sessions: sessions}
}

// List handles GET /api/auth/devices.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	devices, err := h.svc.ListForUser(r.Context(), claims.Subject)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, devices)
}

// Revoke handles DELETE /api/auth/devices/{id}.
func (h *Handler) Revoke(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	deviceID := chi.URLParam(r, "id")
	if err := h.svc.Revoke(r.Context(), deviceID, claims.Subject); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	// Revoke all active sessions for this device immediately.
	_ = h.sessions.Logout(r.Context(), claims.Subject, deviceID)

	w.WriteHeader(http.StatusNoContent)
}

