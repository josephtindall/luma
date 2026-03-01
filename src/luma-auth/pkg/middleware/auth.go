package middleware

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/token"
)

type claimsKey struct{}

// RequireAuth validates the Bearer token in the Authorization header.
// On success it stores the parsed Claims in the request context.
// On failure it writes a 401 JSON response and halts the handler chain.
func RequireAuth(currentKey, prevKey []byte) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			raw := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
			if raw == "" {
				writeAuthError(w, "missing token")
				return
			}

			claims, err := token.ValidateAccessToken(raw, currentKey, prevKey)
			if err != nil {
				writeAuthError(w, "invalid token")
				return
			}

			ctx := context.WithValue(r.Context(), claimsKey{}, claims)
			next.ServeHTTP(w, r.WithContext(ctx))
		})
	}
}

// ClaimsFromContext retrieves the validated JWT claims from the context.
// Returns nil if the middleware was not applied.
func ClaimsFromContext(ctx context.Context) *token.Claims {
	c, _ := ctx.Value(claimsKey{}).(*token.Claims)
	return c
}

func writeAuthError(w http.ResponseWriter, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	_ = json.NewEncoder(w).Encode(errors.ErrorResponse{
		Code:    "UNAUTHORIZED",
		Message: msg,
	})
}
