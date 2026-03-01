// Package integration contains end-to-end tests for every postgres repository.
// Tests require a real PostgreSQL instance.
//
// Run with:
//
//	HAVEN_TEST_DB_URL=postgres://haven:haven@localhost:5432/haven_test go test -v -race ./internal/integration/
//
// If HAVEN_TEST_DB_URL is not set the entire suite is skipped (exit 0).
package integration_test

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	bootstrappg "github.com/josephtindall/luma-auth/internal/bootstrap/postgres"
	"github.com/josephtindall/luma-auth/internal/migrate"
	"github.com/josephtindall/luma-auth/migrations"
)

// testDB is the shared pool used by every test in this package.
var testDB *pgxpool.Pool

func TestMain(m *testing.M) {
	url := os.Getenv("HAVEN_TEST_DB_URL")
	if url == "" {
		log.Println("HAVEN_TEST_DB_URL not set — integration tests skipped")
		os.Exit(0)
	}

	ctx := context.Background()

	var err error
	testDB, err = pgxpool.New(ctx, url)
	if err != nil {
		log.Fatalf("open pool: %v", err)
	}
	defer testDB.Close()

	if err := migrate.Up(ctx, testDB, migrations.FS); err != nil {
		log.Fatalf("migrate up: %v", err)
	}

	// Ensure the singleton instance row exists for bootstrap tests.
	if err := bootstrappg.New(testDB).EnsureRow(ctx); err != nil {
		log.Fatalf("ensure instance row: %v", err)
	}

	os.Exit(m.Run())
}

// ── shared helpers ────────────────────────────────────────────────────────────

// bg returns a fresh background context.
func bg() context.Context { return context.Background() }

// randHex returns n random bytes as a lowercase hex string (length 2n).
func randHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// uniqueEmail returns an email address guaranteed not to collide across tests.
func uniqueEmail() string {
	return fmt.Sprintf("test-%s@haven.invalid", randHex(8))
}

// genUUID generates a UUID v4 via the test database.
func genUUID(t *testing.T) string {
	t.Helper()
	var id string
	if err := testDB.QueryRow(bg(), "SELECT gen_random_uuid()::TEXT").Scan(&id); err != nil {
		t.Fatalf("genUUID: %v", err)
	}
	return id
}

// insertUser inserts a minimal haven.users row and registers a cleanup that
// cascades deletions to devices, refresh_tokens, and audit_log rows.
func insertUser(t *testing.T, email string) string {
	t.Helper()
	var id string
	err := testDB.QueryRow(bg(), `
		INSERT INTO haven.users (email, display_name, password_hash, instance_role_id)
		VALUES ($1, 'Test User', '$argon2id$stub', 'builtin:instance-member')
		RETURNING id::TEXT
	`, email).Scan(&id)
	if err != nil {
		t.Fatalf("insertUser(%q): %v", email, err)
	}
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM haven.users WHERE id = $1::UUID", id) //nolint:errcheck
	})
	return id
}

// insertOwnerUser inserts a user with the instance-owner role.
func insertOwnerUser(t *testing.T, email string) string {
	t.Helper()
	var id string
	err := testDB.QueryRow(bg(), `
		INSERT INTO haven.users (email, display_name, password_hash, instance_role_id)
		VALUES ($1, 'Owner', '$argon2id$stub', 'builtin:instance-owner')
		RETURNING id::TEXT
	`, email).Scan(&id)
	if err != nil {
		t.Fatalf("insertOwnerUser: %v", err)
	}
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM haven.users WHERE id = $1::UUID", id) //nolint:errcheck
	})
	return id
}

// insertDevice inserts a haven.devices row. Cascades from user on cleanup.
func insertDevice(t *testing.T, userID, fingerprint string) string {
	t.Helper()
	var id string
	err := testDB.QueryRow(bg(), `
		INSERT INTO haven.devices (user_id, name, platform, fingerprint)
		VALUES ($1::UUID, 'Test Device', 'web', $2)
		RETURNING id::TEXT
	`, userID, fingerprint).Scan(&id)
	if err != nil {
		t.Fatalf("insertDevice: %v", err)
	}
	return id
}

// insertRefreshToken inserts a haven.refresh_tokens row. Cascades from device.
func insertRefreshToken(t *testing.T, deviceID, tokenHash string, expiresAt time.Time) string {
	t.Helper()
	var id string
	err := testDB.QueryRow(bg(), `
		INSERT INTO haven.refresh_tokens (device_id, token_hash, expires_at)
		VALUES ($1::UUID, $2, $3)
		RETURNING id::TEXT
	`, deviceID, tokenHash, expiresAt).Scan(&id)
	if err != nil {
		t.Fatalf("insertRefreshToken: %v", err)
	}
	return id
}

// insertPendingInvitation inserts a pending invitation and registers cleanup.
// Returns the invitation UUID and the token hash stored in the DB.
func insertPendingInvitation(t *testing.T, inviterID string) (invID, tokenHash string) {
	t.Helper()
	tokenHash = randHex(32) // simulates a SHA-256 hex output
	err := testDB.QueryRow(bg(), `
		INSERT INTO haven.invitations (inviter_id, token_hash, status, expires_at)
		VALUES ($1::UUID, $2, 'pending', NOW() + INTERVAL '48 hours')
		RETURNING id::TEXT
	`, inviterID, tokenHash).Scan(&invID)
	if err != nil {
		t.Fatalf("insertPendingInvitation: %v", err)
	}
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM haven.invitations WHERE id = $1::UUID", invID) //nolint:errcheck
	})
	return invID, tokenHash
}

// resetInstanceToUnclaimed resets the haven.instance row to a clean UNCLAIMED
// state. Call from t.Cleanup in any test that modifies bootstrap state.
func resetInstanceToUnclaimed(t *testing.T) {
	t.Helper()
	_, err := testDB.Exec(bg(), `
		UPDATE haven.instance
		SET setup_state            = 'unclaimed',
		    setup_token_hash       = NULL,
		    setup_token_expires_at = NULL,
		    setup_token_failures   = 0,
		    activated_at           = NULL
	`)
	if err != nil {
		t.Logf("resetInstanceToUnclaimed: %v", err)
	}
}
