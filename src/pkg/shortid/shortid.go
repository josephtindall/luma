package shortid

import (
	"crypto/rand"
	"fmt"
	"math/big"
)

const alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const defaultLength = 10

// Generate returns a cryptographically random short ID of 10 characters
// using a base-62 alphabet [0-9A-Za-z].
func Generate() (string, error) {
	result := make([]byte, defaultLength)
	for i := range result {
		idx, err := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		if err != nil {
			return "", fmt.Errorf("shortid: rand: %w", err)
		}
		result[i] = alphabet[idx.Int64()]
	}
	return string(result), nil
}
