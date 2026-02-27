package migrate

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sort"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Runner applies SQL migration files idempotently.
type Runner struct {
	pool *pgxpool.Pool
	dir  string
}

// NewRunner creates a migration runner that reads *.sql files from dir.
func NewRunner(pool *pgxpool.Pool, dir string) *Runner {
	return &Runner{pool: pool, dir: dir}
}

// Run applies all unapplied migrations in lexicographic order.
func (r *Runner) Run(ctx context.Context) error {
	if err := r.ensureTable(ctx); err != nil {
		return fmt.Errorf("ensuring schema_migrations table: %w", err)
	}

	files, err := r.pendingMigrations(ctx)
	if err != nil {
		return fmt.Errorf("determining pending migrations: %w", err)
	}

	for _, f := range files {
		if err := r.apply(ctx, f); err != nil {
			return fmt.Errorf("applying migration %s: %w", f, err)
		}
	}

	if len(files) == 0 {
		slog.Info("migrations: all up to date")
	} else {
		slog.Info("migrations: applied", "count", len(files))
	}
	return nil
}

// ensureTable creates the schema_migrations tracking table if it doesn't exist.
func (r *Runner) ensureTable(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, `
		CREATE SCHEMA IF NOT EXISTS luma;
		CREATE TABLE IF NOT EXISTS luma.schema_migrations (
			version    TEXT        PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		);
	`)
	return err
}

// pendingMigrations returns migration filenames not yet recorded in schema_migrations.
func (r *Runner) pendingMigrations(ctx context.Context) ([]string, error) {
	entries, err := os.ReadDir(r.dir)
	if err != nil {
		return nil, fmt.Errorf("reading migrations dir: %w", err)
	}

	var allFiles []string
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".sql" {
			continue
		}
		allFiles = append(allFiles, e.Name())
	}
	sort.Strings(allFiles)

	applied := make(map[string]bool)
	rows, err := r.pool.Query(ctx, "SELECT version FROM luma.schema_migrations")
	if err != nil {
		return nil, fmt.Errorf("querying applied migrations: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var v string
		if err := rows.Scan(&v); err != nil {
			return nil, fmt.Errorf("scanning migration version: %w", err)
		}
		applied[v] = true
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterating applied migrations: %w", err)
	}

	var pending []string
	for _, f := range allFiles {
		if !applied[f] {
			pending = append(pending, f)
		}
	}
	return pending, nil
}

// apply runs a single migration file inside a transaction and records it.
func (r *Runner) apply(ctx context.Context, filename string) error {
	sql, err := os.ReadFile(filepath.Join(r.dir, filename))
	if err != nil {
		return fmt.Errorf("reading file: %w", err)
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("beginning transaction: %w", err)
	}
	defer tx.Rollback(ctx)

	if _, err := tx.Exec(ctx, string(sql)); err != nil {
		return fmt.Errorf("executing SQL: %w", err)
	}

	if _, err := tx.Exec(ctx, "INSERT INTO luma.schema_migrations (version) VALUES ($1)", filename); err != nil {
		return fmt.Errorf("recording migration: %w", err)
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("committing transaction: %w", err)
	}

	slog.Info("migrations: applied", "version", filename)
	return nil
}
