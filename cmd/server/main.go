package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma/internal/haven"
	"github.com/josephtindall/luma/internal/migrate"
	vaultsPkg "github.com/josephtindall/luma/internal/vaults"
	vaultsPostgres "github.com/josephtindall/luma/internal/vaults/postgres"
	"github.com/josephtindall/luma/pkg/authz"
	"github.com/josephtindall/luma/pkg/config"
)

func main() {
	if err := run(); err != nil {
		slog.Error("fatal", "error", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("loading config: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Database
	pool, err := pgxpool.New(ctx, cfg.DBUrl)
	if err != nil {
		return fmt.Errorf("connecting to database: %w", err)
	}
	defer pool.Close()

	if err := pool.Ping(ctx); err != nil {
		return fmt.Errorf("pinging database: %w", err)
	}
	slog.Info("database connected")

	// Run migrations
	migrator := migrate.NewRunner(pool, "migrations")
	if err := migrator.Run(ctx); err != nil {
		return fmt.Errorf("running migrations: %w", err)
	}

	// Haven client
	havenClient := haven.NewClient(cfg.HavenUrl)
	havenMiddleware := haven.NewMiddleware(havenClient)

	// Authz — uses Haven client as the permission checker.
	// The user ID extractor bridges pkg/authz → internal/haven without a direct import.
	authorizer := authz.NewAuthorizer(havenClient, func(ctx context.Context) string {
		id := haven.IdentityFromContext(ctx)
		if id == nil {
			return ""
		}
		return id.UserID
	})

	// Vaults
	vaultRepo := vaultsPostgres.NewRepository(pool)
	vaultService := vaultsPkg.NewService(vaultRepo)
	vaultHandler := vaultsPkg.NewHandler(vaultService, authorizer)

	// Router
	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	// Health check — unauthenticated
	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	// Personal vault lazy creation — runs after auth, creates on first request.
	ensureVaultMw := vaultsPkg.EnsurePersonalVaultMiddleware(
		vaultService,
		func(ctx context.Context) string {
			id := haven.IdentityFromContext(ctx)
			if id == nil {
				return ""
			}
			return id.UserID
		},
		func(ctx context.Context, userID string) (string, error) {
			user, err := havenClient.GetUser(ctx, userID)
			if err != nil {
				return "", err
			}
			return user.DisplayName, nil
		},
	)

	// Protected routes
	r.Route("/api/luma", func(r chi.Router) {
		r.Use(havenMiddleware.Authenticate)
		r.Use(ensureVaultMw)
		r.Mount("/vaults", vaultHandler.Routes())
	})

	// Server
	addr := fmt.Sprintf(":%d", cfg.Port)
	srv := &http.Server{
		Addr:         addr,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Graceful shutdown
	done := make(chan os.Signal, 1)
	signal.Notify(done, os.Interrupt, syscall.SIGTERM)

	go func() {
		slog.Info("server starting", "addr", addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "error", err)
			os.Exit(1)
		}
	}()

	<-done
	slog.Info("shutting down")

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	return srv.Shutdown(shutdownCtx)
}

