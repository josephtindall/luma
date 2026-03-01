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

// Handler is a transparent proxy for Haven auth and setup endpoints.
// It does not decode request bodies (except login/refresh to extract the access token)
// and does not attach context-held tokens.
type Handler struct {
	client     *http.Client
	havenURL   string
	userIDFunc func(context.Context) string
}

// NewHandler creates an auth proxy handler. httpClient must not be nil.
// userIDFunc extracts the authenticated user ID from context (set by Haven
// middleware). It is used by UserRoutes to resolve /me to a real user ID.
func NewHandler(httpClient *http.Client, havenURL string, userIDFunc func(context.Context) string) *Handler {
	return &Handler{
		client:     httpClient,
		havenURL:   strings.TrimRight(havenURL, "/"),
		userIDFunc: userIDFunc,
	}
}

// SetupRoutes returns a router for /api/luma/setup/* endpoints.
func (h *Handler) SetupRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/status", h.status)
	r.Post("/verify-token", h.proxySetup("POST", "/api/setup/verify-token"))
	r.Post("/configure", h.proxySetup("POST", "/api/setup/instance"))
	r.Post("/owner", h.proxySetup("POST", "/api/setup/owner"))
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
// These proxy to Haven's /users/me and related endpoints. Haven enforces
// ownership on /users/me paths, so no authz.RequireCan() is needed.
func (h *Handler) UserRoutes() chi.Router {
	r := chi.NewRouter()
	// GET /me needs special handling: Haven has GET /api/haven/users/{id}
	// but no GET /api/haven/users/me, so we resolve the real user ID from
	// the auth context and proxy to /api/haven/users/{id}.
	r.Get("/me", h.getMe)
	r.Put("/me/profile", h.proxyAuth("PUT", "/api/haven/users/me/profile"))
	r.Post("/me/password", h.proxyAuth("POST", "/api/haven/users/me/password"))
	r.Get("/me/preferences", h.proxyAuth("GET", "/api/haven/users/me/preferences"))
	r.Patch("/me/preferences", h.proxyAuth("PATCH", "/api/haven/users/me/preferences"))
	r.Get("/me/devices", h.proxyAuth("GET", "/api/haven/devices"))
	r.Delete("/me/devices/{id}", h.proxyAuthWithParam("DELETE", "/api/haven/devices/", "id"))
	r.Get("/me/audit", h.proxyAuth("GET", "/api/haven/audit/me"))
	return r
}

// getMe resolves the authenticated user's ID and proxies to Haven's
// GET /api/haven/users/{id} endpoint.
func (h *Handler) getMe(w http.ResponseWriter, r *http.Request) {
	userID := h.userIDFunc(r.Context())
	if userID == "" {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
		return
	}
	h.proxyAuth("GET", "/api/haven/users/"+userID)(w, r)
}

// status probes Haven state.
// Haven 503 → {"state":"unclaimed"}
// Haven 401 → {"state":"active"}
// Connection error/timeout → HTTP 503 {"error":"haven unavailable"}
// Unexpected status → HTTP 502
func (h *Handler) status(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, h.havenURL+"/api/haven/validate", nil)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "haven unavailable"})
		return
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusServiceUnavailable: // 503 — UNCLAIMED or SETUP
		writeJSON(w, http.StatusOK, map[string]string{"state": "unclaimed"})
	case http.StatusUnauthorized: // 401 — ACTIVE
		writeJSON(w, http.StatusOK, map[string]string{"state": "active"})
	default:
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": fmt.Sprintf("unexpected haven status: %d", resp.StatusCode)})
	}
}

// proxyAuth returns a handler that forwards the request to Haven with the
// caller's Authorization header. Used for /users/me endpoints where Haven
// enforces ownership.
func (h *Handler) proxyAuth(method, havenPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		req, err := http.NewRequestWithContext(r.Context(), method, h.havenURL+havenPath, r.Body)
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
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "haven unavailable"})
			return
		}
		defer resp.Body.Close()

		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
	}
}

// proxyAuthWithParam returns a handler that appends a chi URL param to the
// Haven path and forwards the request with the caller's Authorization header.
func (h *Handler) proxyAuthWithParam(method, havenPathPrefix, paramName string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		paramVal := chi.URLParam(r, paramName)
		if paramVal == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "missing " + paramName})
			return
		}

		req, err := http.NewRequestWithContext(r.Context(), method, h.havenURL+havenPathPrefix+paramVal, r.Body)
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
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "haven unavailable"})
			return
		}
		defer resp.Body.Close()

		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
	}
}

// proxySetup returns a handler that pipes the request body verbatim to Haven and
// forwards Haven's status code and response body verbatim.
func (h *Handler) proxySetup(method, havenPath string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		req, err := http.NewRequestWithContext(r.Context(), method, h.havenURL+havenPath, r.Body)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		req.Header.Set("Content-Type", r.Header.Get("Content-Type"))

		resp, err := h.client.Do(req)
		if err != nil {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "haven unavailable"})
			return
		}
		defer resp.Body.Close()

		w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body) //nolint:errcheck
	}
}

// login forwards credentials to Haven, rewrites the refresh cookie Path, and
// returns {"access_token":"<value>"} to the browser.
func (h *Handler) login(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, h.havenURL+"/api/haven/auth/login", r.Body)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	req.Header.Set("Content-Type", r.Header.Get("Content-Type"))

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "haven unavailable"})
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
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "invalid haven response"})
		return
	}

	accessToken, _ := payload["access_token"].(string)

	// Rewrite Set-Cookie path from Haven's path to Luma's refresh path.
	rewriteCookies(w, resp, "/api/haven/refresh", "/api/luma/auth/refresh")

	writeJSON(w, http.StatusOK, map[string]string{"access_token": accessToken})
}

// refresh forwards the browser's cookie to Haven, rewrites the Set-Cookie path,
// and returns a new access token.
func (h *Handler) refresh(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, h.havenURL+"/api/haven/auth/refresh", nil)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	// Forward the browser's cookie to Haven.
	if cookie := r.Header.Get("Cookie"); cookie != "" {
		req.Header.Set("Cookie", cookie)
	}

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "haven unavailable"})
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
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "invalid haven response"})
		return
	}

	accessToken, _ := payload["access_token"].(string)

	rewriteCookies(w, resp, "/api/haven/refresh", "/api/luma/auth/refresh")

	writeJSON(w, http.StatusOK, map[string]string{"access_token": accessToken})
}

// logout forwards the browser cookie to Haven and proxies its response status
// and any Set-Cookie (which Haven uses to expire the cookie).
func (h *Handler) logout(w http.ResponseWriter, r *http.Request) {
	req, err := http.NewRequestWithContext(r.Context(), http.MethodPost, h.havenURL+"/api/haven/auth/logout", nil)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	if cookie := r.Header.Get("Cookie"); cookie != "" {
		req.Header.Set("Cookie", cookie)
	}

	resp, err := h.client.Do(req)
	if err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "haven unavailable"})
		return
	}
	defer resp.Body.Close()

	// Forward any Set-Cookie headers (expiry cookies from Haven).
	for _, sc := range resp.Header["Set-Cookie"] {
		w.Header().Add("Set-Cookie", sc)
	}

	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body) //nolint:errcheck
}

// rewriteCookies reads Set-Cookie headers from the Haven response via resp.Cookies(),
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
