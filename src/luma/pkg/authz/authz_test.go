package authz

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"
)

type mockChecker struct {
	allowed bool
	err     error
	gotReq  CheckRequest
}

func (m *mockChecker) CheckPermission(_ context.Context, req CheckRequest) (bool, error) {
	m.gotReq = req
	return m.allowed, m.err
}

func userIDFromCtx(userID string) UserIDExtractor {
	return func(_ context.Context) string { return userID }
}

func TestRequireCan_Allowed(t *testing.T) {
	checker := &mockChecker{allowed: true}
	a := NewAuthorizer(checker, userIDFromCtx("user-1"))
	w := httptest.NewRecorder()

	ok := a.RequireCan(context.Background(), w, "vault:read", Resource{
		Type:    "vault",
		ID:      "v-1",
		VaultID: "v-1",
	})

	if !ok {
		t.Fatal("expected RequireCan to return true")
	}
	if w.Code != http.StatusOK {
		t.Errorf("expected status 200, got %d", w.Code)
	}
}

func TestRequireCan_Denied(t *testing.T) {
	checker := &mockChecker{allowed: false}
	a := NewAuthorizer(checker, userIDFromCtx("user-1"))
	w := httptest.NewRecorder()

	ok := a.RequireCan(context.Background(), w, "vault:edit", Resource{
		Type:    "vault",
		ID:      "v-1",
		VaultID: "v-1",
	})

	if ok {
		t.Fatal("expected RequireCan to return false")
	}
	if w.Code != http.StatusForbidden {
		t.Errorf("expected status 403, got %d", w.Code)
	}
}

func TestRequireCan_Error(t *testing.T) {
	checker := &mockChecker{err: errors.New("auth service unavailable")}
	a := NewAuthorizer(checker, userIDFromCtx("user-1"))
	w := httptest.NewRecorder()

	ok := a.RequireCan(context.Background(), w, "page:read", Resource{
		Type: "page",
		ID:   "p-1",
	})

	if ok {
		t.Fatal("expected RequireCan to return false on error")
	}
	if w.Code != http.StatusForbidden {
		t.Errorf("expected status 403, got %d", w.Code)
	}
}

func TestRequireCan_NoUserID(t *testing.T) {
	checker := &mockChecker{allowed: true}
	a := NewAuthorizer(checker, userIDFromCtx(""))
	w := httptest.NewRecorder()

	ok := a.RequireCan(context.Background(), w, "vault:read", Resource{
		Type: "vault",
		ID:   "v-1",
	})

	if ok {
		t.Fatal("expected RequireCan to return false when user ID is empty")
	}
	if w.Code != http.StatusForbidden {
		t.Errorf("expected status 403, got %d", w.Code)
	}
}

func TestRequireCan_CheckRequestConstruction(t *testing.T) {
	checker := &mockChecker{allowed: true}
	a := NewAuthorizer(checker, userIDFromCtx("user-42"))
	w := httptest.NewRecorder()

	a.RequireCan(context.Background(), w, "task:edit", Resource{
		Type:    "task",
		ID:      "t-abc",
		VaultID: "v-xyz",
	})

	want := CheckRequest{
		UserID:       "user-42",
		Action:       "task:edit",
		ResourceType: "task",
		ResourceID:   "t-abc",
		VaultID:      "v-xyz",
	}
	if checker.gotReq != want {
		t.Errorf("CheckRequest mismatch:\n  got  %+v\n  want %+v", checker.gotReq, want)
	}
}
