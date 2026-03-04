package preferences

import (
	"context"
	"strings"
	"testing"
)

// mockRepo is a no-op repository for unit tests.
type mockRepo struct{}

func (m *mockRepo) Get(_ context.Context, _ string) (*Preferences, error) {
	return &Preferences{}, nil
}
func (m *mockRepo) Update(_ context.Context, _ string, _ UpdateParams) error {
	return nil
}

func svcUnderTest() *Service {
	return NewService(&mockRepo{})
}

func strPtr(s string) *string { return &s }

// ── Theme ─────────────────────────────────────────────────────────────────────

func TestUpdate_Theme_Valid(t *testing.T) {
	svc := svcUnderTest()
	for _, theme := range []string{"system", "light", "dark"} {
		if err := svc.Update(context.Background(), "u1", UpdateParams{Theme: strPtr(theme)}); err != nil {
			t.Errorf("theme %q: unexpected error: %v", theme, err)
		}
	}
}

func TestUpdate_Theme_Invalid(t *testing.T) {
	svc := svcUnderTest()
	err := svc.Update(context.Background(), "u1", UpdateParams{Theme: strPtr("neon")})
	if err == nil {
		t.Fatal("expected error for invalid theme, got nil")
	}
	if !strings.Contains(err.Error(), "theme") {
		t.Errorf("error should mention theme, got: %v", err)
	}
}

// ── TimeFormat ────────────────────────────────────────────────────────────────

func TestUpdate_TimeFormat_Valid(t *testing.T) {
	svc := svcUnderTest()
	for _, f := range []string{"12h", "24h"} {
		if err := svc.Update(context.Background(), "u1", UpdateParams{TimeFormat: strPtr(f)}); err != nil {
			t.Errorf("time_format %q: unexpected error: %v", f, err)
		}
	}
}

func TestUpdate_TimeFormat_Invalid(t *testing.T) {
	svc := svcUnderTest()
	err := svc.Update(context.Background(), "u1", UpdateParams{TimeFormat: strPtr("6h")})
	if err == nil {
		t.Fatal("expected error for invalid time_format, got nil")
	}
	if !strings.Contains(err.Error(), "time_format") {
		t.Errorf("error should mention time_format, got: %v", err)
	}
}

// ── Timezone ──────────────────────────────────────────────────────────────────

func TestUpdate_Timezone_Valid(t *testing.T) {
	svc := svcUnderTest()
	for _, tz := range []string{"UTC", "America/New_York", "Europe/London", "Asia/Tokyo"} {
		if err := svc.Update(context.Background(), "u1", UpdateParams{Timezone: strPtr(tz)}); err != nil {
			t.Errorf("timezone %q: unexpected error: %v", tz, err)
		}
	}
}

func TestUpdate_Timezone_Invalid(t *testing.T) {
	svc := svcUnderTest()
	err := svc.Update(context.Background(), "u1", UpdateParams{Timezone: strPtr("Moon/Crater")})
	if err == nil {
		t.Fatal("expected error for invalid timezone, got nil")
	}
	if !strings.Contains(err.Error(), "timezone") {
		t.Errorf("error should mention timezone, got: %v", err)
	}
}

// ── Language ──────────────────────────────────────────────────────────────────

func TestUpdate_Language_Valid(t *testing.T) {
	svc := svcUnderTest()
	for _, lang := range []string{"en", "en-US", "zh-Hans-CN", "fr-CA"} {
		if err := svc.Update(context.Background(), "u1", UpdateParams{Language: strPtr(lang)}); err != nil {
			t.Errorf("language %q: unexpected error: %v", lang, err)
		}
	}
}

func TestUpdate_Language_Invalid(t *testing.T) {
	svc := svcUnderTest()
	err := svc.Update(context.Background(), "u1", UpdateParams{Language: strPtr("not valid!")})
	if err == nil {
		t.Fatal("expected error for invalid language, got nil")
	}
	if !strings.Contains(err.Error(), "language") {
		t.Errorf("error should mention language, got: %v", err)
	}
}

// ── Nil fields pass through without error ─────────────────────────────────────

func TestUpdate_NilFieldsPassThrough(t *testing.T) {
	svc := svcUnderTest()
	if err := svc.Update(context.Background(), "u1", UpdateParams{}); err != nil {
		t.Fatalf("empty update: unexpected error: %v", err)
	}
}
