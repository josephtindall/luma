// luma-auth server — dependency wiring and startup.
// This file contains zero business logic. All logic lives in internal/.
package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"syscall"
	"time"
	_ "time/tzdata" // embed IANA timezone database for portability

	"github.com/go-chi/chi/v5"
	chimiddleware "github.com/go-chi/chi/v5/middleware"
	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/josephtindall/luma-auth/internal/audit"
	auditpg "github.com/josephtindall/luma-auth/internal/audit/postgres"
	"github.com/josephtindall/luma-auth/internal/authz"
	authzpg "github.com/josephtindall/luma-auth/internal/authz/postgres"
	"github.com/josephtindall/luma-auth/internal/bootstrap"
	bootstrappg "github.com/josephtindall/luma-auth/internal/bootstrap/postgres"
	"github.com/josephtindall/luma-auth/internal/device"
	devicepg "github.com/josephtindall/luma-auth/internal/device/postgres"
	"github.com/josephtindall/luma-auth/internal/invitation"
	invitationpg "github.com/josephtindall/luma-auth/internal/invitation/postgres"
	mfapkg "github.com/josephtindall/luma-auth/internal/mfa"
	mfapg "github.com/josephtindall/luma-auth/internal/mfa/postgres"
	"github.com/josephtindall/luma-auth/internal/migrate"
	"github.com/josephtindall/luma-auth/internal/preferences"
	prefpg "github.com/josephtindall/luma-auth/internal/preferences/postgres"
	"github.com/josephtindall/luma-auth/internal/session"
	sessionpg "github.com/josephtindall/luma-auth/internal/session/postgres"
	"github.com/josephtindall/luma-auth/internal/user"
	userpg "github.com/josephtindall/luma-auth/internal/user/postgres"
	"github.com/josephtindall/luma-auth/migrations"
	"github.com/josephtindall/luma-auth/pkg/config"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	pkgmiddleware "github.com/josephtindall/luma-auth/pkg/middleware"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server failed", "err", err)
		os.Exit(1)
	}
}

func run() error {
	// ── 1. Configuration ──────────────────────────────────────────────────────
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("config: %w", err)
	}

	// ── 2. PostgreSQL connection pool ─────────────────────────────────────────
	db, err := pgxpool.New(context.Background(), cfg.DBURL)
	if err != nil {
		return fmt.Errorf("postgres: connect: %w", err)
	}
	defer db.Close()

	if err := db.Ping(context.Background()); err != nil {
		return fmt.Errorf("postgres: ping: %w", err)
	}
	slog.Info("postgres connected")

	// ── 3. Redis client ───────────────────────────────────────────────────────
	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
	})
	defer rdb.Close()

	if err := rdb.Ping(context.Background()).Err(); err != nil {
		return fmt.Errorf("redis: ping: %w", err)
	}
	slog.Info("redis connected")

	// ── 4. Migrations ─────────────────────────────────────────────────────────
	if err := migrate.Up(context.Background(), db, migrations.FS); err != nil {
		return fmt.Errorf("migrations: %w", err)
	}
	slog.Info("migrations up to date")

	// ── 5. Repositories ───────────────────────────────────────────────────────
	userRepo := userpg.New(db)
	deviceRepo := devicepg.New(db)
	sessionRepo := sessionpg.New(db)
	auditRepo := auditpg.New(db)
	prefRepo := prefpg.New(db)
	invitationRepo := invitationpg.New(db)
	bootstrapRepo := bootstrappg.New(db)
	authzRepo := authzpg.New(db)
	mfaRepo := mfapg.New(db)

	// ── 5b. WebAuthn instance ─────────────────────────────────────────────────────
	rpOrigin := cfg.RPOrigin
	if rpOrigin == "" {
		rpOrigin = cfg.BaseURL
	}
	rpURL, err := url.Parse(rpOrigin)
	if err != nil {
		return fmt.Errorf("webauthn: parse rp origin: %w", err)
	}

	wa, err := webauthn.New(&webauthn.Config{
		RPDisplayName: cfg.RPDisplayName,
		RPID:          rpURL.Hostname(),
		RPOrigins:     []string{rpOrigin},
	})
	if err != nil {
		return fmt.Errorf("webauthn: init: %w", err)
	}
	waStore := mfapkg.NewWebAuthnSessionStore(rdb)

	// ── 6. Services ───────────────────────────────────────────────────────────────
	auditSvc := audit.NewAsyncService(auditRepo)
	defer auditSvc.Stop()

	userSvc := user.NewService(userRepo, auditSvc)
	deviceSvc := device.NewService(deviceRepo, auditSvc)
	prefSvc := preferences.NewService(prefRepo)
	invitationSvc := invitation.NewService(invitationRepo)
	bootstrapSvc := bootstrap.NewService(bootstrapRepo)
	mfaSvc := mfapkg.NewService(mfaRepo, userRepo, auditSvc, wa, waStore)

	sessionSvc := session.NewService(
		userRepo,
		deviceRepo,
		sessionRepo,
		auditSvc,
		invitationRepo,
		mfaSvc,
		mfaSvc, // also satisfies MFAMethodChecker
		cfg.JWTSigningKey,
	)

	authzAuthorizer := authz.NewDefaultAuthorizer(authzRepo, rdb)

	// ── 7. Bootstrap initialisation ───────────────────────────────────────────
	// Ensures the instance row exists. Prints the setup token to stdout when
	// the instance is UNCLAIMED and no valid token is stored.
	if err := bootstrapSvc.Initialize(context.Background()); err != nil {
		return fmt.Errorf("bootstrap: init: %w", err)
	}

	// ── 8. HTTP handlers ──────────────────────────────────────────────────────
	bootstrapGate := bootstrap.NewBootstrapGate(bootstrapRepo)
	bootstrapHandler := bootstrap.NewHandler(bootstrapSvc, sessionSvc)
	sessionHandler := session.NewHandler(sessionSvc, true /* secureCookie */)
	userHandler := user.NewHandler(userSvc, sessionSvc)
	deviceHandler := device.NewHandler(deviceSvc, sessionSvc)
	prefHandler := preferences.NewHandler(prefSvc)
	invHandler := invitation.NewHandler(invitationSvc, cfg.BaseURL)
	authzHandler := authz.NewHandler(authzAuthorizer, auditSvc)
	mfaHandler := mfapkg.NewHandler(mfaSvc, sessionSvc, sessionSvc, sessionSvc, true /* secureCookie */)

	// ── 9. Router ─────────────────────────────────────────────────────────────
	r := chi.NewRouter()

	r.Use(chimiddleware.Recoverer)
	r.Use(pkgmiddleware.RequestID)
	r.Use(pkgmiddleware.Logger)
	r.Use(bootstrapGate.Middleware) // enforced on every request

	// ── Health (always reachable, all bootstrap states) ───────────────────────
	r.Get("/api/auth/health", func(w http.ResponseWriter, r *http.Request) {
		state, err := bootstrapRepo.Get(r.Context())
		if err != nil {
			httputil.WriteJSON(w, http.StatusServiceUnavailable, map[string]string{
				"status": "degraded",
				"error":  "database unreachable",
			})
			return
		}
		httputil.WriteJSON(w, http.StatusOK, map[string]string{
			"status":        "ok",
			"state":         string(state.SetupState),
			"instance_name": state.Name,
		})
	})

	// ── Setup wizard (unauthenticated) ────────────────────────────────────────
	r.Post("/api/setup/verify-token", bootstrapHandler.VerifyToken)
	r.Post("/api/setup/instance", bootstrapHandler.ConfigureInstance)
	r.Post("/api/setup/owner", bootstrapHandler.CreateOwner)

	// ── Auth (rate-limited on sensitive paths) ────────────────────────────────
	r.Group(func(r chi.Router) {
		r.Use(pkgmiddleware.IPRateLimit(rdb))
		r.Post("/api/auth/identify", sessionHandler.Identify)
		r.Post("/api/auth/login", sessionHandler.Login)
		r.Post("/api/auth/refresh", sessionHandler.Refresh)
		r.Post("/api/auth/register", sessionHandler.Register)
		r.Post("/api/auth/mfa/verify", mfaHandler.VerifyMFA)
		r.Post("/api/auth/passkeys/login/begin", mfaHandler.BeginLogin)
		r.Post("/api/auth/passkeys/login/finish", mfaHandler.FinishLogin)
		r.Post("/api/auth/passkeys/passwordless/begin", mfaHandler.BeginPasskeyLogin)
		r.Post("/api/auth/passkeys/passwordless/finish", mfaHandler.FinishPasskeyLogin)
	})

	// ── Invitation join (unauthenticated — accessed before account creation) ──
	r.Get("/api/auth/join", invHandler.Join)

	// ── Protected routes (Bearer token required) ──────────────────────────────
	authMiddleware := pkgmiddleware.RequireAuth(cfg.JWTSigningKey, cfg.JWTSigningKeyPrev)

	r.Group(func(r chi.Router) {
		r.Use(authMiddleware)

		r.Get("/api/auth/validate", sessionHandler.Validate)

		r.Post("/api/auth/logout", sessionHandler.Logout)
		r.Post("/api/auth/logout-all", sessionHandler.LogoutAll)

		r.Get("/api/auth/users/{id}", userHandler.GetUser)
		r.Put("/api/auth/users/me/profile", userHandler.UpdateProfile)
		r.Post("/api/auth/users/me/password", userHandler.ChangePassword)
		r.Get("/api/auth/users/me/preferences", prefHandler.Get)
		r.Patch("/api/auth/users/me/preferences", prefHandler.Update)

		r.Get("/api/auth/devices", deviceHandler.List)
		r.Delete("/api/auth/devices/{id}", deviceHandler.Revoke)

		r.Get("/api/auth/mfa/totp", mfaHandler.ListTOTP)
		r.Post("/api/auth/mfa/totp/setup", mfaHandler.SetupTOTP)
		r.Post("/api/auth/mfa/totp/confirm", mfaHandler.ConfirmTOTP)
		r.Delete("/api/auth/mfa/totp/{id}", mfaHandler.RemoveTOTP)

		r.Post("/api/auth/users/me/mfa/recovery-codes", mfaHandler.GenerateRecoveryCodes)
		r.Get("/api/auth/users/me/mfa/recovery-codes/count", mfaHandler.GetRecoveryCodesCount)

		r.Post("/api/auth/passkeys/register/begin", mfaHandler.BeginRegistration)
		r.Post("/api/auth/passkeys/register/finish", mfaHandler.FinishRegistration)
		r.Get("/api/auth/passkeys", mfaHandler.ListPasskeys)
		r.Delete("/api/auth/passkeys/{id}", mfaHandler.RevokePasskey)

		r.Get("/api/auth/audit/me", auditHandler(auditRepo, false))
		r.Get("/api/auth/audit", auditHandler(auditRepo, true))

		r.Post("/api/auth/authz/check", authzHandler.Check)

		r.Post("/api/auth/invitations", invHandler.Create)
		r.Get("/api/auth/invitations", invHandler.List)
		r.Delete("/api/auth/invitations/{id}", invHandler.Revoke)

		r.Get("/api/auth/admin/users", userHandler.ListUsers)
		r.Post("/api/auth/admin/users/{id}/lock", userHandler.LockUser)
		r.Delete("/api/auth/admin/users/{id}/lock", userHandler.UnlockUser)
		r.Delete("/api/auth/admin/users/{id}/sessions", sessionHandler.RevokeUserSessions)
	})

	// ── 10. Start server + graceful shutdown ──────────────────────────────────
	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      r,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		slog.Info("server listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	<-quit
	slog.Info("shutdown signal received")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		return fmt.Errorf("graceful shutdown: %w", err)
	}
	slog.Info("server stopped cleanly")
	return nil
}

// auditHandler is an inline handler for the audit log endpoints until audit
// grows its own Handler type.
func auditHandler(repo audit.Repository, all bool) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims := pkgmiddleware.ClaimsFromContext(r.Context())
		if claims == nil {
			httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
			return
		}
		if all && claims.Role != "builtin:instance-owner" {
			httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
			return
		}
		var (
			rows []*audit.Row
			err  error
		)
		if all {
			rows, err = repo.ListAll(r.Context(), 100, 0)
		} else {
			rows, err = repo.ListForUser(r.Context(), claims.Subject, 100, 0)
		}
		if err != nil {
			httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to load audit log")
			return
		}
		httputil.WriteJSON(w, http.StatusOK, rows)
	}
}
