package bootstrap

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"log/slog"
	"regexp"
	"strings"
	"time"

	"github.com/josephtindall/luma-auth/pkg/crypto"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// bcp47Pattern matches well-formed BCP-47 language tags, e.g. "en", "en-US", "zh-Hans-CN".
var bcp47Pattern = regexp.MustCompile(`^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{1,8})*$`)

// ErrInvalidName is returned when the instance name fails validation.
var ErrInvalidName = fmt.Errorf("instance name must be 2–64 characters")

const (
	setupTokenLifetime = 2 * time.Hour    // UNCLAIMED token validity
	setupWindowTimeout = 30 * time.Minute // SETUP state window after token verified
	maxTokenFailures   = 3
	minPasswordLen     = 8
)

// Service handles all bootstrap business logic.
// The handler delegates to this service — never calls the repository directly.
type Service struct {
	repo StateRepository
}

// NewService constructs the bootstrap service.
func NewService(repo StateRepository) *Service {
	return &Service{repo: repo}
}

// Initialize must be called once at server startup (after migrations).
// It ensures the instance row exists and prints the setup token to stdout
// if the instance is UNCLAIMED and no valid token is stored.
func (s *Service) Initialize(ctx context.Context) error {
	if err := s.repo.EnsureRow(ctx); err != nil {
		return fmt.Errorf("bootstrap: ensure row: %w", err)
	}

	state, err := s.repo.Get(ctx)
	if err != nil {
		return fmt.Errorf("bootstrap: get state: %w", err)
	}

	if state.SetupState == StateActive {
		slog.Info("bootstrap: instance is active — setup complete")
		return nil
	}

	if state.SetupState == StateSetup {
		// Check whether the SETUP window has expired.
		if state.SetupTokenExpiresAt != nil && time.Now().After(*state.SetupTokenExpiresAt) {
			slog.Warn("bootstrap: SETUP window expired — resetting to UNCLAIMED")
			return s.regenerateToken(ctx)
		}
		slog.Info("bootstrap: instance is in SETUP state — awaiting owner creation")
		return nil
	}

	// StateUnclaimed: ensure there is a valid setup token.
	if state.SetupTokenHash != nil && state.SetupTokenExpiresAt != nil &&
		time.Now().Before(*state.SetupTokenExpiresAt) {
		// Valid token already exists — just remind via stdout.
		slog.Info("bootstrap: instance is UNCLAIMED — setup token already issued; check startup logs")
		return nil
	}

	return s.regenerateToken(ctx)
}

// GetState returns the current instance state for the middleware/handler check.
func (s *Service) GetState(ctx context.Context) (*InstanceState, error) {
	return s.repo.Get(ctx)
}

// VerifyToken validates the presented raw setup token (constant-time comparison
// against the stored SHA-256 hash). On success it transitions to SETUP.
// On failure it increments the counter; after maxTokenFailures it resets to
// UNCLAIMED and generates a fresh token, which is printed to stdout.
func (s *Service) VerifyToken(ctx context.Context, rawToken string) error {
	state, err := s.repo.Get(ctx)
	if err != nil {
		return fmt.Errorf("bootstrap: get state: %w", err)
	}
	if state.SetupState != StateUnclaimed {
		return pkgerrors.ErrSetupComplete
	}
	if state.SetupTokenHash == nil {
		return pkgerrors.ErrTokenInvalid
	}
	if state.SetupTokenExpiresAt != nil && time.Now().After(*state.SetupTokenExpiresAt) {
		_ = s.regenerateToken(ctx)
		return pkgerrors.ErrTokenExpired
	}

	presented := hashSetupToken(rawToken)
	expected := []byte(*state.SetupTokenHash)
	if subtle.ConstantTimeCompare([]byte(presented), expected) != 1 {
		count, err := s.repo.IncrementTokenFailures(ctx)
		if err != nil {
			return fmt.Errorf("bootstrap: increment failures: %w", err)
		}
		if count >= maxTokenFailures {
			slog.Warn("bootstrap: max token failures reached — regenerating setup token")
			_ = s.regenerateToken(ctx)
		}
		return pkgerrors.ErrInvalidCredentials
	}

	expiry := time.Now().UTC().Add(setupWindowTimeout)
	if err := s.repo.TransitionToSetup(ctx, expiry); err != nil {
		return fmt.Errorf("bootstrap: transition to setup: %w", err)
	}
	slog.Info("bootstrap: token verified — transitioned to SETUP", "window_expires", expiry)
	return nil
}

// ConfigureInstance updates the instance name, locale, and timezone (Step 2).
func (s *Service) ConfigureInstance(ctx context.Context, name, locale, timezone string) error {
	if err := s.requireState(ctx, StateSetup); err != nil {
		return err
	}
	if err := s.checkSetupTimeout(ctx); err != nil {
		return err
	}
	if len(name) < 2 || len(name) > 64 {
		return ErrInvalidName
	}
	if _, err := time.LoadLocation(timezone); err != nil {
		return fmt.Errorf("bootstrap: invalid timezone %q: must be a valid IANA timezone (e.g. \"America/New_York\")", timezone)
	}
	if !bcp47Pattern.MatchString(locale) {
		return fmt.Errorf("bootstrap: invalid locale %q: must be a valid BCP-47 language tag (e.g. \"en-US\")", locale)
	}
	return s.repo.ConfigureInstance(ctx, name, locale, timezone)
}

// CreateOwner hashes the password and runs the atomic owner-creation
// transaction (Step 3), transitioning the instance to ACTIVE.
// Returns the new user's UUID so the caller can issue tokens.
func (s *Service) CreateOwner(ctx context.Context, params CreateOwnerParams) (userID string, err error) {
	if err := s.requireState(ctx, StateSetup); err != nil {
		return "", err
	}
	if err := s.checkSetupTimeout(ctx); err != nil {
		return "", err
	}
	if len(params.PasswordHash) < minPasswordLen {
		// params.PasswordHash is the raw password at this point — hash it below.
		return "", pkgerrors.ErrPasswordTooShort
	}

	hashed, err := crypto.HashPassword(params.PasswordHash)
	if err != nil {
		return "", fmt.Errorf("bootstrap: hash password: %w", err)
	}
	params.PasswordHash = hashed

	userID, err = s.repo.CreateOwnerAtomic(ctx, params)
	if err != nil {
		return "", fmt.Errorf("bootstrap: create owner: %w", err)
	}
	slog.Info("bootstrap: owner created — instance is now ACTIVE", "user_id", userID)
	return userID, nil
}

// ── internal helpers ──────────────────────────────────────────────────────────

func (s *Service) requireState(ctx context.Context, expected State) error {
	state, err := s.repo.Get(ctx)
	if err != nil {
		return fmt.Errorf("bootstrap: get state: %w", err)
	}
	if state.SetupState != expected {
		if state.SetupState == StateActive {
			return pkgerrors.ErrSetupComplete
		}
		return pkgerrors.ErrSetupRequired
	}
	return nil
}

func (s *Service) checkSetupTimeout(ctx context.Context) error {
	state, err := s.repo.Get(ctx)
	if err != nil {
		return err
	}
	if state.SetupTokenExpiresAt != nil && time.Now().After(*state.SetupTokenExpiresAt) {
		slog.Warn("bootstrap: SETUP window expired — resetting to UNCLAIMED")
		_ = s.regenerateToken(ctx)
		return fmt.Errorf("bootstrap: %w", pkgerrors.ErrTokenExpired)
	}
	return nil
}

func (s *Service) regenerateToken(ctx context.Context) error {
	raw, err := generateSetupCode(8)
	if err != nil {
		return fmt.Errorf("bootstrap: generate token: %w", err)
	}
	hash := hashSetupToken(raw)
	expiry := time.Now().UTC().Add(setupTokenLifetime)

	if err := s.repo.ResetToUnclaimed(ctx, hash, expiry); err != nil {
		return fmt.Errorf("bootstrap: store token: %w", err)
	}

	// Print to stdout — this is intentional. Operators read it from container logs.
	display := raw[:4] + "-" + raw[4:]
	expiryLocal := expiry.Local().Format("3:04 PM")
	header := fmt.Sprintf("  SETUP VERIFY CODE (expires at %s)", expiryLocal)
	boxWidth := len(header) + 2 // +2 for ║ borders
	if boxWidth < 45 {
		boxWidth = 45
	}
	inner := boxWidth - 2
	fmt.Printf("\n")
	fmt.Printf("╔%s╗\n", strings.Repeat("═", inner))
	fmt.Printf("║%-*s║\n", inner, header)
	fmt.Printf("╠%s╣\n", strings.Repeat("═", inner))
	pad := (inner - len(display)) / 2
	fmt.Printf("║%s%-*s║\n", strings.Repeat(" ", pad), inner-pad, display)
	fmt.Printf("╚%s╝\n", strings.Repeat("═", inner))
	fmt.Printf("\n")
	return nil
}

// generateSetupCode returns a random uppercase alphanumeric code of the given
// length. Uses crypto/rand — safe for one-time setup codes.
func generateSetupCode(length int) (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no 0/O/1/I to avoid confusion
	b := make([]byte, length)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	for i := range b {
		b[i] = alphabet[b[i]%byte(len(alphabet))]
	}
	return string(b), nil
}

func hashSetupToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
