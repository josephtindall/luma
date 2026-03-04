package crypto

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"fmt"
	"strings"

	"golang.org/x/crypto/argon2"
)

// Parameters fixed per spec: time=3, memory=65536KB, parallelism=2,
// saltLen=32B, keyLen=32B. Target ~250ms. Never deviate from these values.
const (
	argonTime        = 3
	argonMemory      = 65536
	argonParallelism = 2
	argonSaltLen     = 32
	argonKeyLen      = 32
)

// HashPassword hashes password with Argon2id and returns a PHC string.
// The caller must not log or persist the raw password.
func HashPassword(password string) (string, error) {
	salt := make([]byte, argonSaltLen)
	if _, err := rand.Read(salt); err != nil {
		return "", fmt.Errorf("crypto: generate salt: %w", err)
	}

	hash := argon2.IDKey(
		[]byte(password),
		salt,
		argonTime,
		argonMemory,
		argonParallelism,
		argonKeyLen,
	)

	// PHC format: $argon2id$v=19$m=65536,t=3,p=2$<salt>$<hash>
	encoded := fmt.Sprintf(
		"$argon2id$v=%d$m=%d,t=%d,p=%d$%s$%s",
		argon2.Version,
		argonMemory,
		argonTime,
		argonParallelism,
		base64.RawStdEncoding.EncodeToString(salt),
		base64.RawStdEncoding.EncodeToString(hash),
	)
	return encoded, nil
}

// VerifyPassword returns true if password matches the PHC-format hash.
// Uses constant-time comparison. Never reveals which part failed.
func VerifyPassword(password, phc string) (bool, error) {
	params, salt, expected, err := parsePHC(phc)
	if err != nil {
		return false, fmt.Errorf("crypto: parse PHC hash: %w", err)
	}

	actual := argon2.IDKey(
		[]byte(password),
		salt,
		params.time,
		params.memory,
		params.parallelism,
		uint32(len(expected)),
	)

	return subtle.ConstantTimeCompare(actual, expected) == 1, nil
}

type argonParams struct {
	time        uint32
	memory      uint32
	parallelism uint8
}

func parsePHC(phc string) (argonParams, []byte, []byte, error) {
	// $argon2id$v=19$m=65536,t=3,p=2$<salt>$<hash>
	parts := strings.Split(phc, "$")
	if len(parts) != 6 || parts[1] != "argon2id" {
		return argonParams{}, nil, nil, fmt.Errorf("invalid PHC format")
	}

	var p argonParams
	_, err := fmt.Sscanf(parts[3], "m=%d,t=%d,p=%d", &p.memory, &p.time, &p.parallelism)
	if err != nil {
		return argonParams{}, nil, nil, fmt.Errorf("parse params: %w", err)
	}

	salt, err := base64.RawStdEncoding.DecodeString(parts[4])
	if err != nil {
		return argonParams{}, nil, nil, fmt.Errorf("decode salt: %w", err)
	}

	hash, err := base64.RawStdEncoding.DecodeString(parts[5])
	if err != nil {
		return argonParams{}, nil, nil, fmt.Errorf("decode hash: %w", err)
	}

	return p, salt, hash, nil
}
