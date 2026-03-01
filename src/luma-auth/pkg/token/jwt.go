package token

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const accessTokenLifetime = 15 * time.Minute

// Claims is the exact JWT payload. No extra fields — ever.
// sub=user ID, did=device ID, role=instance role ID.
type Claims struct {
	jwt.RegisteredClaims
	DeviceID string `json:"did"`
	Role     string `json:"role"`
}

// GenerateAccessToken creates a signed HMAC-SHA256 JWT for the given user.
// signingKey must be the 512-bit key from config.
func GenerateAccessToken(userID, deviceID, role string, signingKey []byte) (string, error) {
	jti, err := randomHex(16)
	if err != nil {
		return "", fmt.Errorf("token: generate jti: %w", err)
	}

	now := time.Now().UTC()
	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(accessTokenLifetime)),
			ID:        jti,
		},
		DeviceID: deviceID,
		Role:     role,
	}

	t := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := t.SignedString(signingKey)
	if err != nil {
		return "", fmt.Errorf("token: sign JWT: %w", err)
	}
	return signed, nil
}

// ValidateAccessToken parses and validates a JWT. Tries currentKey first,
// then prevKey (non-nil during zero-downtime key rotation). Returns Claims on
// success or an error if invalid, expired, or signed with an unknown key.
func ValidateAccessToken(tokenStr string, currentKey, prevKey []byte) (*Claims, error) {
	claims, err := parseWithKey(tokenStr, currentKey)
	if err == nil {
		return claims, nil
	}

	if prevKey != nil {
		claims, err = parseWithKey(tokenStr, prevKey)
		if err == nil {
			return claims, nil
		}
	}

	return nil, fmt.Errorf("token: validate: %w", err)
}

func parseWithKey(tokenStr string, key []byte) (*Claims, error) {
	t, err := jwt.ParseWithClaims(tokenStr, &Claims{}, func(t *jwt.Token) (any, error) {
		if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", t.Header["alg"])
		}
		return key, nil
	})
	if err != nil {
		return nil, err
	}

	claims, ok := t.Claims.(*Claims)
	if !ok || !t.Valid {
		return nil, fmt.Errorf("invalid token claims")
	}
	return claims, nil
}

func randomHex(n int) (string, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}
