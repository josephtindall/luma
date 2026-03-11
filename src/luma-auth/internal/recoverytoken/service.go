package recoverytoken

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"math/big"
)

// Service implements recovery token business logic.
type Service struct {
	repo Repository
}

// NewService constructs the recovery token service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// Generate creates a new 64-digit decimal recovery token for the user,
// stores its SHA-256 hash, and returns the raw token.
// Any existing token for the user is replaced.
func (s *Service) Generate(ctx context.Context, userID string) (string, error) {
	raw, err := generateRawToken()
	if err != nil {
		return "", fmt.Errorf("recoverytoken.Generate: %w", err)
	}
	hash := hashToken(raw)
	if err := s.repo.Upsert(ctx, userID, hash); err != nil {
		return "", fmt.Errorf("recoverytoken.Generate: %w", err)
	}
	return raw, nil
}

// HasToken returns true if the user has a stored recovery token.
func (s *Service) HasToken(ctx context.Context, userID string) (bool, error) {
	t, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return false, fmt.Errorf("recoverytoken.HasToken: %w", err)
	}
	return t != nil, nil
}

// VerifyAndConsume checks the raw token against the stored hash.
// If correct, the token is deleted and true is returned.
// If incorrect or absent, false is returned without error.
func (s *Service) VerifyAndConsume(ctx context.Context, userID, rawToken string) (bool, error) {
	t, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return false, fmt.Errorf("recoverytoken.VerifyAndConsume: %w", err)
	}
	if t == nil {
		return false, nil
	}
	if hashToken(rawToken) != t.TokenHash {
		return false, nil
	}
	if err := s.repo.DeleteByUserID(ctx, userID); err != nil {
		return false, fmt.Errorf("recoverytoken.VerifyAndConsume: delete: %w", err)
	}
	return true, nil
}

// generateRawToken returns a 64-character decimal string (16 groups × 4 digits).
func generateRawToken() (string, error) {
	const digits = 64
	buf := make([]byte, digits)
	for i := range buf {
		n, err := rand.Int(rand.Reader, big.NewInt(10))
		if err != nil {
			return "", err
		}
		buf[i] = byte('0' + n.Int64())
	}
	return string(buf), nil
}

// hashToken returns the hex-encoded SHA-256 of the raw token.
func hashToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
