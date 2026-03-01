package token

import (
	"testing"
	"time"
)

// testKey is a 512-bit key used across token tests.
var testKey = func() []byte {
	k := make([]byte, 64)
	for i := range k {
		k[i] = byte(i + 1)
	}
	return k
}()

func TestGenerateAccessToken_NonEmpty(t *testing.T) {
	tok, err := GenerateAccessToken("user-1", "device-1", "builtin:instance-owner", testKey)
	if err != nil {
		t.Fatalf("GenerateAccessToken: %v", err)
	}
	if tok == "" {
		t.Error("expected non-empty token string")
	}
}

func TestValidateAccessToken_RoundTrip(t *testing.T) {
	tok, err := GenerateAccessToken("user-42", "device-7", "builtin:instance-member", testKey)
	if err != nil {
		t.Fatal(err)
	}
	claims, err := ValidateAccessToken(tok, testKey, nil)
	if err != nil {
		t.Fatalf("ValidateAccessToken: %v", err)
	}
	if claims.Subject != "user-42" {
		t.Errorf("Subject = %q, want %q", claims.Subject, "user-42")
	}
	if claims.DeviceID != "device-7" {
		t.Errorf("DeviceID = %q, want %q", claims.DeviceID, "device-7")
	}
	if claims.Role != "builtin:instance-member" {
		t.Errorf("Role = %q, want %q", claims.Role, "builtin:instance-member")
	}
}

func TestValidateAccessToken_JTISet(t *testing.T) {
	tok, _ := GenerateAccessToken("u", "d", "r", testKey)
	claims, err := ValidateAccessToken(tok, testKey, nil)
	if err != nil {
		t.Fatal(err)
	}
	if claims.ID == "" {
		t.Error("expected jti (ID) to be set")
	}
}

func TestValidateAccessToken_Lifetime(t *testing.T) {
	tok, _ := GenerateAccessToken("u", "d", "r", testKey)
	claims, err := ValidateAccessToken(tok, testKey, nil)
	if err != nil {
		t.Fatal(err)
	}
	if claims.IssuedAt == nil || claims.ExpiresAt == nil {
		t.Fatal("expected iat and exp to be set")
	}
	lifetime := claims.ExpiresAt.Time.Sub(claims.IssuedAt.Time)
	if lifetime < 14*time.Minute || lifetime > 16*time.Minute {
		t.Errorf("token lifetime = %v, want ~15m", lifetime)
	}
}

func TestValidateAccessToken_WrongKey(t *testing.T) {
	tok, err := GenerateAccessToken("u", "d", "r", testKey)
	if err != nil {
		t.Fatal(err)
	}
	wrongKey := make([]byte, 64) // all zeros
	_, err = ValidateAccessToken(tok, wrongKey, nil)
	if err == nil {
		t.Error("expected error when validating with wrong key")
	}
}

func TestValidateAccessToken_FallsBackToPrevKey(t *testing.T) {
	prevKey := make([]byte, 64)
	for i := range prevKey {
		prevKey[i] = 0xff
	}
	tok, err := GenerateAccessToken("u", "d", "r", prevKey)
	if err != nil {
		t.Fatal(err)
	}
	// currentKey doesn't match; prevKey should succeed.
	claims, err := ValidateAccessToken(tok, testKey, prevKey)
	if err != nil {
		t.Fatalf("expected prev-key fallback to succeed: %v", err)
	}
	if claims.Subject != "u" {
		t.Errorf("Subject = %q, want u", claims.Subject)
	}
}

func TestValidateAccessToken_BothKeysMiss(t *testing.T) {
	tok, _ := GenerateAccessToken("u", "d", "r", testKey)
	keyA := make([]byte, 64)
	keyB := make([]byte, 64)
	for i := range keyB {
		keyB[i] = 0xab
	}
	_, err := ValidateAccessToken(tok, keyA, keyB)
	if err == nil {
		t.Error("expected error when neither key matches")
	}
}

func TestValidateAccessToken_NilPrevKey(t *testing.T) {
	tok, _ := GenerateAccessToken("u", "d", "r", testKey)
	claims, err := ValidateAccessToken(tok, testKey, nil)
	if err != nil {
		t.Fatalf("unexpected error with nil prevKey: %v", err)
	}
	if claims.Subject != "u" {
		t.Errorf("Subject = %q", claims.Subject)
	}
}
