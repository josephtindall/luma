package bootstrap

import (
	"encoding/json"
	"net/http"
)

// BootstrapGate is the second enforcement layer for the bootstrap state machine.
// It wraps the entire router and allows or blocks paths based on current state.
//
// Enforcement layers (all three must pass — passing one is insufficient):
//  1. DB column — setup_state in haven.instance
//  2. This middleware — evaluated on every request
//  3. Handler — explicit State check at the start of each setup handler
type BootstrapGate struct {
	repo StateRepository
}

// NewBootstrapGate constructs the middleware with a state repository.
func NewBootstrapGate(repo StateRepository) *BootstrapGate {
	return &BootstrapGate{repo: repo}
}

// Middleware returns an http.Handler middleware function.
func (g *BootstrapGate) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		state, err := g.repo.Get(r.Context())
		if err != nil {
			writeGateError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "state unavailable")
			return
		}

		path := r.URL.Path

		switch state.SetupState {
		case StateUnclaimed:
			// Only health + token verification allowed.
			if !isAllowedInUnclaimed(path) {
				writeGateError(w, http.StatusServiceUnavailable, "SETUP_REQUIRED",
					"instance not configured; complete setup first")
				return
			}

		case StateSetup:
			// Only setup wizard paths allowed.
			if !isAllowedInSetup(path) {
				writeGateError(w, http.StatusServiceUnavailable, "SETUP_IN_PROGRESS",
					"setup in progress; complete the wizard first")
				return
			}

		case StateActive:
			// Setup endpoints are permanently closed.
			if isSetupPath(path) {
				writeGateError(w, http.StatusGone, "SETUP_COMPLETE",
					"setup already complete")
				return
			}
		}

		next.ServeHTTP(w, r)
	})
}

func isAllowedInUnclaimed(path string) bool {
	return path == "/" || path == "/api/setup/verify-token" || path == "/api/haven/health"
}

func isAllowedInSetup(path string) bool {
	return path == "/" || path == "/api/haven/health" || isSetupPath(path)
}

func isSetupPath(path string) bool {
	return len(path) >= 10 && path[:10] == "/api/setup"
}

func writeGateError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{
		"code":    code,
		"message": msg,
	})
}
