package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"
)

// Handler is a transparent proxy for auth service endpoints.
// It does not decode request bodies (except login/refresh to extract the access token)
// and does not attach context-held tokens.
type Handler struct {
	client     *http.Client
	authURL    string
	userIDFunc func(context.Context) string
}

// NewHandler creates an auth proxy handler. httpClient must not be nil.
// userIDFunc extracts the authenticated user ID from context (set by auth
// middleware). It is used by UserRoutes to resolve /me to a real user ID.
func NewHandler(httpClient *http.Client, authURL string, userIDFunc func(context.Context) string) *Handler {
	return &Handler{
		client:     httpClient,
		authURL:    strings.TrimRight(authURL, "/"),
		userIDFunc: userIDFunc,
	}
}

// SetupRoutes returns a router for /api/luma/setup/* endpoints.
func (h *Handler) SetupRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/status", h.status)
	r.Post("/verify-token", h.proxySetup("POST", "/api/setup/verify-token"))
	r.Post("/configure", h.proxySetup("POST", "/api/setup/instance"))
	r.Post("/owner", h.createOwner)
	return r
}

// AuthRoutes returns a router for /api/luma/auth/* endpoints.
func (h *Handler) AuthRoutes() chi.Router {
	r := chi.NewRouter()
	r.Post("/login", h.login)
	r.Post("/refresh", h.refresh)
	r.Post("/logout", h.logout)
	return r
}

// UserRoutes returns a router for /api/luma/user/* endpoints.
// These proxy to the auth service's /users/me and related endpoints. The auth
// service enforces ownership on /users/me paths, so no authz.RequireCan() is needed.
func (h *Handler) UserRoutes() chi.Router {
	r := chi.NewRouter()
	// GET /me needs special handling: the auth service has GET /api/auth/users/{id}
	// but no GET /api/auth/users/me, so we resolve the real user ID from
	// the auth context and proxy to /api/auth/users/{id}.
	r.Get("/me", h.getMe)
	r.Put("/me/profile", h.proxyAuth("PUT", "/api/auth/users/me/profile"))
	r.Post("/me/password", h.proxyAuth("POST", "/api/auth/users/me/password"))
	r.Get("/me/preferences", h.proxyAuth("GET", "/api/auth/users/me/preferences"))
	r.Patch("/me/preferences", h.proxyAuth("PATCH", "/api/auth/users/me/preferences"))
	r.Get("/me/devices", h.proxyAuth("GET", "/api/auth/devices"))
	r.Delete("/me/devices/{id}", h.proxyAuthWithParam("DELETE", "/api/auth/devices/", "id"))
	r.Get("/me/audit", h.proxyAuth("GET", "/api/auth/audit/me"))
	return r
}

// getMe resolves the authenticated user's ID and proxies to auth service's
// GET /api/auth/users/{id} endpoint.
func (h *Handler) getMe(w http.ResponseWriter, r *http.Request) {
	userID := h.userIDFunc(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	h.proxyAuth("GET", "/api/auth/users/"+userID)(w, r)
}

// status probes auth service state.
// auth service 503 → {"state":"unclaimed"}
// auth service 401 → {"state":"active"}
// Connection error/timeout → HTTP 503 {"error":"auth service unavailable"}
// Unexpected status → HTTP 502
func (h *Handler) status(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, h.authURL+"/api/auth/validate", nil)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
		return
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusServiceUnavailable: // 503 — UNCLAIMED or SETUP
		writeJSON(w, http.StatusOK, map[string]string{"state": "unclaimed"})
	case http.StatusUnauthorized: // 401 — ACTIVE
		writeJSON(w, http.StatusOK, map[string]string{"state": "active"})
	default:
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": fmt.Sprintf("unexpected auth status: %d", resp.StatusCode)})
	}
}

// proxyAuth returns a handler that forwards the request to auth service with the
// caller's Authorization header. Used for /users/me endpoints where auth service
// enforces ownership.
func (h *Handler) proxyAuth(method, authPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		req, err := http.NewRequestWithContext(r.Context(), method, h.authURL+authPath, r.Body)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		req.Header.Set("Content-Type", r.Header.Get("Content-Type"))
		if auth := r.Header.Get("Authorization"); auth != "" {
			req.Header.Set("Authorization", auth)
		}

		resp, err := h.client.Do(req)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
			return
		}
		defer resp.Body.Close()

		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
	}
}

// proxyAuthWithParam returns a handler that appends a chi URL param to the
// auth service path and forwards the request with the caller's Authorization header.
func (h *Handler) proxyAuthWithParam(method, authPathPrefix, paramName string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		paramVal := chi.URLParam(r, paramName)
		if paramVal == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing " + paramName})
			return
		}

		req, err := http.NewRequestWithContext(r.Context(), method, h.authURL+authPathPrefix+paramVal, r.Body)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		req.Header.Set("Content-Type", r.Header.Get("Content-Type"))
		if auth := r.Header.Get("Authorization"); auth != "" {
			req.Header.Set("Authorization", auth)
		}

		resp, err := h.client.Do(req)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
			return
		}
		defer resp.Body.Close()

		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
	}
}

// proxySetup returns a handler that pipes the request body verbatim to auth service and
// forwards auth service's status code and response body verbatim.
func (h *Handler) proxySetup(method, authPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		req, err := http.NewRequestWithContext(r.Context(), method, h.authURL+authPath, r.Body)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		req.Header.Set("Content-Type", r.Header.Get("Content-Type"))

		resp, err := h.client.Do(req)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
			return
		}
		defer resp.Body.Close()

		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
	}
}

// createOwner forwards the owner creation request to auth service, rewrites the
// refresh cookie Path (like login does), and returns the access token to the browser.
func (h *Handler) createOwner(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, h.authURL+"/api/setup/owner", r.Body)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	req.Header.Set("Content-Type", r.Header.Get("Content-Type"))

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusCreated {
		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
		return
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	var payload map[string]interface{}
	if err := json.Unmarshal(body, &payload); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "invalid auth response"})
		return
	}

	rewriteCookies(w, resp, "/api/auth/refresh", "/api/luma/auth/refresh")

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	w.Write(body) //nolint:errcheck
}

// login forwards credentials to auth service, rewrites the refresh cookie Path, and
// returns {"access_token":"<value>"} to the browser.
func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, h.authURL+"/api/auth/login", r.Body)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	req.Header.Set("Content-Type", r.Header.Get("Content-Type"))

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
		return
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	var payload map[string]interface{}
	if err := json.Unmarshal(body, &payload); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "invalid auth response"})
		return
	}

	accessToken, _ := payload["access_token"].(string)

	// Rewrite Set-Cookie path from auth service's path to Luma's refresh path.
	rewriteCookies(w, resp, "/api/auth/refresh", "/api/luma/auth/refresh")

	writeJSON(w, http.StatusOK, map[string]string{"access_token": accessToken})
}

// refresh forwards the browser's cookie to auth service, rewrites the Set-Cookie path,
// and returns a new access token.
func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, h.authURL+"/api/auth/refresh", nil)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	// Forward the browser's cookie to auth service.
	if cookie := r.Header.Get("Cookie"); cookie != "" {
		req.Header.Set("Cookie", cookie)
	}

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
		return
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	var payload map[string]interface{}
	if err := json.Unmarshal(body, &payload); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "invalid auth response"})
		return
	}

	accessToken, _ := payload["access_token"].(string)

	rewriteCookies(w, resp, "/api/auth/refresh", "/api/luma/auth/refresh")

	writeJSON(w, http.StatusOK, map[string]string{"access_token": accessToken})
}

// logout forwards the browser cookie to auth service and proxies its response status
// and any Set-Cookie (which auth service uses to expire the cookie).
func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, h.authURL+"/api/auth/logout", nil)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	if cookie := r.Header.Get("Cookie"); cookie != "" {
		req.Header.Set("Cookie", cookie)
	}

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "auth service unavailable"})
		return
	}
	defer resp.Body.Close()

	// Forward any Set-Cookie headers (expiry cookies from auth service).
	for _, sc := range resp.Header["Set-Cookie"] {
		w.Header().Add("Set-Cookie", sc)
	}

	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body) //nolint:errcheck
}

// rewriteCookies reads Set-Cookie headers from the auth service response via resp.Cookies(),
// rewrites the Path attribute from oldPath to newPath, then sets them on the browser
// response. Using resp.Cookies() + manual serialisation avoids string-replacement bugs.
func rewriteCookies(w http.ResponseWriter, resp *http.Response, oldPath, newPath string) {
	for _, c := range resp.Cookies() {
		if c.Path == oldPath {
			c.Path = newPath
		}
		w.Header().Add("Set-Cookie", cookieString(c))
	}
}

// cookieString serialises a *http.Cookie to its Set-Cookie header string value.
// We build this manually because (*http.Cookie).String() produces the cookie's
// request-header form (name=value only), not its full Set-Cookie response form.
func cookieString(c *http.Cookie) string {
	var b strings.Builder
	b.WriteString(c.Name)
	b.WriteByte('=')
	b.WriteString(c.Value)

	if c.Path != "" {
		b.WriteString("; Path=")
		b.WriteString(c.Path)
	}
	if c.Domain != "" {
		b.WriteString("; Domain=")
		b.WriteString(c.Domain)
	}
	if !c.Expires.IsZero() {
		b.WriteString("; Expires=")
		b.WriteString(c.Expires.UTC().Format(time.RFC1123))
	}
	if c.MaxAge > 0 {
		b.WriteString(fmt.Sprintf("; Max-Age=%d", c.MaxAge))
	} else if c.MaxAge < 0 {
		b.WriteString("; Max-Age=0")
	}
	if c.HttpOnly {
		b.WriteString("; HttpOnly")
	}
	if c.Secure {
		b.WriteString("; Secure")
	}
	switch c.SameSite {
	case http.SameSiteStrictMode:
		b.WriteString("; SameSite=Strict")
	case http.SameSiteLaxMode:
		b.WriteString("; SameSite=Lax")
	case http.SameSiteNoneMode:
		b.WriteString("; SameSite=None")
	}
	return b.String()
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v) //nolint:errcheck
}
