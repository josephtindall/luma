package shortid

import (
	"testing"
)

func TestGenerate_Length(t *testing.T) {
	id, err := Generate()
	if err != nil {
		t.Fatalf("Generate() error: %v", err)
	}
	if len(id) != defaultLength {
		t.Errorf("expected length %d, got %d", defaultLength, len(id))
	}
}

func TestGenerate_AlphabetValidity(t *testing.T) {
	for i := 0; i < 100; i++ {
		id, err := Generate()
		if err != nil {
			t.Fatalf("Generate() error: %v", err)
		}
		for _, c := range id {
			found := false
			for _, a := range alphabet {
				if c == a {
					found = true
					break
				}
			}
			if !found {
				t.Errorf("character %q not in alphabet", c)
			}
		}
	}
}

func TestGenerate_Uniqueness(t *testing.T) {
	seen := make(map[string]bool, 1000)
	for i := 0; i < 1000; i++ {
		id, err := Generate()
		if err != nil {
			t.Fatalf("Generate() error: %v", err)
		}
		if seen[id] {
			t.Fatalf("duplicate ID generated: %s", id)
		}
		seen[id] = true
	}
}
