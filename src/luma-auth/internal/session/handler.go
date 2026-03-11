package session

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/josephtindall/luma-auth/internal/audit"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// ForceChangeTokenCreator issues a short-lived token for the force-password-change flow.
// Satisfied by passwordreset.Service.
type ForceChangeTokenCreator interface {
	CreateForceChangeToken(ctx context.Context, userID string) (string, error)
}

// RecoveryTokenGenerator generates (or regenerates) a recovery token for a user.
// Satisfied by recoverytoken.Service.
type RecoveryTokenGenerator interface {
	Generate(ctx context.Context, userID string) (string, error)
}

// RefreshCookieName is the name of the HttpOnly cookie used to store
// the refresh token. Shared with bootstrap/handler.go for initial token issuance.
const RefreshCookieName = "auth_refresh"

// Handler serves auth endpoints.
type Handler struct {
	svc           *Service
	passwordReset ForceChangeTokenCreator // may be nil if feature not wired
	recovery      RecoveryTokenGenerator  // may be nil if feature not wired
	secureCookie  bool                    // false only in tests
	audit         audit.Service
}

// NewHandler constructs the session handler.
func NewHandler(svc *Service, passwordReset ForceChangeTokenCreator, secureCookie bool) *Handler {
	return &Handler{svc: svc, passwordReset: passwordReset, secureCookie: secureCookie}
}

// SetRecoveryGenerator injects the recovery token generator (called from main.go).
func (h *Handler) SetRecoveryGenerator(g RecoveryTokenGenerator) { h.recovery = g }

// SetAuditor injects the audit service.
func (h *Handler) SetAuditor(a audit.Service) { h.audit = a }

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
		UserAgent:    truncateUA(r.UserAgent()),
		IPAddress:    remoteIP(r),
	})
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}

	h.setRefreshCookie(w, pair.RefreshToken, pair.ExpiresAt)
	resp := map[string]string{"access_token": pair.AccessToken}
	if h.recovery != nil {
		if raw, err := h.recovery.Generate(r.Context(), pair.UserID); err == nil {
			resp["recovery_token"] = raw
		}
	}
	httputil.WriteJSON(w, http.StatusCreated, resp)
}

// Identify handles POST /api/auth/identify.
// Returns which MFA methods are available for the given email without
// requiring a password. Returns the same shape for unknown emails (anti-enumeration).
func (h *Handler) Identify(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email string `json:"email"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.Email == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "email is required")
		return
	}

	result, err := h.svc.Identify(r.Context(), req.Email)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "identify failed")
		return
	}

	httputil.WriteJSON(w, http.StatusOK, result)
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

	result, err := h.svc.Login(r.Context(), LoginParams{
		Email:       req.Email,
		Password:    req.Password,
		DeviceName:  req.DeviceName,
		Platform:    req.Platform,
		Fingerprint: req.Fingerprint,
		UserAgent:   truncateUA(r.UserAgent()),
		IPAddress:   remoteIP(r),
	})
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), errorCode(err), err.Error())
		return
	}

	if result.MFARequired {
		httputil.WriteJSON(w, http.StatusOK, map[string]any{
			"mfa_required": true,
			"mfa_token":    result.MFAToken,
			"methods":      result.MFAMethods,
		})
		return
	}

	if result.PasswordChangeRequired && h.passwordReset != nil {
		token, err := h.passwordReset.CreateForceChangeToken(r.Context(), result.UserID)
		if err != nil {
			httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to create change token")
			return
		}
		httputil.WriteJSON(w, http.StatusOK, map[string]any{
			"password_change_required": true,
			"change_token":             token,
		})
		return
	}

	h.setRefreshCookie(w, result.Pair.RefreshToken, result.Pair.ExpiresAt)
	httputil.WriteJSON(w, http.StatusOK, map[string]string{
		"access_token": result.Pair.AccessToken,
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
	if h.audit != nil {
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventAdminSessionsRevoked,
			Metadata: map[string]any{
				"target_user_id": targetID,
			},
		})
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

// truncateUA limits the User-Agent string to 512 bytes to prevent an
// oversized header from being stored in the audit log.
func truncateUA(ua string) string {
	if len(ua) > 512 {
		return ua[:512]
	}
	return ua
}
