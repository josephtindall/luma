package bootstrap

import (
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"time"

	"github.com/josephtindall/luma-auth/internal/authz"
	"github.com/josephtindall/luma-auth/internal/session"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// Handler serves the setup wizard API endpoints.
// All handlers call the Service — which re-checks state internally (third layer).
type Handler struct {
	svc      *Service
	issuer   session.Issuer
	authzSvc authz.Authorizer
}

// NewHandler constructs the setup handler.
// issuer is called after owner creation to issue the initial token pair.
func NewHandler(svc *Service, issuer session.Issuer) *Handler {
	return &Handler{svc: svc, issuer: issuer}
}

// SetAuthorizer injects the authz evaluator.
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

// VerifyToken handles POST /api/setup/verify-token (Step 1).
// Transitions UNCLAIMED → SETUP on a valid token.
func (h *Handler) VerifyToken(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Token string `json:"token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil || req.Token == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "token required")
		return
	}

	if err := h.svc.VerifyToken(r.Context(), req.Token); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ConfigureInstance handles POST /api/setup/instance (Step 2).
func (h *Handler) ConfigureInstance(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name     string `json:"name"`
		Locale   string `json:"locale"`
		Timezone string `json:"timezone"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.Name == "" || req.Locale == "" || req.Timezone == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "name, locale, and timezone are required")
		return
	}

	if err := h.svc.ConfigureInstance(r.Context(), req.Name, req.Locale, req.Timezone); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// CreateOwner handles POST /api/setup/owner (Step 3).
// Creates the owner user, atomically transitions to ACTIVE, then issues the
// first token pair so the owner lands directly on the dashboard.
func (h *Handler) CreateOwner(w http.ResponseWriter, r *http.Request) {
	var req struct {
		DisplayName  string `json:"display_name"`
		Email        string `json:"email"`
		Password     string `json:"password"`
		Confirmed    bool   `json:"confirmed"`
		InstanceName string `json:"instance_name"`
		Locale       string `json:"locale"`
		Timezone     string `json:"timezone"`
		DeviceName   string `json:"device_name"`
		Platform     string `json:"platform"`
		Fingerprint  string `json:"fingerprint"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if !req.Confirmed {
		httputil.WriteError(w, http.StatusBadRequest, "CONFIRMATION_REQUIRED",
			"explicit acknowledgment is required")
		return
	}
	if req.DisplayName == "" || req.Email == "" || req.Password == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST",
			"display_name, email, and password are required")
		return
	}
	if req.Platform == "" {
		req.Platform = "web"
	}
	if req.DeviceName == "" {
		req.DeviceName = "Browser"
	}
	if req.Fingerprint == "" {
		req.Fingerprint = "bootstrap-" + req.Email // fallback for wizard flow
	}

	// Service hashes the password and runs the atomic DB transaction.
	userID, err := h.svc.CreateOwner(r.Context(), CreateOwnerParams{
		DisplayName:  req.DisplayName,
		Email:        req.Email,
		PasswordHash: req.Password, // raw password passed in; service hashes it
		InstanceName: req.InstanceName,
		Locale:       req.Locale,
		Timezone:     req.Timezone,
	})
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}

	// Issue the first token pair — owner lands directly on the dashboard.
	pair, err := h.issuer.IssueForUser(r.Context(), session.IssueForUserParams{
		UserID:      userID,
		DeviceName:  req.DeviceName,
		Platform:    req.Platform,
		Fingerprint: req.Fingerprint,
		UserAgent:   r.UserAgent(),
		IPAddress:   remoteIP(r),
	})
	if err != nil {
		// Instance is ACTIVE but token issuance failed — non-fatal.
		httputil.WriteError(w, http.StatusInternalServerError, "TOKEN_ERROR",
			"owner created but token issuance failed; please log in manually")
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     session.RefreshCookieName,
		Value:    pair.RefreshToken,
		Path:     "/api/auth/refresh",
		Expires:  pair.ExpiresAt,
		MaxAge:   int(time.Until(pair.ExpiresAt).Seconds()),
		HttpOnly: true,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
	})

	httputil.WriteJSON(w, http.StatusCreated, map[string]string{
		"access_token": pair.AccessToken,
		"user_id":      userID,
	})
}

// GetInstanceSettings handles GET /api/auth/admin/instance-settings.
func (h *Handler) GetInstanceSettings(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "instance:read") {
		return
	}

	state, err := h.svc.GetSettings(r.Context())
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, instanceSettingsResponse(state))
}

// UpdateInstanceSettings handles PATCH /api/auth/admin/instance-settings.
func (h *Handler) UpdateInstanceSettings(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "instance:configure") {
		return
	}

	var req struct {
		Name                     *string `json:"name"`
		PasswordMinLength        *int    `json:"password_min_length"`
		PasswordRequireUppercase *bool   `json:"password_require_uppercase"`
		PasswordRequireLowercase *bool   `json:"password_require_lowercase"`
		PasswordRequireNumbers   *bool   `json:"password_require_numbers"`
		PasswordRequireSymbols   *bool   `json:"password_require_symbols"`
		PasswordHistoryCount     *int    `json:"password_history_count"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}

	state, err := h.svc.UpdateSettings(r.Context(), InstanceSettingsParams{
		Name:                     req.Name,
		PasswordMinLength:        req.PasswordMinLength,
		PasswordRequireUppercase: req.PasswordRequireUppercase,
		PasswordRequireLowercase: req.PasswordRequireLowercase,
		PasswordRequireNumbers:   req.PasswordRequireNumbers,
		PasswordRequireSymbols:   req.PasswordRequireSymbols,
		PasswordHistoryCount:     req.PasswordHistoryCount,
	})
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, instanceSettingsResponse(state))
}

func instanceSettingsResponse(s *InstanceState) map[string]any {
	return map[string]any{
		"name":                       s.Name,
		"password_min_length":        s.PasswordMinLength,
		"password_require_uppercase": s.PasswordRequireUppercase,
		"password_require_lowercase": s.PasswordRequireLowercase,
		"password_require_numbers":   s.PasswordRequireNumbers,
		"password_require_symbols":   s.PasswordRequireSymbols,
		"password_history_count":     s.PasswordHistoryCount,
	}
}

// ── helpers ───────────────────────────────────────────────────────────────────

func errorCode(err error) string {
	if err == nil {
		return ""
	}
	switch {
	case pkgerrors.Is(err, pkgerrors.ErrSetupComplete):
		return "SETUP_COMPLETE"
	case pkgerrors.Is(err, pkgerrors.ErrTokenExpired):
		return "SETUP_EXPIRED"
	case pkgerrors.Is(err, pkgerrors.ErrInvalidCredentials):
		return "INVALID_TOKEN"
	case pkgerrors.Is(err, pkgerrors.ErrPasswordTooShort):
		return "PASSWORD_TOO_SHORT"
	case pkgerrors.Is(err, pkgerrors.ErrSetupRequired):
		return "SETUP_REQUIRED"
	case errors.Is(err, ErrInvalidName):
		return "INVALID_NAME"
	default:
		return "INTERNAL_ERROR"
	}
}


// remoteIP strips the port from r.RemoteAddr so it can be stored as INET.
func remoteIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
