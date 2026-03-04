package mfa

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

// SessionIssuer issues token pairs after MFA verification.
// Satisfied by session.Service.
type SessionIssuer interface {
	IssueForDevice(ctx context.Context, userID, deviceID, ipAddress, userAgent string) (accessToken, refreshToken string, expiresAt time.Time, err error)
}

// Handler serves MFA endpoints.
type Handler struct {
	svc          *Service
	sessions     SessionIssuer
	secureCookie bool
}

// NewHandler constructs the MFA handler.
func NewHandler(svc *Service, sessions SessionIssuer, secureCookie bool) *Handler {
	return &Handler{svc: svc, sessions: sessions, secureCookie: secureCookie}
}

// ── TOTP management (Bearer required) ───────────────────────────────────────

// SetupTOTP handles POST /api/auth/mfa/totp/setup.
func (h *Handler) SetupTOTP(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	var req struct {
		Name string `json:"name"`
	}
	// Body is optional — name defaults to "Authenticator" in the service.
	_ = json.NewDecoder(r.Body).Decode(&req)

	result, err := h.svc.SetupTOTP(r.Context(), claims.Subject, req.Name)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	httputil.WriteJSON(w, http.StatusOK, map[string]string{
		"id":          result.ID,
		"secret":      result.Secret,
		"otpauth_uri": result.OTPAuthURI,
	})
}

// ConfirmTOTP handles POST /api/auth/mfa/totp/confirm.
func (h *Handler) ConfirmTOTP(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	var req struct {
		ID   string `json:"id"`
		Code string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.ID == "" || req.Code == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "id and code are required")
		return
	}

	if err := h.svc.ConfirmTOTP(r.Context(), claims.Subject, req.ID, req.Code); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	httputil.WriteJSON(w, http.StatusOK, map[string]bool{"enabled": true})
}

// ListTOTP handles GET /api/auth/mfa/totp.
func (h *Handler) ListTOTP(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	secrets, err := h.svc.ListTOTPSecrets(r.Context(), claims.Subject)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	type totpResponse struct {
		ID        string    `json:"id"`
		Name      string    `json:"name"`
		CreatedAt time.Time `json:"created_at"`
	}

	result := make([]totpResponse, 0, len(secrets))
	for _, s := range secrets {
		result = append(result, totpResponse{
			ID:        s.ID,
			Name:      s.Name,
			CreatedAt: s.CreatedAt,
		})
	}

	httputil.WriteJSON(w, http.StatusOK, result)
}

// RemoveTOTP handles DELETE /api/auth/mfa/totp/{id}.
func (h *Handler) RemoveTOTP(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	secretID := chi.URLParam(r, "id")
	if secretID == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "missing totp id")
		return
	}

	var req struct {
		Password string `json:"password"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.Password == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "password is required")
		return
	}

	if err := h.svc.RemoveTOTP(r.Context(), claims.Subject, secretID, req.Password); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ── MFA challenge verification (unauthenticated, rate-limited) ──────────────

// VerifyMFA handles POST /api/auth/mfa/verify.
func (h *Handler) VerifyMFA(w http.ResponseWriter, r *http.Request) {
	var req struct {
		MFAToken string `json:"mfa_token"`
		Code     string `json:"code"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.MFAToken == "" || req.Code == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "mfa_token and code are required")
		return
	}

	userID, deviceID, err := h.svc.VerifyChallenge(r.Context(), req.MFAToken, req.Code, remoteIP(r))
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
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

// ── Passkey management (Bearer required) ────────────────────────────────────

// ListPasskeys handles GET /api/auth/passkeys.
func (h *Handler) ListPasskeys(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	passkeys, err := h.svc.ListPasskeys(r.Context(), claims.Subject)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	type passkeyResponse struct {
		ID        string    `json:"id"`
		Name      string    `json:"name"`
		CreatedAt time.Time `json:"created_at"`
	}

	result := make([]passkeyResponse, 0, len(passkeys))
	for _, p := range passkeys {
		result = append(result, passkeyResponse{
			ID:        p.ID,
			Name:      p.Name,
			CreatedAt: p.CreatedAt,
		})
	}

	httputil.WriteJSON(w, http.StatusOK, result)
}

// RevokePasskey handles DELETE /api/auth/passkeys/{id}.
func (h *Handler) RevokePasskey(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	passkeyID := chi.URLParam(r, "id")
	if passkeyID == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "missing passkey id")
		return
	}

	if err := h.svc.RevokePasskey(r.Context(), claims.Subject, passkeyID); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// ── Passkey registration ceremonies (Bearer required) ───────────────────────

// BeginRegistration handles POST /api/auth/passkeys/register/begin.
// Returns PublicKeyCredentialCreationOptions for navigator.credentials.create().
func (h *Handler) BeginRegistration(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	var req struct {
		Name string `json:"name"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)

	creation, err := h.svc.BeginRegistration(r.Context(), claims.Subject, req.Name)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	httputil.WriteJSON(w, http.StatusOK, creation)
}

// FinishRegistration handles POST /api/auth/passkeys/register/finish.
// Validates the attestation response and stores the credential.
func (h *Handler) FinishRegistration(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	passkey, err := h.svc.FinishRegistration(r.Context(), claims.Subject, r)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	httputil.WriteJSON(w, http.StatusOK, map[string]any{
		"id":         passkey.ID,
		"name":       passkey.Name,
		"created_at": passkey.CreatedAt,
	})
}

// ── Passkey login ceremonies (unauthenticated, rate-limited) ────────────────

// BeginLogin handles POST /api/auth/passkeys/login/begin.
// Returns PublicKeyCredentialRequestOptions for navigator.credentials.get().
func (h *Handler) BeginLogin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		MFAToken string `json:"mfa_token"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}
	if req.MFAToken == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "mfa_token is required")
		return
	}

	userID, _, err := h.svc.LookupChallenge(r.Context(), req.MFAToken)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	assertion, err := h.svc.BeginLogin(r.Context(), userID)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	httputil.WriteJSON(w, http.StatusOK, assertion)
}

// FinishLogin handles POST /api/auth/passkeys/login/finish.
// Verifies the assertion, issues tokens, and sets the refresh cookie.
func (h *Handler) FinishLogin(w http.ResponseWriter, r *http.Request) {
	// The MFA token is passed as a query parameter since the body is the
	// WebAuthn assertion response that must be forwarded raw to the library.
	mfaToken := r.URL.Query().Get("mfa_token")
	if mfaToken == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "mfa_token query parameter is required")
		return
	}

	userID, deviceID, err := h.svc.LookupChallenge(r.Context(), mfaToken)
	if err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	if err := h.svc.FinishLogin(r.Context(), userID, remoteIP(r), r.UserAgent(), r); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}

	// Consume the MFA challenge now that login succeeded.
	_ = h.svc.ConsumeChallenge(r.Context(), mfaToken)

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

// ── Helpers ─────────────────────────────────────────────────────────────────

const refreshCookieName = "auth_refresh"

func (h *Handler) setRefreshCookie(w http.ResponseWriter, raw string, expires time.Time) {
	http.SetCookie(w, &http.Cookie{
		Name:     refreshCookieName,
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
