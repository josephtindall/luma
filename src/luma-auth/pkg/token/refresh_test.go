package token

import (
	"encoding/base64"
	"testing"
)

func TestGenerateRefreshToken_Format(t *testing.T) {
	raw, hash, err := GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken: %v", err)
	}
	if raw == "" || hash == "" {
		t.Error("expected non-empty raw and hash")
	}
	b, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		t.Errorf("raw token is not valid base64url: %v", err)
	}
	if len(b) != 32 {
		t.Errorf("decoded token length = %d, want 32 bytes", len(b))
	}
}

func TestGenerateRefreshToken_Unique(t *testing.T) {
	raw1, hash1, _ := GenerateRefreshToken()
	raw2, hash2, _ := GenerateRefreshToken()
	if raw1 == raw2 {
		t.Error("two raw refresh tokens must not be equal")
	}
	if hash1 == hash2 {
		t.Error("two refresh token hashes must not be equal")
	}
}

func TestGenerateRefreshToken_RawDiffersFromHash(t *testing.T) {
	raw, hash, _ := GenerateRefreshToken()
	if raw == hash {
		t.Error("raw token must differ from its hash")
	}
}

func TestHashRefreshToken_Deterministic(t *testing.T) {
	a := HashRefreshToken("some-token-value")
	b := HashRefreshToken("some-token-value")
	if a != b {
		t.Error("same input must produce the same hash")
	}
}

func TestHashRefreshToken_DifferentInputs(t *testing.T) {
	a := HashRefreshToken("token-A")
	b := HashRefreshToken("token-B")
	if a == b {
		t.Error("different inputs must produce different hashes")
	}
}

func TestHashRefreshToken_HexLength(t *testing.T) {
	h := HashRefreshToken("any-value")
	// SHA-256 = 32 bytes = 64 hex chars
	if len(h) != 64 {
		t.Errorf("hash length = %d, want 64 hex chars", len(h))
	}
	for _, c := range h {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			t.Errorf("non-lowercase-hex character %q in hash", c)
			break
		}
	}
}

func TestHashRefreshToken_MatchesGenerate(t *testing.T) {
	raw, hashFromGen, _ := GenerateRefreshToken()
	hashDirect := HashRefreshToken(raw)
	if hashFromGen != hashDirect {
		t.Error("HashRefreshToken(raw) must equal the hash returned by GenerateRefreshToken")
	}
}
