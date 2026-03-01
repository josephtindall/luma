package config

import (
	"encoding/hex"
	"fmt"
	"net/url"
	"os"
)

// Config holds all runtime configuration. Loaded once at startup — never
// re-read at runtime. Missing or invalid security values are fatal.
type Config struct {
	// Server
	Port    string // AUTH_PORT    — default "8080"
	BaseURL string // AUTH_BASE_URL — required; public-facing URL, e.g. https://auth.example.com

	// Database — assembled into DBURL by Load(); never set directly.
	DBHost    string // AUTH_DB_HOST    — default "localhost"
	DBPort    string // AUTH_DB_PORT    — default "5432"
	DBUser    string // AUTH_DB_USER    — default "auth_app"
	DBPass    string // LUMA_AUTH_DB_PASS    — required
	DBName    string // AUTH_DB_NAME    — default "auth"
	DBSSLMode string // AUTH_DB_SSL_MODE — default "prefer" (use "disable" for local dev)
	DBURL     string // assembled from the above; ready to pass to pgxpool.New

	// Redis
	RedisAddr     string // AUTH_REDIS_ADDR     — required
	RedisPassword string // AUTH_REDIS_PASSWORD — optional

	// JWT — 512-bit key, hex-encoded. Fatal if missing or < 32 bytes decoded.
	JWTSigningKey     []byte // LUMA_AUTH_JWT_SIGNING_KEY
	JWTSigningKeyPrev []byte // LUMA_AUTH_JWT_SIGNING_KEY_PREV — only during key rotation

	// Setup
	SetupToken string // AUTH_SETUP_TOKEN — CLI unattended path only
}

// Load reads all configuration from environment variables and validates it.
// Returns a fatal error for any missing or invalid security-relevant value.
func Load() (*Config, error) {
	cfg := &Config{
		Port:          envOrDefault("AUTH_PORT", "8080"),
		BaseURL:       os.Getenv("AUTH_BASE_URL"),
		DBHost:        envOrDefault("AUTH_DB_HOST", "localhost"),
		DBPort:        envOrDefault("AUTH_DB_PORT", "5432"),
		DBUser:        envOrDefault("AUTH_DB_USER", "auth_app"),
		DBPass:        os.Getenv("LUMA_AUTH_DB_PASS"),
		DBName:        envOrDefault("AUTH_DB_NAME", "auth"),
		DBSSLMode:     envOrDefault("AUTH_DB_SSL_MODE", "prefer"),
		RedisAddr:     os.Getenv("AUTH_REDIS_ADDR"),
		RedisPassword: os.Getenv("AUTH_REDIS_PASSWORD"),
		SetupToken:    os.Getenv("AUTH_SETUP_TOKEN"),
	}

	if cfg.BaseURL == "" {
		return nil, fmt.Errorf("AUTH_BASE_URL is required (e.g. https://auth.example.com)")
	}
	if u, err := url.Parse(cfg.BaseURL); err != nil || u.Scheme == "" || u.Host == "" {
		return nil, fmt.Errorf("AUTH_BASE_URL must be a valid URL with scheme and host (e.g. https://auth.example.com)")
	}
	if cfg.DBPass == "" {
		return nil, fmt.Errorf("LUMA_AUTH_DB_PASS is required")
	}
	if cfg.RedisAddr == "" {
		return nil, fmt.Errorf("AUTH_REDIS_ADDR is required")
	}

	cfg.DBURL = fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s",
		cfg.DBUser, cfg.DBPass, cfg.DBHost, cfg.DBPort, cfg.DBName, cfg.DBSSLMode)

	key, err := requireHexKey("LUMA_AUTH_JWT_SIGNING_KEY", 32)
	if err != nil {
		return nil, err
	}
	cfg.JWTSigningKey = key

	// Previous key is optional — only present during zero-downtime key rotation.
	if prev := os.Getenv("LUMA_AUTH_JWT_SIGNING_KEY_PREV"); prev != "" {
		prevKey, err := requireHexKey("LUMA_AUTH_JWT_SIGNING_KEY_PREV", 32)
		if err != nil {
			return nil, err
		}
		cfg.JWTSigningKeyPrev = prevKey
	}

	return cfg, nil
}

// requireHexKey decodes a hex-encoded environment variable and asserts it is
// at least minBytes bytes long. Returns a fatal error if absent or too short.
func requireHexKey(name string, minBytes int) ([]byte, error) {
	raw := os.Getenv(name)
	if raw == "" {
		return nil, fmt.Errorf("%s is required", name)
	}
	decoded, err := hex.DecodeString(raw)
	if err != nil {
		return nil, fmt.Errorf("%s is not valid hex: %w", name, err)
	}
	if len(decoded) < minBytes {
		return nil, fmt.Errorf("%s must be at least %d bytes (%d hex chars); got %d bytes",
			name, minBytes, minBytes*2, len(decoded))
	}
	return decoded, nil
}

func envOrDefault(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}
