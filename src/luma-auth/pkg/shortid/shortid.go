// Package shortid provides short, URL-safe, random identifiers.
// The auth service does not use short IDs internally — this package is included for
// Luma consumers that need human-friendly IDs for pages, tasks, and flows.
package shortid

import (
	"crypto/rand"
	"fmt"
	"math/big"
)

const alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

// New returns a cryptographically random short ID of length n using a
// base-62 alphabet [0-9A-Za-z]. Panics if n < 1.
func New(n int) (string, error) {
	if n < 1 {
		panic("shortid: n must be >= 1")
	}

	result := make([]byte, n)
	for i := range result {
		idx, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			return "", fmt.Errorf("shortid: rand: %w", err)
		}
		result[i] = alphabet[idx.Int64()]
	}
	return string(result), nil
}

// Must is like New but panics on error. Convenient in tests and init code.
func Must(n int) string {
	id, err := New(n)
	if err != nil {
		panic(err)
	}
	return id
}
