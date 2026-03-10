package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma/internal/auth"
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

	// Auth client
	authClient := auth.NewClient(cfg.AuthURL)
	authMiddleware := auth.NewMiddleware(authClient)

	// Authz — uses auth client as the permission checker.
	// The user ID extractor bridges pkg/authz → internal/auth without a direct import.
	authorizer := authz.NewAuthorizer(authClient, func(ctx context.Context) string {
		id := auth.IdentityFromContext(ctx)
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
			id := auth.IdentityFromContext(ctx)
			if id == nil {
				return ""
			}
			return id.UserID
		},
		func(ctx context.Context, userID string) (string, error) {
			user, err := authClient.GetUser(ctx, userID)
			if err != nil {
				return "", err
			}
			return user.DisplayName, nil
		},
	)

	// Auth proxy — unauthenticated, outside the protected group
	authHTTPClient := &http.Client{Timeout: 10 * time.Second}
	authHandler := auth.NewHandler(authHTTPClient, cfg.AuthURL, func(ctx context.Context) string {
		id := auth.IdentityFromContext(ctx)
		if id == nil {
			return ""
		}
		return id.UserID
	})

	r.Route("/api/luma/setup", func(r chi.Router) { r.Mount("/", authHandler.SetupRoutes()) })
	r.Route("/api/luma/auth", func(r chi.Router) { r.Mount("/", authHandler.AuthRoutes()) })
	r.Get("/api/luma/health", authHandler.Health())

	// Protected routes
	r.Route("/api/luma", func(r chi.Router) {
		r.Use(authMiddleware.Authenticate)
		r.Use(ensureVaultMw)
		r.Mount("/vaults", vaultHandler.Routes())
		r.Mount("/user", authHandler.UserRoutes())
		r.Mount("/admin", authHandler.AdminRoutes())
	})

	// Static file serving — Flutter web SPA (when LUMA_STATIC_DIR is set).
	// Uses path URL strategy: any path without a matching static file is served
	// as index.html so the Flutter router can handle client-side navigation.
	if cfg.StaticDir != "" {
		staticDir := http.Dir(cfg.StaticDir)
		indexFile := filepath.Join(cfg.StaticDir, "index.html")
		fileServer := http.FileServer(staticDir)
		r.Handle("/*", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			f, err := staticDir.Open(r.URL.Path)
			if err != nil {
				http.ServeFile(w, r, indexFile)
				return
			}
			st, err := f.Stat()
			f.Close()
			if err != nil || st.IsDir() {
				http.ServeFile(w, r, indexFile)
				return
			}
			fileServer.ServeHTTP(w, r)
		}))
	}

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

