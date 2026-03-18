package authz

import (
	"context"
	"log/slog"
	"net/http"
)

// Resource identifies the target of a permission check.
type Resource struct {
	Type    string // page | task | flow | vault
	ID      string // short ID or UUID
	VaultID string // UUID of the owning vault
}

// PermissionChecker calls the auth service to check a permission.
type PermissionChecker interface {
	CheckPermission(ctx context.Context, req CheckRequest) (bool, error)
}

// CheckRequest is the body sent to the auth service's /authz/check endpoint.
type CheckRequest struct {
	UserID       string `json:"user_id"`
	Action       string `json:"action"`
	ResourceType string `json:"resource_type"`
	ResourceID   string `json:"resource_id"`
	VaultID      string `json:"vault_id"`
}

// UserIDExtractor extracts the authenticated user's ID from the request context.
type UserIDExtractor func(ctx context.Context) string

// Authorizer is the single entry point for all permission checks in Luma.
type Authorizer struct {
	checker         PermissionChecker
	userIDFromCtx   UserIDExtractor
}

// NewAuthorizer creates a new Authorizer with the given permission checker
// and a function that extracts the user ID from context.
func NewAuthorizer(checker PermissionChecker, userIDFromCtx UserIDExtractor) *Authorizer {
	return &Authorizer{checker: checker, userIDFromCtx: userIDFromCtx}
}

// RequireCan checks whether the authenticated user has permission to perform
// the given action on the given resource. If the check fails or the user is
// not authorized, it writes a 403 response and returns false. Handlers should
// return immediately when RequireCan returns false.
func (a *Authorizer) RequireCan(ctx context.Context, w http.ResponseWriter, action string, resource Resource) bool {
	userID := a.userIDFromCtx(ctx)
	if userID == "" {
		writeForbidden(w)
		return false
	}

	allowed, err := a.checker.CheckPermission(ctx, CheckRequest{
		UserID:       userID,
		Action:       action,
		ResourceType: resource.Type,
		ResourceID:   resource.ID,
		VaultID:      resource.VaultID,
	})
	if err != nil {
		slog.ErrorContext(ctx, "authz check failed", "action", action, "error", err)
		writeForbidden(w)
		return false
	}
	if !allowed {
		writeForbidden(w)
		return false
	}
	return true
}

// Can checks whether the authenticated user has permission to perform the action
// without writing an HTTP response. Returns false on error (fail-safe).
func (a *Authorizer) Can(ctx context.Context, action string, resource Resource) bool {
	userID := a.userIDFromCtx(ctx)
	if userID == "" {
		return false
	}

	allowed, err := a.checker.CheckPermission(ctx, CheckRequest{
		UserID:       userID,
		Action:       action,
		ResourceType: resource.Type,
		ResourceID:   resource.ID,
		VaultID:      resource.VaultID,
	})
	if err != nil {
		slog.ErrorContext(ctx, "authz check failed", "action", action, "error", err)
		return false
	}
	return allowed
}

func writeForbidden(w http.ResponseWriter) {
	http.Error(w, `{"error":"forbidden"}`, http.StatusForbidden)
}
