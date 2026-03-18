package authz

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/redis/go-redis/v9"
)

// Resource identifies the target of a permission check.
type Resource struct {
	Type    string // e.g. "page", "task", "vault"
	ID      string
	VaultID string
}

// CheckRequest is the body of POST /api/auth/authz/check.
type CheckRequest struct {
	UserID       string `json:"user_id"`
	Action       string `json:"action"`                  // e.g. "page:edit"
	ResourceType string `json:"resource_type"`           // e.g. "page"
	ResourceID   string `json:"resource_id"`
	VaultID      string `json:"vault_id"`
	VaultRole    string `json:"vault_role,omitempty"`    // caller's vault membership role, e.g. "builtin:vault-admin"
}

// CheckResult is the response body.
type CheckResult struct {
	Allowed bool   `json:"allowed"`
	Reason  string `json:"reason,omitempty"` // populated only when Allowed=false
}

// Authorizer evaluates the four-dimension permission model.
// Implementations may cache results in Redis (5-min TTL).
type Authorizer interface {
	Check(ctx context.Context, req CheckRequest) (CheckResult, error)
}

// Repository provides the data the authorizer needs.
type Repository interface {
	// GetInstanceRole returns the policy set for the user's instance role.
	GetInstanceRole(ctx context.Context, userID string) ([]PolicyStatement, error)

	// GetResourcePermission returns explicit resource-level allow/deny for the user.
	GetResourcePermission(ctx context.Context, userID, resourceType, resourceID string) (*ResourcePermission, error)

	// IsFeatureEnabled returns whether a top-level feature flag is set on the instance.
	IsFeatureEnabled(ctx context.Context, feature string) (bool, error)

	// IsOwner returns true if the user holds the instance-owner role.
	IsOwner(ctx context.Context, userID string) (bool, error)

	// GetCustomRolePermissionsForUser returns all custom-role permission rows relevant
	// to this user (direct + via groups, at all nesting depths) matching the action
	// or any scoped variant of it (e.g. "vault:*:edit", "vault:shortId:edit").
	GetCustomRolePermissionsForUser(ctx context.Context, userID, action, resourceType, resourceID string) ([]CustomRolePerm, error)

	// InvalidateUserCache removes all cached authz results for a user.
	InvalidateUserCache(ctx context.Context, userID string) error
}

// CustomRolePerm is a permission row returned by GetCustomRolePermissionsForUser.
type CustomRolePerm struct {
	Effect      string // "allow" | "allow_cascade" | "deny"
	Priority    *int   // nil = lowest precedence
	IsCascaded  bool   // true if inherited through group nesting (depth > 0)
}

// PolicyStatement is a single allow/deny rule from a policy.
type PolicyStatement struct {
	Effect        string   // "allow" | "deny"
	Actions       []string // e.g. ["page:edit", "page:read"]
	ResourceTypes []string // e.g. ["page"]
}

// ResourcePermission is an explicit allow/deny for a specific user+resource.
type ResourcePermission struct {
	Effect  string // "allow" | "deny"
	Actions []string
}

// DefaultAuthorizer implements the four-dimension evaluation algorithm.
type DefaultAuthorizer struct {
	repo  Repository
	cache *redis.Client
}

// NewDefaultAuthorizer constructs the default authorizer with optional Redis caching.
func NewDefaultAuthorizer(repo Repository, cache *redis.Client) *DefaultAuthorizer {
	return &DefaultAuthorizer{repo: repo, cache: cache}
}

// Check evaluates all permission dimensions in strict order.
//
// Evaluation order:
//  1. Owner fast-path — untouchable; no custom role can block the owner
//  2. Feature flag (instance-level)
//  3. Resource-level explicit deny
//  4. Resource-level explicit allow
//  5. Vault role policies
//  6. Custom role evaluation (direct + group inheritance + priority + cascade)
//  7. Instance role policies
//  8. Default → DENY
func (a *DefaultAuthorizer) Check(ctx context.Context, req CheckRequest) (CheckResult, error) {
	cacheKey := fmt.Sprintf("authz:%s:%s:%s:%s:%s:%s",
		req.UserID, req.VaultID, req.ResourceType, req.ResourceID, req.Action, req.VaultRole)

	// Try cache first.
	if a.cache != nil {
		if val, err := a.cache.Get(ctx, cacheKey).Result(); err == nil {
			var cached CheckResult
			if err := json.Unmarshal([]byte(val), &cached); err == nil {
				return cached, nil
			}
		}
	}

	// 1. Owner fast-path — cannot be blocked by any custom role deny.
	owner, err := a.repo.IsOwner(ctx, req.UserID)
	if err != nil {
		return CheckResult{}, fmt.Errorf("authz: owner check: %w", err)
	}
	if owner {
		return a.cacheAndReturn(ctx, cacheKey, CheckResult{Allowed: true})
	}

	// 2. Feature flag.
	featureKey := domainOf(req.Action)
	enabled, err := a.repo.IsFeatureEnabled(ctx, featureKey)
	if err != nil {
		return CheckResult{}, fmt.Errorf("authz: feature flag: %w", err)
	}
	if !enabled {
		return a.cacheAndReturn(ctx, cacheKey, CheckResult{Allowed: false, Reason: "feature_disabled"})
	}

	// 3 & 4. Resource-level explicit permission.
	rp, err := a.repo.GetResourcePermission(ctx, req.UserID, req.ResourceType, req.ResourceID)
	if err != nil {
		return CheckResult{}, fmt.Errorf("authz: resource permission: %w", err)
	}
	if rp != nil {
		if rp.Effect == "deny" && containsAction(rp.Actions, req.Action) {
			return a.cacheAndReturn(ctx, cacheKey, CheckResult{Allowed: false, Reason: "resource_explicit_deny"})
		}
		if rp.Effect == "allow" && containsAction(rp.Actions, req.Action) {
			return a.cacheAndReturn(ctx, cacheKey, CheckResult{Allowed: true})
		}
	}

	// 5. Vault role — derived from the VaultRole field sent by luma.
	if result, ok := evaluatePolicies(builtinVaultPolicies(req.VaultRole), req.Action, "vault_role"); ok {
		return a.cacheAndReturn(ctx, cacheKey, result)
	}

	// 6. Custom role evaluation.
	if result, ok, err := a.evaluateCustomRoles(ctx, req.UserID, req.Action, req.ResourceType, req.ResourceID); err != nil {
		return CheckResult{}, fmt.Errorf("authz: custom roles: %w", err)
	} else if ok {
		return a.cacheAndReturn(ctx, cacheKey, result)
	}

	// 7. Instance role.
	instancePolicies, err := a.repo.GetInstanceRole(ctx, req.UserID)
	if err != nil {
		return CheckResult{}, fmt.Errorf("authz: instance role: %w", err)
	}
	if result, ok := evaluatePolicies(instancePolicies, req.Action, "instance_role"); ok {
		return a.cacheAndReturn(ctx, cacheKey, result)
	}

	// 8. Default deny.
	return a.cacheAndReturn(ctx, cacheKey, CheckResult{Allowed: false, Reason: "default_deny"})
}

// priorityBucket groups custom role permissions by priority level.
type priorityBucket struct {
	priority *int
	perms    []CustomRolePerm
}

// evaluateCustomRoles applies priority-based, cascade-aware custom role evaluation.
//
// Rules:
//   - IsCascaded=true + Effect="allow" → dropped (non-cascading allow)
//   - IsCascaded=true + Effect="allow_cascade" or "deny" → kept
//   - Priority: lower number wins; nil = lowest; within same priority deny beats allow
func (a *DefaultAuthorizer) evaluateCustomRoles(ctx context.Context, userID, action, resourceType, resourceID string) (CheckResult, bool, error) {
	perms, err := a.repo.GetCustomRolePermissionsForUser(ctx, userID, action, resourceType, resourceID)
	if err != nil {
		return CheckResult{}, false, err
	}

	// Apply cascade filter: drop plain "allow" if inherited through group nesting.
	var filtered []CustomRolePerm
	for _, p := range perms {
		if p.IsCascaded && p.Effect == "allow" {
			continue
		}
		filtered = append(filtered, p)
	}
	if len(filtered) == 0 {
		return CheckResult{}, false, nil
	}

	// Group by priority. Process ascending priority (lower number first); nil last.
	seen := map[string]bool{}
	var buckets []priorityBucket

	for i := range filtered {
		key := priorityKey(filtered[i].Priority)
		if seen[key] {
			continue
		}
		seen[key] = true
		b := priorityBucket{priority: filtered[i].Priority}
		for j := range filtered {
			if priorityKey(filtered[j].Priority) == key {
				b.perms = append(b.perms, filtered[j])
			}
		}
		buckets = append(buckets, b)
	}

	// Sort buckets: non-nil ascending, then nil.
	for i := 1; i < len(buckets); i++ {
		for j := i; j > 0; j-- {
			if priorityBucketLess(buckets[j], buckets[j-1]) {
				buckets[j], buckets[j-1] = buckets[j-1], buckets[j]
			} else {
				break
			}
		}
	}

	for _, b := range buckets {
		hasDeny := false
		hasAllow := false
		for _, p := range b.perms {
			if p.Effect == "deny" {
				hasDeny = true
			} else {
				hasAllow = true
			}
		}
		if hasDeny {
			return CheckResult{Allowed: false, Reason: "custom_role_deny"}, true, nil
		}
		if hasAllow {
			return CheckResult{Allowed: true}, true, nil
		}
	}
	return CheckResult{}, false, nil
}

func priorityKey(p *int) string {
	if p == nil {
		return "nil"
	}
	return fmt.Sprintf("%d", *p)
}

func priorityBucketLess(a, b priorityBucket) bool {
	if a.priority == nil {
		return false // nil is largest (lowest priority)
	}
	if b.priority == nil {
		return true
	}
	return *a.priority < *b.priority
}

// cacheAndReturn stores the result in Redis (best-effort) and returns it.
func (a *DefaultAuthorizer) cacheAndReturn(ctx context.Context, key string, result CheckResult) (CheckResult, error) {
	if a.cache != nil {
		if b, err := json.Marshal(result); err == nil {
			if err := a.cache.Set(ctx, key, b, 5*time.Minute).Err(); err != nil {
				slog.Warn("authz: cache write failed", "key", key, "err", err)
			}
		}
	}
	return result, nil
}

// evaluatePolicies scans a list of policy statements for the action.
// Returns (result, true) if a matching statement was found, (zero, false) otherwise.
// Deny takes precedence over allow within the same policy set.
func evaluatePolicies(stmts []PolicyStatement, action, source string) (CheckResult, bool) {
	for _, s := range stmts {
		if !containsAction(s.Actions, action) {
			continue
		}
		if s.Effect == "deny" {
			return CheckResult{Allowed: false, Reason: source + "_deny"}, true
		}
	}
	for _, s := range stmts {
		if !containsAction(s.Actions, action) {
			continue
		}
		if s.Effect == "allow" {
			return CheckResult{Allowed: true}, true
		}
	}
	return CheckResult{}, false
}

func containsAction(actions []string, target string) bool {
	for _, a := range actions {
		if a == target {
			return true
		}
	}
	return false
}

// builtinVaultPolicies maps a built-in vault role string to its policy statements.
// Returns nil for an empty or unrecognised role (evaluation continues to next step).
func builtinVaultPolicies(roleID string) []PolicyStatement {
	allVault := []string{
		"vault:read", "vault:edit", "vault:archive",
		"vault:manage-members", "vault:manage-roles",
	}
	allContent := []string{
		"page:read", "page:create", "page:edit", "page:delete", "page:archive",
		"page:version", "page:restore-version", "page:share", "page:transclude",
		"task:read", "task:create", "task:edit", "task:delete", "task:assign",
		"task:close", "task:comment",
		"flow:read", "flow:create", "flow:edit", "flow:delete", "flow:publish",
		"flow:execute", "flow:comment",
	}
	switch roleID {
	case "builtin:vault-admin":
		actions := make([]string, 0, len(allVault)+len(allContent))
		actions = append(actions, allVault...)
		actions = append(actions, allContent...)
		return []PolicyStatement{{Effect: "allow", Actions: actions}}
	case "builtin:vault-editor":
		actions := make([]string, 0, 1+len(allContent))
		actions = append(actions, "vault:read")
		actions = append(actions, allContent...)
		return []PolicyStatement{{Effect: "allow", Actions: actions}}
	case "builtin:vault-viewer":
		return []PolicyStatement{{Effect: "allow", Actions: []string{
			"vault:read", "page:read", "task:read", "flow:read",
		}}}
	default:
		return nil
	}
}

// domainOf extracts the domain from "domain:action" (e.g. "page" from "page:edit").
func domainOf(action string) string {
	for i, c := range action {
		if c == ':' {
			return action[:i]
		}
	}
	return action
}
