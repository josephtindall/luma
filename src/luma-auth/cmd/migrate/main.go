// luma-auth migrate — standalone migration CLI.
// Usage:
//
//	go run ./cmd/migrate up      Apply all pending migrations
//	go run ./cmd/migrate down    Roll back the last applied migration
//	go run ./cmd/migrate status  Show migration status
package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/migrate"
	"github.com/josephtindall/luma-auth/migrations"
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
		fmt.Println("usage: migrate [up|down|status]")
		return nil
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}

	ctx := context.Background()
	db, err := pgxpool.New(ctx, cfg.DBURL)
	if err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer db.Close()

	switch args[0] {
	case "up":
		return migrate.Up(ctx, db, migrations.FS)
	case "down":
		return migrate.Down(ctx, db, migrations.FS)
	case "status":
		return migrate.Status(ctx, db, migrations.FS)
	default:
		return fmt.Errorf("unknown command %q — use up, down, or status", args[0])
	}
}
