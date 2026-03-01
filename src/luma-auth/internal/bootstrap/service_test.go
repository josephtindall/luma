package bootstrap

import (
	"context"
	"strings"
	"testing"
)

// serviceFor builds a Service backed by a mock repo fixed in the given state.
func serviceFor(state State) *Service {
	return NewService(&mockStateRepo{state: state})
}

// ── ConfigureInstance validation ──────────────────────────────────────────────

func TestConfigureInstance_Valid(t *testing.T) {
	svc := serviceFor(StateSetup)
	if err := svc.ConfigureInstance(context.Background(), "My Haven", "en-US", "America/New_York"); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestConfigureInstance_InvalidTimezone(t *testing.T) {
	svc := serviceFor(StateSetup)
	err := svc.ConfigureInstance(context.Background(), "My Haven", "en-US", "Not/ATimezone")
	if err == nil {
		t.Fatal("expected error for invalid timezone, got nil")
	}
	if !strings.Contains(err.Error(), "timezone") {
		t.Errorf("error should mention timezone, got: %v", err)
	}
}

func TestConfigureInstance_InvalidLocale(t *testing.T) {
	svc := serviceFor(StateSetup)
	err := svc.ConfigureInstance(context.Background(), "My Haven", "not valid locale!", "UTC")
	if err == nil {
		t.Fatal("expected error for invalid locale, got nil")
	}
	if !strings.Contains(err.Error(), "locale") {
		t.Errorf("error should mention locale, got: %v", err)
	}
}

func TestConfigureInstance_NameTooShort(t *testing.T) {
	svc := serviceFor(StateSetup)
	err := svc.ConfigureInstance(context.Background(), "X", "en-US", "UTC")
	if err == nil {
		t.Fatal("expected error for short name, got nil")
	}
}

func TestConfigureInstance_WrongState(t *testing.T) {
	svc := serviceFor(StateUnclaimed)
	err := svc.ConfigureInstance(context.Background(), "My Haven", "en-US", "UTC")
	if err == nil {
		t.Fatal("expected error when not in SETUP state, got nil")
	}
}
