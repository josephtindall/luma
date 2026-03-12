package middleware

import (
	"context"
	"net"
	"net/http"
	"strings"
)

type ipKey struct{}

// WithIPAddress extracts the IP from the request and puts it in the context.
func WithIPAddress(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip := remoteIP(r)
		ctx := context.WithValue(r.Context(), ipKey{}, ip)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// IPFromContext returns the IP address from the context.
func IPFromContext(ctx context.Context) *string {
	if ip, ok := ctx.Value(ipKey{}).(string); ok && ip != "" {
		return &ip
	}
	return nil
}

// remoteIP strips the port from r.RemoteAddr and checks standard proxy headers.
func remoteIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		if parts := strings.Split(xff, ","); len(parts) > 0 {
			return strings.TrimSpace(parts[0])
		}
	}
	if rip := r.Header.Get("X-Real-IP"); rip != "" {
		return strings.TrimSpace(rip)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
