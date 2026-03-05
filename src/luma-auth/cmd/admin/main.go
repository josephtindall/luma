// luma-auth admin — administrative escape hatch for self-hosted environments.
//
// Usage:
//
//	go run ./cmd/admin unlock <email>    Unlock a locked account and reset failed login counter
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) < 2 {
		printUsage()
		return nil
	}

	dbURL := os.Getenv("AUTH_DB_URL")
	if dbURL == "" {
		return fmt.Errorf("AUTH_DB_URL environment variable is required")
	}

	ctx := context.Background()
	db, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer db.Close()

	switch args[0] {
	case "unlock":
		return unlockAccount(ctx, db, args[1])
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func unlockAccount(ctx context.Context, db *pgxpool.Pool, email string) error {
	const q = `
		UPDATE auth.users
		SET locked_at = NULL,
		    locked_reason = NULL,
		    failed_login_attempts = 0,
		    updated_at = NOW()
		WHERE email = $1
		RETURNING id, display_name`

	var id, name string
	err := db.QueryRow(ctx, q, email).Scan(&id, &name)
	if err != nil {
		return fmt.Errorf("no user found with email %q (or database error: %v)", email, err)
	}

	fmt.Printf("✓ Unlocked account for %s (%s)\n", name, email)
	fmt.Println("  Failed login counter reset to 0.")
	fmt.Println("  The user can now log in immediately.")
	return nil
}

func printUsage() {
	fmt.Println("luma-auth admin — administrative escape hatch")
	fmt.Println()
	fmt.Println("Usage:")
	fmt.Println("  admin unlock <email>    Unlock a locked account")
	fmt.Println()
	fmt.Println("Environment:")
	fmt.Println("  AUTH_DB_URL  PostgreSQL connection string (required)")
}
