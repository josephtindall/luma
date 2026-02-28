package haven

import "context"

type contextKey int

const (
	identityKey contextKey = iota
	tokenKey
)

// WithIdentity stores the authenticated identity in the context.
func WithIdentity(ctx context.Context, id *Identity) context.Context {
	return context.WithValue(ctx, identityKey, id)
}

// IdentityFromContext retrieves the authenticated identity from the context.
// Returns nil if no identity is present.
func IdentityFromContext(ctx context.Context) *Identity {
	id, _ := ctx.Value(identityKey).(*Identity)
	return id
}

// withToken stores the raw bearer token in the context for forwarding to Haven.
func withToken(ctx context.Context, token string) context.Context {
	return context.WithValue(ctx, tokenKey, token)
}

// tokenFromContext retrieves the raw bearer token from the context.
func tokenFromContext(ctx context.Context) string {
	t, _ := ctx.Value(tokenKey).(string)
	return t
}
