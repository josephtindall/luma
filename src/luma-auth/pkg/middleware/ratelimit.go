package middleware

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	// 30 attempts per IP per 15-minute window before HTTP 429.
	// With MFA, each login cycle consumes 2-4 requests (login + verify/passkey).
	rateLimitWindow  = 15 * time.Minute
	rateLimitMaxHits = 30
)

// IPRateLimit enforces per-IP rate limiting using Redis sliding counters.
// Intended for login and registration endpoints only.
func IPRateLimit(rdb *redis.Client) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := clientIP(r)
			key := fmt.Sprintf("ratelimit:ip:%s", ip)
			ctx := r.Context()

			count, err := increment(ctx, rdb, key, rateLimitWindow)
			if err != nil {
				// Redis unavailable — fail open to avoid blocking legitimate users,
				// but log the error so ops is alerted.
				slog.Error("rate limiter: redis unavailable, failing open", "ip", ip, "err", err)
				next.ServeHTTP(w, r)
				return
			}

			if count > rateLimitMaxHits {
				w.Header().Set("Retry-After", fmt.Sprintf("%d", int(rateLimitWindow.Seconds())))
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusTooManyRequests)
				_ = json.NewEncoder(w).Encode(map[string]string{
					"code":    "RATE_LIMITED",
					"message": "too many attempts; try again later",
				})
				return
			}

			next.ServeHTTP(w, r)
		})
	}
}

// increment atomically increments a Redis counter, setting TTL on first write.
func increment(ctx context.Context, rdb *redis.Client, key string, window time.Duration) (int64, error) {
	pipe := rdb.Pipeline()
	incr := pipe.Incr(ctx, key)
	pipe.Expire(ctx, key, window)
	if _, err := pipe.Exec(ctx); err != nil {
		return 0, fmt.Errorf("ratelimit: redis pipeline: %w", err)
	}
	return incr.Val(), nil
}

// clientIP extracts the real client IP, trusting X-Forwarded-For when behind
// the Caddy reverse proxy (which is the only topology the auth service runs in).
func clientIP(r *http.Request) string {
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		// Take the first (leftmost) address — the original client.
		parts := strings.Split(xff, ",")
		return strings.TrimSpace(parts[0])
	}
	// Strip port from RemoteAddr.
	addr := r.RemoteAddr
	if i := strings.LastIndex(addr, ":"); i != -1 {
		return addr[:i]
	}
	return addr
}
