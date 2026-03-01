// Package migrate runs numbered SQL migration files against PostgreSQL.
// Migrations are applied in filename order. Each migration runs inside a
// transaction — a partial failure rolls back the whole file.
// Applied migrations are tracked in haven.schema_migrations.
package migrate

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const createTrackingTable = `
CREATE TABLE IF NOT EXISTS haven.schema_migrations (
    filename   TEXT        PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
)`

// Up applies every unapplied *.sql (non-.down.sql) migration file in
// filename order. Each file runs in its own transaction.
func Up(ctx context.Context, db *pgxpool.Pool, migrations fs.FS) error {
	if err := ensureSchema(ctx, db); err != nil {
		return err
	}
	if err := ensureTrackingTable(ctx, db); err != nil {
		return err
	}

	applied, err := appliedSet(ctx, db)
	if err != nil {
		return err
	}

	files, err := upFiles(migrations)
	if err != nil {
		return err
	}

	for _, name := range files {
		if applied[name] {
			slog.Debug("migration already applied", "file", name)
			continue
		}
		if err := applyFile(ctx, db, migrations, name); err != nil {
			return fmt.Errorf("migrate up %s: %w", name, err)
		}
		slog.Info("migration applied", "file", name)
	}
	return nil
}

// Down rolls back the most recently applied migration by running its
// corresponding .down.sql file. Does nothing if no migrations are applied.
func Down(ctx context.Context, db *pgxpool.Pool, migrations fs.FS) error {
	if err := ensureTrackingTable(ctx, db); err != nil {
		return err
	}

	last, err := lastApplied(ctx, db)
	if err != nil {
		return err
	}
	if last == "" {
		slog.Info("no migrations to roll back")
		return nil
	}

	downName := toDownName(last)
	content, err := fs.ReadFile(migrations, downName)
	if err != nil {
		return fmt.Errorf("migrate down: no down file for %s (looked for %s): %w", last, downName, err)
	}

	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("migrate down begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	if _, err := tx.Exec(ctx, string(content)); err != nil {
		return fmt.Errorf("migrate down exec %s: %w", downName, err)
	}
	if _, err := tx.Exec(ctx, `DELETE FROM haven.schema_migrations WHERE filename = $1`, last); err != nil {
		return fmt.Errorf("migrate down unrecord %s: %w", last, err)
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("migrate down commit: %w", err)
	}

	slog.Info("migration rolled back", "file", last)
	return nil
}

// Status prints each migration file and whether it has been applied.
func Status(ctx context.Context, db *pgxpool.Pool, migrations fs.FS) error {
	if err := ensureTrackingTable(ctx, db); err != nil {
		return err
	}

	applied, err := appliedSet(ctx, db)
	if err != nil {
		return err
	}

	files, err := upFiles(migrations)
	if err != nil {
		return err
	}

	for _, f := range files {
		status := "pending"
		if applied[f] {
			status = "applied"
		}
		fmt.Printf("  %-50s %s\n", f, status)
	}
	return nil
}

// ── helpers ───────────────────────────────────────────────────────────────────

func ensureSchema(ctx context.Context, db *pgxpool.Pool) error {
	_, err := db.Exec(ctx, `CREATE SCHEMA IF NOT EXISTS haven`)
	if err != nil {
		return fmt.Errorf("migrate: ensure schema: %w", err)
	}
	return nil
}

func ensureTrackingTable(ctx context.Context, db *pgxpool.Pool) error {
	_, err := db.Exec(ctx, createTrackingTable)
	if err != nil {
		return fmt.Errorf("migrate: ensure tracking table: %w", err)
	}
	return nil
}

func appliedSet(ctx context.Context, db *pgxpool.Pool) (map[string]bool, error) {
	rows, err := db.Query(ctx, `SELECT filename FROM haven.schema_migrations`)
	if err != nil {
		return nil, fmt.Errorf("migrate: list applied: %w", err)
	}
	defer rows.Close()

	applied := make(map[string]bool)
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, fmt.Errorf("migrate: scan applied: %w", err)
		}
		applied[name] = true
	}
	return applied, rows.Err()
}

func lastApplied(ctx context.Context, db *pgxpool.Pool) (string, error) {
	var name string
	err := db.QueryRow(ctx,
		`SELECT filename FROM haven.schema_migrations ORDER BY applied_at DESC, filename DESC LIMIT 1`,
	).Scan(&name)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("migrate: last applied: %w", err)
	}
	return name, nil
}

func upFiles(migrations fs.FS) ([]string, error) {
	entries, err := fs.ReadDir(migrations, ".")
	if err != nil {
		return nil, fmt.Errorf("migrate: read dir: %w", err)
	}

	var files []string
	for _, e := range entries {
		name := e.Name()
		if !e.IsDir() && strings.HasSuffix(name, ".sql") && !strings.HasSuffix(name, ".down.sql") {
			// Skip the Go source file that lives in the same directory.
			files = append(files, name)
		}
	}
	sort.Strings(files)
	return files, nil
}

func applyFile(ctx context.Context, db *pgxpool.Pool, migrations fs.FS, name string) error {
	content, err := fs.ReadFile(migrations, name)
	if err != nil {
		return fmt.Errorf("read: %w", err)
	}

	tx, err := db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	if _, err := tx.Exec(ctx, string(content)); err != nil {
		return fmt.Errorf("exec: %w", err)
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO haven.schema_migrations (filename) VALUES ($1)`, name,
	); err != nil {
		return fmt.Errorf("record: %w", err)
	}

	return tx.Commit(ctx)
}

// toDownName converts "0001_core_tables.sql" → "0001_core_tables.down.sql".
func toDownName(upName string) string {
	return strings.TrimSuffix(upName, ".sql") + ".down.sql"
}
