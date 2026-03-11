package bootstrap

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// mockStateRepo satisfies StateRepository for middleware tests.
// Only Get is called by BootstrapGate; all write methods are no-ops.
type mockStateRepo struct {
	state State
}

func (m *mockStateRepo) Get(_ context.Context) (*InstanceState, error) {
	return &InstanceState{SetupState: m.state}, nil
}
func (m *mockStateRepo) EnsureRow(_ context.Context) error                               { return nil }
func (m *mockStateRepo) StoreSetupToken(_ context.Context, _ string, _ time.Time) error  { return nil }
func (m *mockStateRepo) TransitionToSetup(_ context.Context, _ time.Time) error          { return nil }
func (m *mockStateRepo) IncrementTokenFailures(_ context.Context) (int, error)           { return 0, nil }
func (m *mockStateRepo) ResetToUnclaimed(_ context.Context, _ string, _ time.Time) error { return nil }
func (m *mockStateRepo) ConfigureInstance(_ context.Context, _, _, _ string) error       { return nil }
func (m *mockStateRepo) UpdateSettings(_ context.Context, _ InstanceSettingsParams) error { return nil }
func (m *mockStateRepo) CreateOwnerAtomic(_ context.Context, _ CreateOwnerParams) (string, error) {
	return "", nil
}

// gateFor builds a BootstrapGate in the given fixed state.
func gateFor(state State) *BootstrapGate {
	return NewBootstrapGate(&mockStateRepo{state: state})
}

// okHandler is a next handler that records it was reached.
var okHandler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
})

func assertStatus(t *testing.T, gate *BootstrapGate, path string, wantStatus int) {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	rec := httptest.NewRecorder()
	gate.Middleware(okHandler).ServeHTTP(rec, req)
	if rec.Code != wantStatus {
		t.Errorf("path %q: status = %d, want %d", path, rec.Code, wantStatus)
	}
}

// ── UNCLAIMED ─────────────────────────────────────────────────────────────────

func TestGate_Unclaimed_AllowsRoot(t *testing.T) {
	assertStatus(t, gateFor(StateUnclaimed), "/", http.StatusOK)
}

func TestGate_Unclaimed_AllowsVerifyToken(t *testing.T) {
	assertStatus(t, gateFor(StateUnclaimed), "/api/setup/verify-token", http.StatusOK)
}

func TestGate_Unclaimed_AllowsHealth(t *testing.T) {
	assertStatus(t, gateFor(StateUnclaimed), "/api/auth/health", http.StatusOK)
}

func TestGate_Unclaimed_BlocksLogin(t *testing.T) {
	assertStatus(t, gateFor(StateUnclaimed), "/api/auth/login", http.StatusServiceUnavailable)
}

func TestGate_Unclaimed_BlocksSetupInstance(t *testing.T) {
	// /api/setup/instance requires SETUP state — not accessible from UNCLAIMED.
	assertStatus(t, gateFor(StateUnclaimed), "/api/setup/instance", http.StatusServiceUnavailable)
}

func TestGate_Unclaimed_BlocksAuthz(t *testing.T) {
	assertStatus(t, gateFor(StateUnclaimed), "/api/auth/authz/check", http.StatusServiceUnavailable)
}

// ── SETUP ─────────────────────────────────────────────────────────────────────

func TestGate_Setup_AllowsRoot(t *testing.T) {
	assertStatus(t, gateFor(StateSetup), "/", http.StatusOK)
}

func TestGate_Setup_AllowsHealth(t *testing.T) {
	assertStatus(t, gateFor(StateSetup), "/api/auth/health", http.StatusOK)
}

func TestGate_Setup_AllowsSetupPaths(t *testing.T) {
	gate := gateFor(StateSetup)
	for _, path := range []string{
		"/api/setup/verify-token",
		"/api/setup/instance",
		"/api/setup/owner",
	} {
		assertStatus(t, gate, path, http.StatusOK)
	}
}

func TestGate_Setup_BlocksLogin(t *testing.T) {
	assertStatus(t, gateFor(StateSetup), "/api/auth/login", http.StatusServiceUnavailable)
}

func TestGate_Setup_BlocksValidate(t *testing.T) {
	assertStatus(t, gateFor(StateSetup), "/api/auth/validate", http.StatusServiceUnavailable)
}

// ── ACTIVE ────────────────────────────────────────────────────────────────────

func TestGate_Active_AllowsLogin(t *testing.T) {
	assertStatus(t, gateFor(StateActive), "/api/auth/login", http.StatusOK)
}

func TestGate_Active_AllowsHealth(t *testing.T) {
	assertStatus(t, gateFor(StateActive), "/api/auth/health", http.StatusOK)
}

func TestGate_Active_AllowsValidate(t *testing.T) {
	assertStatus(t, gateFor(StateActive), "/api/auth/validate", http.StatusOK)
}

func TestGate_Active_BlocksSetupVerifyToken(t *testing.T) {
	assertStatus(t, gateFor(StateActive), "/api/setup/verify-token", http.StatusGone)
}

func TestGate_Active_BlocksSetupOwner(t *testing.T) {
	assertStatus(t, gateFor(StateActive), "/api/setup/owner", http.StatusGone)
}

func TestGate_Active_BlocksSetupInstance(t *testing.T) {
	assertStatus(t, gateFor(StateActive), "/api/setup/instance", http.StatusGone)
}
