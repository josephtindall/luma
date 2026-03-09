package passwordreset

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// DeviceEnsurer finds or creates a device for a given user.
// Satisfied by session.Service.
type DeviceEnsurer interface {
	EnsureDevice(ctx context.Context, userID, fingerprint, deviceName, platform, userAgent string) (deviceID string, err error)
}

// SessionIssuer issues token pairs after authentication.
// Satisfied by session.Service.
type SessionIssuer interface {
	IssueForDevice(ctx context.Context, userID, deviceID, ipAddress, userAgent string) (accessToken, refreshToken string, expiresAt time.Time, err error)
}

// Handler serves password-reset HTTP endpoints.
type Handler struct {
	svc          *Service
	devices      DeviceEnsurer
	sessions     SessionIssuer
	secureCookie bool
}

// NewHandler constructs the password-reset handler.
func NewHandler(svc *Service, devices DeviceEnsurer, sessions SessionIssuer, secureCookie bool) *Handler {
	return &Handler{svc: svc, devices: devices, sessions: sessions, secureCookie: secureCookie}
}

// AdminCreateResetToken handles POST /api/auth/admin/users/{id}/password-reset.
// Owner-only. Returns {"token": "<raw>", "expires_at": "..."}.
func (h *Handler) AdminCreateResetToken(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}

	userID := chi.URLParam(r, "id")
	rawToken, expiresAt, err := h.svc.CreateAdminResetToken(r.Context(), userID, claims.Subject)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	httputil.WriteJSON(w, http.StatusOK, map[string]any{
		"token":      rawToken,
		"expires_at": expiresAt,
	})
}

// ResetPassword handles POST /api/auth/reset-password (unauthenticated).
// Validates the token, changes the password, and issues a new session.
func (h *Handler) ResetPassword(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Token       string `json:"token"`
		NewPassword string `json:"new_password"`
		DeviceName  string `json:"device_name"`
		Platform    string `json:"platform"`
		Fingerprint string `json:"fingerprint"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.Token == "" || req.NewPassword == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "token and new_password are required")
		return
	}

	userID, err := h.svc.ResetPassword(r.Context(), req.Token, req.NewPassword)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	// Register or match the device.
	deviceID, err := h.devices.EnsureDevice(r.Context(), userID, req.Fingerprint, req.DeviceName, req.Platform, r.UserAgent())
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "device error")
		return
	}

	accessToken, refreshToken, expiresAt, err := h.sessions.IssueForDevice(r.Context(), userID, deviceID, remoteIP(r), r.UserAgent())
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to issue tokens")
		return
	}

	h.setRefreshCookie(w, refreshToken, expiresAt)
	httputil.WriteJSON(w, http.StatusOK, map[string]string{
		"access_token": accessToken,
	})
}

func (h *Handler) setRefreshCookie(w http.ResponseWriter, raw string, expires time.Time) {
	http.SetCookie(w, &http.Cookie{
		Name:     "auth_refresh",
		Value:    raw,
		Path:     "/api/auth/refresh",
		Expires:  expires,
		MaxAge:   int(time.Until(expires).Seconds()),
		HttpOnly: true,
		Secure:   h.secureCookie,
		SameSite: http.SameSiteStrictMode,
	})
}

func remoteIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
