package mfa

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base32"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net/url"
	"time"

	"github.com/pquerna/otp"
	"github.com/pquerna/otp/totp"

	"github.com/josephtindall/luma-auth/internal/audit"
	"github.com/josephtindall/luma-auth/internal/user"
	"github.com/josephtindall/luma-auth/pkg/crypto"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

const (
	totpIssuer         = "Luma"
	totpSecretSize     = 20 // bytes
	challengeLifetime  = 5 * time.Minute
	challengeTokenSize = 32 // bytes
)

// TokenIssuer issues token pairs after successful MFA/passkey verification.
// Satisfied by session.Service.
type TokenIssuer interface {
	IssueForDevice(ctx context.Context, userID, deviceID, ipAddress, userAgent string) (*TokenPairResult, error)
}

// TokenPairResult mirrors session.TokenPair without importing the session package.
type TokenPairResult struct {
	AccessToken  string
	RefreshToken string
	ExpiresAt    time.Time
}

// Service contains business logic for MFA (TOTP + passkeys).
type Service struct {
	repo  Repository
	users user.Repository
	audit audit.Service
}

// NewService constructs the MFA service.
func NewService(repo Repository, users user.Repository, auditSvc audit.Service) *Service {
	return &Service{repo: repo, users: users, audit: auditSvc}
}

// ── TOTP Setup ──────────────────────────────────────────────────────────────

// SetupTOTP generates a new TOTP secret for the user. The secret is not yet
// verified — the user must call ConfirmTOTP with a valid code and the returned ID.
// Any existing unverified secrets are cleaned up first.
func (s *Service) SetupTOTP(ctx context.Context, userID, name string) (*TOTPSetupResult, error) {
	if name == "" {
		name = "Authenticator"
	}

	// Clean up any stale unverified secrets from previous incomplete enrollments.
	if err := s.repo.DeleteUnverifiedTOTPSecrets(ctx, userID); err != nil {
		return nil, fmt.Errorf("mfa.Service.SetupTOTP cleanup: %w", err)
	}

	// Look up the user to get the email for the otpauth URI.
	u, err := s.users.GetByID(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("mfa.Service.SetupTOTP get user: %w", err)
	}

	// Generate a random secret.
	secret := make([]byte, totpSecretSize)
	if _, err := rand.Read(secret); err != nil {
		return nil, fmt.Errorf("mfa.Service.SetupTOTP rand: %w", err)
	}

	id, err := s.repo.CreateTOTPSecret(ctx, userID, name, secret)
	if err != nil {
		return nil, fmt.Errorf("mfa.Service.SetupTOTP create: %w", err)
	}

	b32Secret := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(secret)

	otpauthURI := fmt.Sprintf("otpauth://totp/%s:%s?secret=%s&issuer=%s&algorithm=SHA1&digits=6&period=30",
		url.PathEscape(totpIssuer), url.PathEscape(u.Email), b32Secret, url.QueryEscape(totpIssuer))

	return &TOTPSetupResult{
		ID:         id,
		Secret:     b32Secret,
		OTPAuthURI: otpauthURI,
	}, nil
}

// ConfirmTOTP verifies the user's TOTP code against a pending (unverified) secret,
// marks the secret as verified, and sets mfa_enabled=true.
func (s *Service) ConfirmTOTP(ctx context.Context, userID, secretID, code string) error {
	secret, err := s.repo.GetTOTPSecretByID(ctx, secretID)
	if err != nil {
		return fmt.Errorf("mfa.Service.ConfirmTOTP get: %w", err)
	}
	if secret == nil || secret.UserID != userID {
		return pkgerrors.ErrTOTPNotSetup
	}
	if secret.Verified {
		return pkgerrors.ErrTOTPAlreadySetup
	}

	b32Secret := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(secret.Secret)
	valid, err := totp.ValidateCustom(code, b32Secret, time.Now().UTC(), totp.ValidateOpts{
		Period:    30,
		Skew:     1,
		Digits:   otp.DigitsSix,
		Algorithm: otp.AlgorithmSHA1,
	})
	if err != nil || !valid {
		return pkgerrors.ErrMFACodeInvalid
	}

	if err := s.repo.VerifyTOTPSecret(ctx, secretID); err != nil {
		return fmt.Errorf("mfa.Service.ConfirmTOTP verify: %w", err)
	}
	if err := s.users.SetMFAEnabled(ctx, userID, true); err != nil {
		return fmt.Errorf("mfa.Service.ConfirmTOTP enable mfa: %w", err)
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID: userID,
		Event:  audit.EventTOTPEnrolled,
		Metadata: map[string]any{
			"totp_name": secret.Name,
		},
	})
	return nil
}

// ListTOTPSecrets returns all verified TOTP secrets for a user (for the settings UI).
func (s *Service) ListTOTPSecrets(ctx context.Context, userID string) ([]*TOTPSecret, error) {
	secrets, err := s.repo.ListVerifiedTOTPSecrets(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("mfa.Service.ListTOTPSecrets: %w", err)
	}
	return secrets, nil
}

// RemoveTOTP removes a specific TOTP secret after verifying the user's password.
// Clears mfa_enabled if no other MFA methods remain.
func (s *Service) RemoveTOTP(ctx context.Context, userID, secretID, password string) error {
	u, err := s.users.GetByID(ctx, userID)
	if err != nil {
		return fmt.Errorf("mfa.Service.RemoveTOTP get user: %w", err)
	}

	ok, err := crypto.VerifyPassword(password, u.PasswordHash)
	if err != nil || !ok {
		return pkgerrors.ErrInvalidCredentials
	}

	existing, err := s.repo.GetTOTPSecretByID(ctx, secretID)
	if err != nil {
		return fmt.Errorf("mfa.Service.RemoveTOTP get secret: %w", err)
	}
	if existing == nil || existing.UserID != userID {
		return pkgerrors.ErrTOTPNotSetup
	}

	if err := s.repo.DeleteTOTPSecret(ctx, secretID); err != nil {
		return fmt.Errorf("mfa.Service.RemoveTOTP delete: %w", err)
	}

	// Check if any MFA methods remain before clearing mfa_enabled.
	totpCount, err := s.repo.CountVerifiedTOTPSecrets(ctx, userID)
	if err != nil {
		return fmt.Errorf("mfa.Service.RemoveTOTP count totp: %w", err)
	}
	passkeyCount, err := s.repo.CountActivePasskeys(ctx, userID)
	if err != nil {
		return fmt.Errorf("mfa.Service.RemoveTOTP count passkeys: %w", err)
	}
	if totpCount == 0 && passkeyCount == 0 {
		if err := s.users.SetMFAEnabled(ctx, userID, false); err != nil {
			return fmt.Errorf("mfa.Service.RemoveTOTP disable mfa: %w", err)
		}
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID: userID,
		Event:  audit.EventTOTPRemoved,
		Metadata: map[string]any{
			"totp_name": existing.Name,
		},
	})
	return nil
}

// ── MFA Challenges ──────────────────────────────────────────────────────────

// CreateChallenge creates a short-lived MFA challenge for a user who passed
// password verification but has mfa_enabled=true. Returns the raw token.
func (s *Service) CreateChallenge(ctx context.Context, userID, deviceID string) (*ChallengeResult, error) {
	raw, hash, err := generateChallengeToken()
	if err != nil {
		return nil, fmt.Errorf("mfa.Service.CreateChallenge generate: %w", err)
	}

	expiresAt := time.Now().UTC().Add(challengeLifetime)
	if err := s.repo.CreateChallenge(ctx, userID, deviceID, hash, expiresAt); err != nil {
		return nil, fmt.Errorf("mfa.Service.CreateChallenge store: %w", err)
	}

	// Determine available methods.
	methods := []string{}
	totpCount, _ := s.repo.CountVerifiedTOTPSecrets(ctx, userID)
	if totpCount > 0 {
		methods = append(methods, "totp")
	}
	passkeyCount, _ := s.repo.CountActivePasskeys(ctx, userID)
	if passkeyCount > 0 {
		methods = append(methods, "passkey")
	}

	return &ChallengeResult{
		MFAToken: raw,
		Methods:  methods,
	}, nil
}

// VerifyChallenge validates an MFA token + TOTP code, consumes the challenge,
// and returns the user/device IDs for token issuance.
func (s *Service) VerifyChallenge(ctx context.Context, mfaToken, code, ipAddress string) (userID, deviceID string, err error) {
	hash := hashChallengeToken(mfaToken)

	challenge, err := s.repo.GetChallengeByHash(ctx, hash)
	if err != nil {
		return "", "", fmt.Errorf("mfa.Service.VerifyChallenge lookup: %w", err)
	}
	if challenge == nil || !challenge.IsValid() {
		return "", "", pkgerrors.ErrMFATokenInvalid
	}

	// Verify the TOTP code against all verified secrets for this user.
	// Per RFC 6238, we track the last used time-step counter per secret and
	// reject any code whose counter has already been consumed (replay guard).
	secrets, err := s.repo.ListVerifiedTOTPSecrets(ctx, challenge.UserID)
	if err != nil {
		return "", "", fmt.Errorf("mfa.Service.VerifyChallenge list totp: %w", err)
	}
	if len(secrets) == 0 {
		return "", "", pkgerrors.ErrTOTPNotSetup
	}

	codeValid := false
	currentCounter := time.Now().UTC().Unix() / 30

	for _, secret := range secrets {
		b32Secret := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(secret.Secret)

		// Check counters current-1, current, current+1 (equivalent to skew=1)
		// but only accept if the counter is strictly greater than last used.
		for _, c := range []int64{currentCounter - 1, currentCounter, currentCounter + 1} {
			if c <= secret.LastUsedCounter {
				continue // this counter (or an earlier one) was already used
			}
			// Validate code at the exact time for this counter (skew=0).
			t := time.Unix(c*30, 0).UTC()
			valid, verr := totp.ValidateCustom(code, b32Secret, t, totp.ValidateOpts{
				Period:    30,
				Skew:     0,
				Digits:   otp.DigitsSix,
				Algorithm: otp.AlgorithmSHA1,
			})
			if verr == nil && valid {
				// Record the counter so this code can't be replayed.
				_ = s.repo.UpdateTOTPLastUsedCounter(ctx, secret.ID, c)
				codeValid = true
				break
			}
		}
		if codeValid {
			break
		}
	}
	if !codeValid {
		s.audit.WriteAsync(ctx, audit.Event{
			UserID:    challenge.UserID,
			Event:     audit.EventMFAChallengeFail,
			IPAddress: ipAddress,
		})
		return "", "", pkgerrors.ErrMFACodeInvalid
	}

	// Consume the challenge.
	if err := s.repo.ConsumeChallenge(ctx, challenge.ID); err != nil {
		return "", "", fmt.Errorf("mfa.Service.VerifyChallenge consume: %w", err)
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID:    challenge.UserID,
		DeviceID:  challenge.DeviceID,
		Event:     audit.EventMFAChallengeOK,
		IPAddress: ipAddress,
	})

	return challenge.UserID, challenge.DeviceID, nil
}

// ── Passkeys ────────────────────────────────────────────────────────────────

// ListPasskeys returns all non-revoked passkeys for a user.
func (s *Service) ListPasskeys(ctx context.Context, userID string) ([]*Passkey, error) {
	passkeys, err := s.repo.ListPasskeysForUser(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("mfa.Service.ListPasskeys: %w", err)
	}
	return passkeys, nil
}

// StorePasskey saves a newly registered passkey and enables MFA.
func (s *Service) StorePasskey(ctx context.Context, p *Passkey) error {
	if err := s.repo.CreatePasskey(ctx, p); err != nil {
		return fmt.Errorf("mfa.Service.StorePasskey: %w", err)
	}
	if err := s.users.SetMFAEnabled(ctx, p.UserID, true); err != nil {
		return fmt.Errorf("mfa.Service.StorePasskey enable mfa: %w", err)
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID: p.UserID,
		Event:  audit.EventPasskeyRegistered,
		Metadata: map[string]any{
			"passkey_name": p.Name,
		},
	})
	return nil
}

// AuthenticatePasskey updates the sign count after successful passkey login.
func (s *Service) AuthenticatePasskey(ctx context.Context, passkey *Passkey, newSignCount int64, ipAddress, userAgent string) error {
	if err := s.repo.UpdatePasskeySignCount(ctx, passkey.ID, newSignCount); err != nil {
		return fmt.Errorf("mfa.Service.AuthenticatePasskey: %w", err)
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID:    passkey.UserID,
		Event:     audit.EventPasskeyLogin,
		IPAddress: ipAddress,
		UserAgent: userAgent,
		Metadata: map[string]any{
			"passkey_name": passkey.Name,
		},
	})
	return nil
}

// RevokePasskey soft-deletes a passkey and clears mfa_enabled if no other
// methods remain.
func (s *Service) RevokePasskey(ctx context.Context, userID, passkeyID string) error {
	p, err := s.repo.GetPasskeyByID(ctx, passkeyID)
	if err != nil {
		return fmt.Errorf("mfa.Service.RevokePasskey get: %w", err)
	}
	if p == nil || p.UserID != userID {
		return pkgerrors.ErrPasskeyNotFound
	}

	if err := s.repo.RevokePasskey(ctx, passkeyID); err != nil {
		return fmt.Errorf("mfa.Service.RevokePasskey: %w", err)
	}

	// Check if any MFA methods remain.
	passkeyCount, err := s.repo.CountActivePasskeys(ctx, userID)
	if err != nil {
		return fmt.Errorf("mfa.Service.RevokePasskey count: %w", err)
	}
	totpCount, _ := s.repo.CountVerifiedTOTPSecrets(ctx, userID)

	if passkeyCount == 0 && totpCount == 0 {
		if err := s.users.SetMFAEnabled(ctx, userID, false); err != nil {
			return fmt.Errorf("mfa.Service.RevokePasskey disable mfa: %w", err)
		}
	}

	s.audit.WriteAsync(ctx, audit.Event{
		UserID: userID,
		Event:  audit.EventPasskeyRevoked,
		Metadata: map[string]any{
			"passkey_id": passkeyID,
		},
	})
	return nil
}

// GetPasskeyByCredentialID looks up a passkey by its WebAuthn credential ID.
func (s *Service) GetPasskeyByCredentialID(ctx context.Context, credentialID []byte) (*Passkey, error) {
	p, err := s.repo.GetPasskeyByCredentialID(ctx, credentialID)
	if err != nil {
		return nil, fmt.Errorf("mfa.Service.GetPasskeyByCredentialID: %w", err)
	}
	return p, nil
}

// ── Helpers ─────────────────────────────────────────────────────────────────

func generateChallengeToken() (raw, hash string, err error) {
	b := make([]byte, challengeTokenSize)
	if _, err = rand.Read(b); err != nil {
		return "", "", fmt.Errorf("mfa: generate challenge token: %w", err)
	}
	raw = base64.RawURLEncoding.EncodeToString(b)
	hash = hashChallengeToken(raw)
	return raw, hash, nil
}

func hashChallengeToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
