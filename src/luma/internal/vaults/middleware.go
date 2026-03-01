package vaults

import (
	"context"
	"log/slog"
	"net/http"
)

// DisplayNameResolver fetches a user's display name from the auth service. Called only
// when a personal vault needs to be created — not on every request.
type DisplayNameResolver func(ctx context.Context, userID string) (string, error)

// EnsurePersonalVaultMiddleware returns HTTP middleware that lazily creates a
// personal vault for the authenticated user on their first request. It should
// be placed after the the auth service auth middleware so that the identity is available
// in context.
//
// userIDFunc extracts the user ID from the request context.
// displayNameFunc resolves a user's display name via the auth service — only called when
// a vault actually needs to be created.
func EnsurePersonalVaultMiddleware(
	service *Service,
	userIDFunc func(ctx context.Context) string,
	displayNameFunc DisplayNameResolver,
) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			userID := userIDFunc(r.Context())
			if userID == "" {
				next.ServeHTTP(w, r)
				return
			}

			has, err := service.repo.HasPersonalVault(r.Context(), userID)
			if err != nil {
				slog.ErrorContext(r.Context(), "checking personal vault", "user_id", userID, "error", err)
				next.ServeHTTP(w, r)
				return
			}
			if has {
				next.ServeHTTP(w, r)
				return
			}

			// Vault needs creation — resolve display name from the auth service.
			displayName, err := displayNameFunc(r.Context(), userID)
			if err != nil {
				slog.ErrorContext(r.Context(), "resolving display name for personal vault", "user_id", userID, "error", err)
				// Fall back to user ID as the display name.
				displayName = userID
			}

			if err := service.EnsurePersonalVault(r.Context(), userID, displayName); err != nil {
				slog.ErrorContext(r.Context(), "ensuring personal vault", "user_id", userID, "error", err)
			}

			next.ServeHTTP(w, r)
		})
	}
}
