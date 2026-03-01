package auth

import (
	"net/http"
	"strings"
)

// Middleware validates Bearer tokens via the auth service on every protected request.
type Middleware struct {
	client *Client
}

// NewMiddleware creates a new authentication middleware.
func NewMiddleware(client *Client) *Middleware {
	return &Middleware{client: client}
}

// Authenticate returns an http.Handler that validates the Bearer token,
// stores the identity and token in the request context, and calls next.
// If the token is missing or invalid, it writes a 401 response.
func (m *Middleware) Authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := extractBearer(r)
		if token == "" {
			writeUnauthorized(w)
			return
		}

		identity, err := m.client.ValidateToken(r.Context(), token)
		if err != nil {
			writeUnauthorized(w)
			return
		}

		ctx := WithIdentity(r.Context(), identity)
		ctx = withToken(ctx, token)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func extractBearer(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if !strings.HasPrefix(auth, "Bearer ") {
		return ""
	}
	return strings.TrimPrefix(auth, "Bearer ")
}

func writeUnauthorized(w http.ResponseWriter) {
	http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
}
