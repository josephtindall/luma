package crypto

import (
	"strings"
	"testing"
)

// Each HashPassword call takes ~250 ms (Argon2id by design).
// These tests verify correctness, not speed.

func TestHashPassword_ValidPHCFormat(t *testing.T) {
	hash, err := HashPassword("correct-horse-battery-staple")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	if !strings.HasPrefix(hash, "$argon2id$") {
		t.Errorf("expected PHC prefix $argon2id$, got %q", hash)
	}
	parts := strings.Split(hash, "$")
	if len(parts) != 6 {
		t.Errorf("expected 6 PHC segments, got %d: %v", len(parts), parts)
	}
}

func TestHashPassword_UniqueSalts(t *testing.T) {
	a, err := HashPassword("same-password")
	if err != nil {
		t.Fatal(err)
	}
	b, err := HashPassword("same-password")
	if err != nil {
		t.Fatal(err)
	}
	if a == b {
		t.Error("two hashes of the same password must differ (random salt)")
	}
}

func TestVerifyPassword_Correct(t *testing.T) {
	hash, err := HashPassword("my-secret-password")
	if err != nil {
		t.Fatal(err)
	}
	ok, err := VerifyPassword("my-secret-password", hash)
	if err != nil {
		t.Fatalf("VerifyPassword: %v", err)
	}
	if !ok {
		t.Error("expected correct password to verify successfully")
	}
}

func TestVerifyPassword_Wrong(t *testing.T) {
	hash, err := HashPassword("my-secret-password")
	if err != nil {
		t.Fatal(err)
	}
	ok, err := VerifyPassword("wrong-password", hash)
	if err != nil {
		t.Fatalf("unexpected error on wrong password: %v", err)
	}
	if ok {
		t.Error("expected wrong password to fail verification")
	}
}

func TestVerifyPassword_TamperedHash(t *testing.T) {
	hash, err := HashPassword("password")
	if err != nil {
		t.Fatal(err)
	}
	// Replace the hash segment (last $-delimited part) with garbage.
	idx := strings.LastIndex(hash, "$")
	tampered := hash[:idx+1] + "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
	ok, err := VerifyPassword("password", tampered)
	if err != nil {
		t.Fatalf("unexpected error on tampered hash: %v", err)
	}
	if ok {
		t.Error("expected tampered hash to fail verification")
	}
}

func TestVerifyPassword_InvalidPHC(t *testing.T) {
	_, err := VerifyPassword("password", "not-a-phc-string")
	if err == nil {
		t.Error("expected error for non-PHC input")
	}
}

func TestVerifyPassword_WrongAlgorithm(t *testing.T) {
	_, err := VerifyPassword("password", "$bcrypt$garbage")
	if err == nil {
		t.Error("expected error for non-argon2id algorithm prefix")
	}
}
