package config

import (
	"fmt"
	"os"
	"strconv"
)

// Config holds all configuration for the Luma server.
type Config struct {
	DBUrl       string
	RedisUrl    string
	HavenUrl    string
	PublicUrl   string
	Port        int
	LogLevel    string
	MaxUploadMB int
	DevMode     bool   // LUMA_DEV_MODE=true — enables verbose logging
	StaticDir   string // LUMA_STATIC_DIR — path to luma-web/build/web/, empty means no static serving
}

// Load reads configuration from environment variables and validates required values.
func Load() (*Config, error) {
	cfg := &Config{
		DBUrl:       os.Getenv("LUMA_DB_URL"),
		RedisUrl:    os.Getenv("LUMA_REDIS_URL"),
		HavenUrl:    os.Getenv("LUMA_HAVEN_URL"),
		PublicUrl:   os.Getenv("LUMA_PUBLIC_URL"),
		LogLevel:    envOr("LUMA_LOG_LEVEL", "info"),
		MaxUploadMB: envIntOr("LUMA_MAX_UPLOAD_MB", 100),
		Port:        envIntOr("LUMA_PORT", 8002),
		DevMode:     os.Getenv("LUMA_DEV_MODE") == "true",
		StaticDir:   os.Getenv("LUMA_STATIC_DIR"),
	}

	if cfg.DBUrl == "" {
		return nil, fmt.Errorf("config: LUMA_DB_URL is required")
	}
	if cfg.RedisUrl == "" {
		return nil, fmt.Errorf("config: LUMA_REDIS_URL is required")
	}
	if cfg.HavenUrl == "" {
		return nil, fmt.Errorf("config: LUMA_HAVEN_URL is required")
	}
	if cfg.PublicUrl == "" {
		return nil, fmt.Errorf("config: LUMA_PUBLIC_URL is required")
	}

	return cfg, nil
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envIntOr(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}
