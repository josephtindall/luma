package recoverytoken

import (
	"context"
	"encoding/json"
	"net"
	"net/http"
	"time"

	"github.com/josephtindall/luma-auth/internal/session"
	"github.com/josephtindall/luma-auth/internal/user"
	"github.com/josephtindall/luma-auth/pkg/crypto"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// PasswordSetter is a narrow interface for setting a password without the
// current password check. Satisfied by user.Service.SetPasswordDirect.
type PasswordSetter interface {
	SetPasswordDirect(ctx context.Context, userID, newPassword string) error
}

// Handler serves recovery token endpoints.
type Handler struct {
	svc          *Service
	users        user.Repository
	passwords    PasswordSetter
	issuer       session.Issuer
	secureCookie bool
}

// NewHandler constructs the recovery token handler.
func NewHandler(
	svc *Service,
	users user.Repository,
	passwords PasswordSetter,
	issuer session.Issuer,
	secureCookie bool,
) *Handler {
	return &Handler{
		svc:          svc,
		users:        users,
		passwords:    passwords,
		issuer:       issuer,
		secureCookie: secureCookie,
	}
}

// GetStatus handles GET /api/auth/recovery/status.
// Returns whether the authenticated user has a stored recovery token.
func (h *Handler) GetStatus(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	has, err := h.svc.HasToken(r.Context(), claims.Subject)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, map[string]bool{"has_token": has})
}

// Generate handles POST /api/auth/recovery/generate.
// Generates (or regenerates) a recovery token for the authenticated user.
// When a token already exists, current_password must be supplied to prove ownership.
func (h *Handler) Generate(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	var req struct {
		CurrentPassword string `json:"current_password"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)

	// If user already has a token, require password verification before replacing it.
	has, err := h.svc.HasToken(r.Context(), claims.Subject)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	if has {
		if req.CurrentPassword == "" {
			httputil.WriteError(w, http.StatusBadRequest, "PASSWORD_REQUIRED",
				"current_password is required to regenerate a recovery token")
			return
		}
		u, err := h.users.GetByID(r.Context(), claims.Subject)
		if err != nil {
			httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to load user")
			return
		}
		ok, err := crypto.VerifyPassword(req.CurrentPassword, u.PasswordHash)
		if err != nil || !ok {
			httputil.WriteError(w, http.StatusForbidden, "INVALID_PASSWORD", "incorrect password")
			return
		}
	}

	raw, err := h.svc.Generate(r.Context(), claims.Subject)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, map[string]string{"token": raw})
}

// ResetPassword handles POST /api/auth/recovery/reset-password.
// Unauthenticated. Verifies the recovery token, sets a new password,
// and issues a fresh session.
func (h *Handler) ResetPassword(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email       string `json:"email"`
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
	if req.Email == "" || req.Token == "" || req.NewPassword == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST",
			"email, token, and new_password are required")
		return
	}

	u, err := h.users.GetByEmail(r.Context(), req.Email)
	if err != nil {
		// Anti-enumeration: same error whether email exists or not.
		httputil.WriteError(w, http.StatusUnauthorized, "INVALID_TOKEN", "invalid recovery token")
		return
	}

	// Normalize token: strip spaces/dashes so users can paste formatted tokens.
	rawToken := normalizeToken(req.Token)

	ok, err := h.svc.VerifyAndConsume(r.Context(), u.ID, rawToken)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "token verification failed")
		return
	}
	if !ok {
		httputil.WriteError(w, http.StatusUnauthorized, "INVALID_TOKEN", "invalid recovery token")
		return
	}

	if err := h.passwords.SetPasswordDirect(r.Context(), u.ID, req.NewPassword); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to set password")
		return
	}

	if req.Platform == "" {
		req.Platform = "web"
	}
	if req.DeviceName == "" {
		req.DeviceName = "Browser"
	}
	if req.Fingerprint == "" {
		req.Fingerprint = "recovery-" + u.ID
	}

	pair, err := h.issuer.IssueForUser(r.Context(), session.IssueForUserParams{
		UserID:      u.ID,
		DeviceName:  req.DeviceName,
		Platform:    req.Platform,
		Fingerprint: req.Fingerprint,
		UserAgent:   r.UserAgent(),
		IPAddress:   remoteIP(r),
	})
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "session issuance failed")
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:     session.RefreshCookieName,
		Value:    pair.RefreshToken,
		Path:     "/api/auth/refresh",
		Expires:  pair.ExpiresAt,
		MaxAge:   int(time.Until(pair.ExpiresAt).Seconds()),
		HttpOnly: true,
		Secure:   h.secureCookie,
		SameSite: http.SameSiteStrictMode,
	})
	httputil.WriteJSON(w, http.StatusOK, map[string]string{
		"access_token": pair.AccessToken,
	})
}

// normalizeToken strips non-digit characters so users can paste formatted codes.
func normalizeToken(s string) string {
	out := make([]byte, 0, len(s))
	for i := range len(s) {
		c := s[i]
		if c >= '0' && c <= '9' {
			out = append(out, c)
		}
	}
	return string(out)
}

func remoteIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
