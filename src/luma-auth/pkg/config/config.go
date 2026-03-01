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
	Port    string // HAVEN_PORT    — default "8080"
	BaseURL string // HAVEN_BASE_URL — required; public-facing URL, e.g. https://haven.example.com

	// Database — assembled into DBURL by Load(); never set directly.
	DBHost    string // HAVEN_DB_HOST    — default "localhost"
	DBPort    string // HAVEN_DB_PORT    — default "5432"
	DBUser    string // HAVEN_DB_USER    — default "haven_app"
	DBPass    string // HAVEN_DB_PASS    — required
	DBName    string // HAVEN_DB_NAME    — default "haven"
	DBSSLMode string // HAVEN_DB_SSL_MODE — default "prefer" (use "disable" for local dev)
	DBURL     string // assembled from the above; ready to pass to pgxpool.New

	// Redis
	RedisAddr     string // HAVEN_REDIS_ADDR     — required
	RedisPassword string // HAVEN_REDIS_PASSWORD — optional

	// JWT — 512-bit key, hex-encoded. Fatal if missing or < 32 bytes decoded.
	JWTSigningKey     []byte // HAVEN_JWT_SIGNING_KEY
	JWTSigningKeyPrev []byte // HAVEN_JWT_SIGNING_KEY_PREV — only during key rotation

	// Setup
	SetupToken string // HAVEN_SETUP_TOKEN — CLI unattended path only
}

// Load reads all configuration from environment variables and validates it.
// Returns a fatal error for any missing or invalid security-relevant value.
func Load() (*Config, error) {
	cfg := &Config{
		Port:          envOrDefault("HAVEN_PORT", "8080"),
		BaseURL:       os.Getenv("HAVEN_BASE_URL"),
		DBHost:        envOrDefault("HAVEN_DB_HOST", "localhost"),
		DBPort:        envOrDefault("HAVEN_DB_PORT", "5432"),
		DBUser:        envOrDefault("HAVEN_DB_USER", "haven_app"),
		DBPass:        os.Getenv("HAVEN_DB_PASS"),
		DBName:        envOrDefault("HAVEN_DB_NAME", "haven"),
		DBSSLMode:     envOrDefault("HAVEN_DB_SSL_MODE", "prefer"),
		RedisAddr:     os.Getenv("HAVEN_REDIS_ADDR"),
		RedisPassword: os.Getenv("HAVEN_REDIS_PASSWORD"),
		SetupToken:    os.Getenv("HAVEN_SETUP_TOKEN"),
	}

	if cfg.BaseURL == "" {
		return nil, fmt.Errorf("HAVEN_BASE_URL is required (e.g. https://haven.example.com)")
	}
	if u, err := url.Parse(cfg.BaseURL); err != nil || u.Scheme == "" || u.Host == "" {
		return nil, fmt.Errorf("HAVEN_BASE_URL must be a valid URL with scheme and host (e.g. https://haven.example.com)")
	}
	if cfg.DBPass == "" {
		return nil, fmt.Errorf("HAVEN_DB_PASS is required")
	}
	if cfg.RedisAddr == "" {
		return nil, fmt.Errorf("HAVEN_REDIS_ADDR is required")
	}

	cfg.DBURL = fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s",
		cfg.DBUser, cfg.DBPass, cfg.DBHost, cfg.DBPort, cfg.DBName, cfg.DBSSLMode)

	key, err := requireHexKey("HAVEN_JWT_SIGNING_KEY", 32)
	if err != nil {
		return nil, err
	}
	cfg.JWTSigningKey = key

	// Previous key is optional — only present during zero-downtime key rotation.
	if prev := os.Getenv("HAVEN_JWT_SIGNING_KEY_PREV"); prev != "" {
		prevKey, err := requireHexKey("HAVEN_JWT_SIGNING_KEY_PREV", 32)
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
