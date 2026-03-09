package authz

import (
	"context"
	"testing"
)

// mockAuthzRepo is a configurable test double for authz.Repository.
type mockAuthzRepo struct {
	instancePolicies []PolicyStatement
	vaultPolicies    []PolicyStatement
	resourcePerm     *ResourcePermission
	featureEnabled   bool
}

func (m *mockAuthzRepo) GetInstanceRole(_ context.Context, _ string) ([]PolicyStatement, error) {
	return m.instancePolicies, nil
}
func (m *mockAuthzRepo) GetVaultRole(_ context.Context, _, _ string) ([]PolicyStatement, error) {
	return m.vaultPolicies, nil
}
func (m *mockAuthzRepo) GetResourcePermission(_ context.Context, _, _, _ string) (*ResourcePermission, error) {
	return m.resourcePerm, nil
}
func (m *mockAuthzRepo) IsFeatureEnabled(_ context.Context, _ string) (bool, error) {
	return m.featureEnabled, nil
}
func (m *mockAuthzRepo) IsOwner(_ context.Context, _ string) (bool, error) {
	return false, nil
}
func (m *mockAuthzRepo) GetCustomRolePermissionsForUser(_ context.Context, _, _ string) ([]CustomRolePerm, error) {
	return nil, nil
}
func (m *mockAuthzRepo) InvalidateUserCache(_ context.Context, _ string) error {
	return nil
}

func newTestAuthorizer(repo Repository) *DefaultAuthorizer {
	return NewDefaultAuthorizer(repo, nil) // nil Redis — caching skipped in tests
}

func pageEditReq() CheckRequest {
	return CheckRequest{
		UserID: "user-1", Action: "page:edit",
		ResourceType: "page", ResourceID: "page-1",
	}
}

func TestCheck_FeatureDisabled_Denied(t *testing.T) {
	a := newTestAuthorizer(&mockAuthzRepo{featureEnabled: false})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if result.Allowed {
		t.Error("expected denied when feature is disabled")
	}
	if result.Reason != "feature_disabled" {
		t.Errorf("Reason = %q, want feature_disabled", result.Reason)
	}
}

func TestCheck_NoPolicies_DefaultDeny(t *testing.T) {
	a := newTestAuthorizer(&mockAuthzRepo{featureEnabled: true})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if result.Allowed {
		t.Error("expected default deny with no policies")
	}
	if result.Reason != "default_deny" {
		t.Errorf("Reason = %q, want default_deny", result.Reason)
	}
}

func TestCheck_InstanceRoleAllow(t *testing.T) {
	a := newTestAuthorizer(&mockAuthzRepo{
		featureEnabled: true,
		instancePolicies: []PolicyStatement{
			{Effect: "allow", Actions: []string{"page:edit"}, ResourceTypes: []string{"page"}},
		},
	})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if !result.Allowed {
		t.Errorf("expected allowed via instance role, reason=%q", result.Reason)
	}
}

func TestCheck_InstanceRoleDeny(t *testing.T) {
	a := newTestAuthorizer(&mockAuthzRepo{
		featureEnabled: true,
		instancePolicies: []PolicyStatement{
			{Effect: "deny", Actions: []string{"page:edit"}, ResourceTypes: []string{"page"}},
		},
	})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if result.Allowed {
		t.Error("expected deny via instance role")
	}
	if result.Reason != "instance_role_deny" {
		t.Errorf("Reason = %q, want instance_role_deny", result.Reason)
	}
}

func TestCheck_ResourceExplicitDeny_WinsOverInstanceAllow(t *testing.T) {
	a := newTestAuthorizer(&mockAuthzRepo{
		featureEnabled: true,
		resourcePerm:   &ResourcePermission{Effect: "deny", Actions: []string{"page:edit"}},
		instancePolicies: []PolicyStatement{
			{Effect: "allow", Actions: []string{"page:edit"}},
		},
	})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if result.Allowed {
		t.Error("expected resource-level deny to override instance allow")
	}
	if result.Reason != "resource_explicit_deny" {
		t.Errorf("Reason = %q, want resource_explicit_deny", result.Reason)
	}
}

func TestCheck_ResourceExplicitAllow(t *testing.T) {
	a := newTestAuthorizer(&mockAuthzRepo{
		featureEnabled: true,
		resourcePerm:   &ResourcePermission{Effect: "allow", Actions: []string{"page:edit"}},
	})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if !result.Allowed {
		t.Errorf("expected resource-level allow, reason=%q", result.Reason)
	}
}

func TestCheck_VaultRoleAllow_BeforeInstanceRole(t *testing.T) {
	a := newTestAuthorizer(&mockAuthzRepo{
		featureEnabled: true,
		vaultPolicies: []PolicyStatement{
			{Effect: "allow", Actions: []string{"page:edit"}},
		},
	})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if !result.Allowed {
		t.Errorf("expected vault role allow, reason=%q", result.Reason)
	}
}

func TestCheck_VaultDeny_WinsOverInstanceAllow(t *testing.T) {
	a := newTestAuthorizer(&mockAuthzRepo{
		featureEnabled: true,
		vaultPolicies: []PolicyStatement{
			{Effect: "deny", Actions: []string{"page:edit"}},
		},
		instancePolicies: []PolicyStatement{
			{Effect: "allow", Actions: []string{"page:edit"}},
		},
	})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if result.Allowed {
		t.Error("expected vault deny to override instance allow")
	}
}

func TestCheck_DenyWinsOverAllowInSamePolicySet(t *testing.T) {
	// Both deny and allow present for same action — deny must win.
	stmts := []PolicyStatement{
		{Effect: "allow", Actions: []string{"page:edit"}},
		{Effect: "deny", Actions: []string{"page:edit"}},
	}
	a := newTestAuthorizer(&mockAuthzRepo{featureEnabled: true, instancePolicies: stmts})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if result.Allowed {
		t.Error("deny must win over allow in the same policy set")
	}
}

func TestCheck_UnlistedAction_DefaultDeny(t *testing.T) {
	// Policy allows page:read, but we request page:delete.
	a := newTestAuthorizer(&mockAuthzRepo{
		featureEnabled: true,
		instancePolicies: []PolicyStatement{
			{Effect: "allow", Actions: []string{"page:read"}},
		},
	})
	req := pageEditReq()
	req.Action = "page:delete"
	result, err := a.Check(context.Background(), req)
	if err != nil {
		t.Fatal(err)
	}
	if result.Allowed {
		t.Error("expected default deny for unlisted action")
	}
}

func TestCheck_ResourceDenyForDifferentAction_DoesNotBlock(t *testing.T) {
	// Resource permission denies page:delete, but we're asking for page:edit.
	a := newTestAuthorizer(&mockAuthzRepo{
		featureEnabled: true,
		resourcePerm:   &ResourcePermission{Effect: "deny", Actions: []string{"page:delete"}},
		instancePolicies: []PolicyStatement{
			{Effect: "allow", Actions: []string{"page:edit"}},
		},
	})
	result, err := a.Check(context.Background(), pageEditReq())
	if err != nil {
		t.Fatal(err)
	}
	if !result.Allowed {
		t.Errorf("resource deny for different action should not block page:edit, reason=%q", result.Reason)
	}
}
