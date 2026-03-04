package token

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"time"
)

const refreshTokenLifetime = 30 * 24 * time.Hour // 30 days

// GenerateRefreshToken returns a cryptographically random refresh token
// (32 bytes, base64url encoded) and its SHA-256 hash (hex-encoded).
//
// Store ONLY the hash. The raw token is handed to the client and must never
// be written to the database.
func GenerateRefreshToken() (raw, hash string, err error) {
	b := make([]byte, 32)
	if _, err = rand.Read(b); err != nil {
		return "", "", fmt.Errorf("token: generate refresh: %w", err)
	}

	raw = base64.RawURLEncoding.EncodeToString(b)
	hash = hashRefreshToken(raw)
	return raw, hash, nil
}

// HashRefreshToken returns the SHA-256 hex hash of a raw refresh token.
// Used to look up a token from client-supplied value before comparing.
func HashRefreshToken(raw string) string {
	return hashRefreshToken(raw)
}

// RefreshTokenExpiry returns the absolute expiry time for a new refresh token.
func RefreshTokenExpiry() time.Time {
	return time.Now().UTC().Add(refreshTokenLifetime)
}

func hashRefreshToken(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}
