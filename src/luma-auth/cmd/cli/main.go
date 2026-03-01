// luma-auth-cli — operational and administrative CLI for luma-auth.
// Provides unattended setup, secret generation, health checks, and factory reset.
package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/josephtindall/luma-auth/pkg/config"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) == 0 {
		printUsage()
		return nil
	}

	switch args[0] {
	case "setup":
		return setupUnattended(args[1:])

	case "generate-secrets":
		return generateSecrets()

	case "validate-config":
		return validateConfig(args[1:])

	case "healthcheck":
		return healthcheck(args[1:])

	case "factory-reset":
		return factoryReset(args[1:])

	default:
		printUsage()
		return fmt.Errorf("unknown command: %s", args[0])
	}
}

// setupUnattended reads AUTH_OWNER_* env vars and drives the three-step setup
// API non-interactively. AUTH_UNATTENDED=true must be set explicitly to guard
// against accidental headless runs.
func setupUnattended(args []string) error {
	var envFile, addr string
	for i, a := range args {
		if a == "--env-file" && i+1 < len(args) {
			envFile = args[i+1]
		}
		if a == "--addr" && i+1 < len(args) {
			addr = args[i+1]
		}
	}

	if envFile != "" {
		if err := loadEnvFile(envFile); err != nil {
			return fmt.Errorf("setup: %w", err)
		}
	}

	if os.Getenv("AUTH_UNATTENDED") != "true" {
		return fmt.Errorf("setup: AUTH_UNATTENDED=true must be set to confirm unattended mode")
	}

	ownerEmail := os.Getenv("AUTH_OWNER_EMAIL")
	ownerName := os.Getenv("AUTH_OWNER_NAME")
	ownerPassword := os.Getenv("AUTH_OWNER_PASSWORD")
	instanceName := os.Getenv("AUTH_INSTANCE_NAME")
	setupToken := os.Getenv("AUTH_SETUP_TOKEN")

	var missing []string
	if ownerEmail == "" {
		missing = append(missing, "AUTH_OWNER_EMAIL")
	}
	if ownerName == "" {
		missing = append(missing, "AUTH_OWNER_NAME")
	}
	if ownerPassword == "" {
		missing = append(missing, "AUTH_OWNER_PASSWORD")
	}
	if instanceName == "" {
		missing = append(missing, "AUTH_INSTANCE_NAME")
	}
	if setupToken == "" {
		missing = append(missing, "AUTH_SETUP_TOKEN")
	}
	if len(missing) > 0 {
		return fmt.Errorf("setup: missing required environment variables: %s", strings.Join(missing, ", "))
	}

	locale := getEnvOrDefault("AUTH_INSTANCE_LOCALE", "en-US")
	timezone := getEnvOrDefault("AUTH_INSTANCE_TIMEZONE", "UTC")
	if addr == "" {
		addr = getEnvOrDefault("AUTH_ADDR", "http://127.0.0.1:8080")
	}

	fmt.Println("Auth service unattended setup — starting...")

	// Step 1: verify the setup token — transitions UNCLAIMED → SETUP.
	fmt.Println("  [1/3] Verifying setup token...")
	if err := apiPost(addr+"/api/setup/verify-token",
		map[string]any{"token": setupToken},
		http.StatusNoContent, nil); err != nil {
		return fmt.Errorf("setup: verify-token: %w", err)
	}

	// Step 2: configure the instance name, locale, and timezone.
	fmt.Println("  [2/3] Configuring instance...")
	if err := apiPost(addr+"/api/setup/instance",
		map[string]any{"name": instanceName, "locale": locale, "timezone": timezone},
		http.StatusNoContent, nil); err != nil {
		return fmt.Errorf("setup: configure-instance: %w", err)
	}

	// Step 3: create the owner — transitions instance to ACTIVE.
	fmt.Println("  [3/3] Creating owner account...")
	var ownerResp struct {
		UserID string `json:"user_id"`
	}
	if err := apiPost(addr+"/api/setup/owner",
		map[string]any{
			"display_name": ownerName,
			"email":        ownerEmail,
			"password":     ownerPassword,
			"confirmed":    true,
		},
		http.StatusCreated, &ownerResp); err != nil {
		return fmt.Errorf("setup: create-owner: %w", err)
	}

	fmt.Println()
	fmt.Println("Auth service setup complete.")
	fmt.Printf("  Instance:    %s\n", instanceName)
	fmt.Printf("  Owner email: %s\n", ownerEmail)
	fmt.Printf("  User ID:     %s\n", ownerResp.UserID)
	return nil
}

// factoryReset drops and recreates the auth schema, resetting the instance to
// UNCLAIMED state. The next server start re-applies all migrations automatically.
func factoryReset(args []string) error {
	confirmed := false
	for _, a := range args {
		if a == "--confirm-destroy-all-data" {
			confirmed = true
		}
	}
	if !confirmed {
		return fmt.Errorf("factory-reset: --confirm-destroy-all-data is required\n" +
			"  This permanently deletes all auth data. There is no undo.")
	}

	host := getEnvOrDefault("AUTH_DB_HOST", "localhost")
	port := getEnvOrDefault("AUTH_DB_PORT", "5432")
	user := getEnvOrDefault("AUTH_DB_USER", "auth_app")
	pass := os.Getenv("LUMA_AUTH_DB_PASS")
	name := getEnvOrDefault("AUTH_DB_NAME", "auth")
	sslmode := getEnvOrDefault("AUTH_DB_SSL_MODE", "prefer")

	if pass == "" {
		return fmt.Errorf("factory-reset: LUMA_AUTH_DB_PASS is required")
	}

	dbURL := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=%s",
		user, pass, host, port, name, sslmode)

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		return fmt.Errorf("factory-reset: connect to postgres: %w", err)
	}
	defer conn.Close(ctx)

	tx, err := conn.Begin(ctx)
	if err != nil {
		return fmt.Errorf("factory-reset: begin transaction: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	if _, err := tx.Exec(ctx, "DROP SCHEMA IF EXISTS auth CASCADE"); err != nil {
		return fmt.Errorf("factory-reset: drop schema: %w", err)
	}
	if _, err := tx.Exec(ctx, "CREATE SCHEMA auth"); err != nil {
		return fmt.Errorf("factory-reset: create schema: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("factory-reset: commit: %w", err)
	}

	fmt.Println("Auth service has been reset to factory state.")
	fmt.Println("Run 'docker compose up' to re-run migrations and get a fresh setup token.")
	return nil
}

// apiPost sends a POST request with a JSON body and checks the response status.
// If out is non-nil and the status matches, the response body is decoded into it.
func apiPost(url string, body any, expectStatus int, out any) error {
	payload, err := json.Marshal(body)
	if err != nil {
		return fmt.Errorf("marshal request: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != expectStatus {
		var apiErr struct {
			Code    string `json:"code"`
			Message string `json:"message"`
		}
		if jerr := json.NewDecoder(resp.Body).Decode(&apiErr); jerr == nil && apiErr.Message != "" {
			return fmt.Errorf("HTTP %d %s: %s", resp.StatusCode, apiErr.Code, apiErr.Message)
		}
		return fmt.Errorf("HTTP %d (expected %d)", resp.StatusCode, expectStatus)
	}

	if out != nil {
		if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
			return fmt.Errorf("decode response: %w", err)
		}
	}
	return nil
}

// getEnvOrDefault returns the environment variable or def if unset/empty.
func getEnvOrDefault(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

func validateConfig(args []string) error {
	// Parse --env-file flag.
	var envFile string
	for i, a := range args {
		if a == "--env-file" && i+1 < len(args) {
			envFile = args[i+1]
		}
	}

	if envFile != "" {
		if err := loadEnvFile(envFile); err != nil {
			return fmt.Errorf("validate-config: %w", err)
		}
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("validate-config: %w", err)
	}

	fmt.Println("Configuration OK")
	fmt.Printf("  Port:      %s\n", cfg.Port)
	fmt.Printf("  DB host:   %s:%s/%s\n", cfg.DBHost, cfg.DBPort, cfg.DBName)
	fmt.Printf("  Redis:     %s\n", cfg.RedisAddr)
	fmt.Printf("  JWT key:   %d bytes\n", len(cfg.JWTSigningKey))
	return nil
}

// loadEnvFile reads a .env file and sets each key=value pair into the environment.
// Lines starting with '#' and blank lines are ignored.
func loadEnvFile(path string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("open env file: %w", err)
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		idx := strings.IndexByte(line, '=')
		if idx < 0 {
			continue
		}
		key := line[:idx]
		val := line[idx+1:]
		if err := os.Setenv(key, val); err != nil {
			return fmt.Errorf("setenv %s: %w", key, err)
		}
	}
	return scanner.Err()
}

func healthcheck(args []string) error {
	addr := "http://127.0.0.1:8080"
	for i, a := range args {
		if a == "--addr" && i+1 < len(args) {
			addr = args[i+1]
		}
	}

	resp, err := http.Get(addr + "/api/auth/health") //nolint:gosec
	if err != nil {
		fmt.Fprintf(os.Stderr, "healthcheck: request failed: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Fprintf(os.Stderr, "healthcheck: unexpected status %d\n", resp.StatusCode)
		os.Exit(1)
	}
	fmt.Println("healthy")
	return nil
}

func generateSecrets() error {
	jwtKey, err := randomHex(64) // 512-bit signing key
	if err != nil {
		return fmt.Errorf("generate jwt key: %w", err)
	}
	dbPass, err := randomHex(32) // 256-bit DB password
	if err != nil {
		return fmt.Errorf("generate db password: %w", err)
	}

	fmt.Printf("# Generated by: go run ./cmd/cli generate-secrets\n")
	fmt.Printf("# Copy these into your .env file.\n\n")
	fmt.Printf("LUMA_AUTH_JWT_SIGNING_KEY=%s\n", jwtKey)
	fmt.Printf("LUMA_AUTH_DB_PASS=%s\n", dbPass)
	return nil
}

func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

func printUsage() {
	fmt.Println(`luma-auth-cli — auth service administration

Commands:
  setup [--env-file FILE] [--addr URL]
                                    Unattended install — reads AUTH_OWNER_* env vars.
                                    Requires AUTH_UNATTENDED=true, AUTH_SETUP_TOKEN,
                                    AUTH_OWNER_EMAIL, AUTH_OWNER_NAME,
                                    AUTH_OWNER_PASSWORD, AUTH_INSTANCE_NAME.
  generate-secrets                  Print all required secrets as .env lines
  validate-config [--env-file FILE] Validate configuration before starting
  healthcheck [--addr URL]          Exit 0 if server is healthy (default: http://127.0.0.1:8080)
  factory-reset --confirm-destroy-all-data
                                    Wipe all data and reset to UNCLAIMED state`)
}
