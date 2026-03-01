package session

import (
	"encoding/json"
	"net"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// RefreshCookieName is the name of the HttpOnly cookie used to store
// the refresh token. Shared with bootstrap/handler.go for initial token issuance.
const RefreshCookieName = "auth_refresh"

// Handler serves auth endpoints.
type Handler struct {
	svc          *Service
	secureCookie bool // false only in tests
}

// NewHandler constructs the session handler.
func NewHandler(svc *Service, secureCookie bool) *Handler {
	return &Handler{svc: svc, secureCookie: secureCookie}
}

// Register handles POST /api/auth/register.
func (h *Handler) Register(w http.ResponseWriter, r *http.Request) {
	var req struct {
		InvitationID string `json:"invitation_id"`
		Email        string `json:"email"`
		DisplayName  string `json:"display_name"`
		Password     string `json:"password"`
		DeviceName   string `json:"device_name"`
		Platform     string `json:"platform"`
		Fingerprint  string `json:"fingerprint"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}

	if req.InvitationID == "" || req.Email == "" || req.Password == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invitation_id, email, and password are required")
		return
	}

	pair, err := h.svc.Register(r.Context(), SessionRegisterParams{
		InvitationID: req.InvitationID,
		Email:        req.Email,
		DisplayName:  req.DisplayName,
		Password:     req.Password,
		DeviceName:   req.DeviceName,
		Platform:     req.Platform,
		Fingerprint:  req.Fingerprint,
		UserAgent:    r.UserAgent(),
		IPAddress:    remoteIP(r),
	})
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}

	h.setRefreshCookie(w, pair.RefreshToken, pair.ExpiresAt)
	httputil.WriteJSON(w, http.StatusCreated, map[string]string{
		"access_token": pair.AccessToken,
	})
}

// Login handles POST /api/auth/login.
func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email       string `json:"email"`
		Password    string `json:"password"`
		DeviceName  string `json:"device_name"`
		Platform    string `json:"platform"`
		Fingerprint string `json:"fingerprint"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}

	pair, err := h.svc.Login(r.Context(), LoginParams{
		Email:       req.Email,
		Password:    req.Password,
		DeviceName:  req.DeviceName,
		Platform:    req.Platform,
		Fingerprint: req.Fingerprint,
		UserAgent:   r.UserAgent(),
		IPAddress:   remoteIP(r),
	})
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}

	h.setRefreshCookie(w, pair.RefreshToken, pair.ExpiresAt)
	httputil.WriteJSON(w, http.StatusOK, map[string]string{
		"access_token": pair.AccessToken,
	})
}

// Refresh handles POST /api/auth/refresh.
// Reads the refresh token from the HttpOnly cookie (web) or Authorization header (mobile).
func (h *Handler) Refresh(w http.ResponseWriter, r *http.Request) {
	raw := refreshTokenFromRequest(r)
	if raw == "" {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "no refresh token")
		return
	}

	pair, err := h.svc.Refresh(r.Context(), raw)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}

	h.setRefreshCookie(w, pair.RefreshToken, pair.ExpiresAt)
	httputil.WriteJSON(w, http.StatusOK, map[string]string{
		"access_token": pair.AccessToken,
	})
}

// Logout handles POST /api/auth/logout.
func (h *Handler) Logout(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if err := h.svc.Logout(r.Context(), claims.Subject, claims.DeviceID); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}
	h.clearRefreshCookie(w)
	w.WriteHeader(http.StatusNoContent)
}

// LogoutAll handles POST /api/auth/logout-all.
func (h *Handler) LogoutAll(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if err := h.svc.LogoutAll(r.Context(), claims.Subject); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}
	h.clearRefreshCookie(w)
	w.WriteHeader(http.StatusNoContent)
}

// Validate handles GET /api/auth/validate — called by Luma on every request.
func (h *Handler) Validate(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	u, err := h.svc.GetUser(r.Context(), claims.Subject)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "could not load user")
		return
	}

	httputil.WriteJSON(w, http.StatusOK, map[string]string{
		"user_id":       u.ID,
		"email":         u.Email,
		"display_name":  u.DisplayName,
		"instance_role": u.InstanceRoleID,
		"device_id":     claims.DeviceID,
	})
}

// RevokeUserSessions handles DELETE /api/auth/admin/users/{id}/sessions — owner only.
func (h *Handler) RevokeUserSessions(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}

	targetID := chi.URLParam(r, "id")
	if err := h.svc.LogoutAll(r.Context(), targetID); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *Handler) setRefreshCookie(w http.ResponseWriter, raw string, expires time.Time) {
	http.SetCookie(w, &http.Cookie{
		Name:     RefreshCookieName,
		Value:    raw,
		Path:     "/api/auth/refresh",
		Expires:  expires,
		MaxAge:   int(time.Until(expires).Seconds()),
		HttpOnly: true,
		Secure:   h.secureCookie,
		SameSite: http.SameSiteStrictMode,
	})
}

func (h *Handler) clearRefreshCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     RefreshCookieName,
		Value:    "",
		Path:     "/api/auth/refresh",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   h.secureCookie,
		SameSite: http.SameSiteStrictMode,
	})
}

// refreshTokenFromRequest extracts the raw refresh token from either the
// HttpOnly cookie (web clients) or X-Refresh-Token header (mobile clients).
func refreshTokenFromRequest(r *http.Request) string {
	if c, err := r.Cookie(RefreshCookieName); err == nil {
		return c.Value
	}
	return r.Header.Get("X-Refresh-Token")
}

func errorCode(err error) string {
	return pkgerrors.ErrorCode(err)
}


// remoteIP strips the port from r.RemoteAddr so it can be stored as INET.
func remoteIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr // already just an IP (unusual but safe)
	}
	return host
}
