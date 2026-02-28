package auth

import (
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
	client   *http.Client
	havenURL string
}

// NewHandler creates an auth proxy handler. httpClient must not be nil.
func NewHandler(httpClient *http.Client, havenURL string) *Handler {
	return &Handler{
		client:   httpClient,
		havenURL: strings.TrimRight(havenURL, "/"),
	}
}

// SetupRoutes returns a router for /api/luma/setup/* endpoints.
func (h *Handler) SetupRoutes() chi.Router {
	r := chi.NewRouter()
	r.Get("/status", h.status)
	r.Post("/verify-token", h.proxySetup("POST", "/api/setup/verify-token"))
	r.Post("/configure", h.proxySetup("POST", "/api/setup/configure"))
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
