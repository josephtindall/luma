package integration_test

import (
	"testing"

	authzpg "github.com/josephtindall/luma-auth/internal/authz/postgres"
)

// TestAuthz_GetInstanceRole_Owner verifies that an owner user gets the
// owner-all policy statements seeded by migration 0003.
func TestAuthz_GetInstanceRole_Owner(t *testing.T) {
	repo := authzpg.New(testDB, nil)
	ownerID := insertOwnerUser(t, uniqueEmail())

	stmts, err := repo.GetInstanceRole(bg(), ownerID)
	if err != nil {
		t.Fatalf("GetInstanceRole: %v", err)
	}
	if len(stmts) == 0 {
		t.Fatal("expected at least one policy statement for instance-owner")
	}
	// The owner-all policy grants allow on all actions.
	for _, s := range stmts {
		if s.Effect != "allow" {
			t.Errorf("unexpected effect %q in owner policy", s.Effect)
		}
		if len(s.Actions) == 0 {
			t.Error("expected non-empty Actions in owner policy")
		}
	}
}

// TestAuthz_GetInstanceRole_Member verifies the member baseline policy.
func TestAuthz_GetInstanceRole_Member(t *testing.T) {
	repo := authzpg.New(testDB, nil)
	memberID := insertUser(t, uniqueEmail())

	stmts, err := repo.GetInstanceRole(bg(), memberID)
	if err != nil {
		t.Fatalf("GetInstanceRole: %v", err)
	}
	if len(stmts) == 0 {
		t.Fatal("expected policy statements for instance-member")
	}
	// member-base: allow audit:read-own, user:read, etc.
	found := false
	for _, s := range stmts {
		for _, action := range s.Actions {
			if action == "audit:read-own" {
				found = true
			}
		}
	}
	if !found {
		t.Error("expected audit:read-own in member policy")
	}
}

// TestAuthz_GetInstanceRole_NoUserID_ReturnsEmpty verifies that an unknown
// user ID produces an empty (not errored) result.
func TestAuthz_GetInstanceRole_NoUserID_ReturnsEmpty(t *testing.T) {
	repo := authzpg.New(testDB, nil)
	stmts, err := repo.GetInstanceRole(bg(), genUUID(t))
	if err != nil {
		t.Fatalf("GetInstanceRole: %v", err)
	}
	if len(stmts) != 0 {
		t.Errorf("expected 0 statements for unknown user, got %d", len(stmts))
	}
}

// TestAuthz_GetResourcePermission_NoRow_ReturnsNil verifies that when no
// resource permission exists the method returns nil, nil.
func TestAuthz_GetResourcePermission_NoRow_ReturnsNil(t *testing.T) {
	repo := authzpg.New(testDB, nil)
	rp, err := repo.GetResourcePermission(bg(), genUUID(t), "page", genUUID(t))
	if err != nil {
		t.Fatalf("GetResourcePermission: %v", err)
	}
	if rp != nil {
		t.Error("expected nil for absent resource permission")
	}
}

// TestAuthz_GetResourcePermission_ReturnsRow verifies retrieval of a seeded row.
func TestAuthz_GetResourcePermission_ReturnsRow(t *testing.T) {
	repo := authzpg.New(testDB, nil)
	userID := insertUser(t, uniqueEmail())
	grantedBy := insertOwnerUser(t, uniqueEmail())
	resourceID := "page-" + randHex(4)

	// Insert a resource permission directly.
	testDB.Exec(bg(), `
		INSERT INTO auth.resource_permissions
		    (resource_type, resource_id, subject_type, subject_id, effect, actions, granted_by)
		VALUES ('page', $1, 'user', $2, 'allow', ARRAY['page:edit','page:read'], $3::UUID)
	`, resourceID, userID, grantedBy) //nolint:errcheck
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM auth.resource_permissions WHERE resource_id = $1", resourceID) //nolint:errcheck
	})

	rp, err := repo.GetResourcePermission(bg(), userID, "page", resourceID)
	if err != nil {
		t.Fatalf("GetResourcePermission: %v", err)
	}
	if rp == nil {
		t.Fatal("expected non-nil ResourcePermission")
	}
	if rp.Effect != "allow" {
		t.Errorf("Effect = %q, want allow", rp.Effect)
	}
	if len(rp.Actions) != 2 {
		t.Errorf("Actions count = %d, want 2", len(rp.Actions))
	}
}

// TestAuthz_GetResourcePermission_Expired_ReturnsNil verifies that an expired
// permission is not returned.
func TestAuthz_GetResourcePermission_Expired_ReturnsNil(t *testing.T) {
	repo := authzpg.New(testDB, nil)
	userID := insertUser(t, uniqueEmail())
	grantedBy := insertOwnerUser(t, uniqueEmail())
	resourceID := "page-" + randHex(4)

	testDB.Exec(bg(), `
		INSERT INTO auth.resource_permissions
		    (resource_type, resource_id, subject_type, subject_id, effect, actions, granted_by, expires_at)
		VALUES ('page', $1, 'user', $2, 'allow', ARRAY['page:edit'], $3::UUID, NOW() - INTERVAL '1 hour')
	`, resourceID, userID, grantedBy) //nolint:errcheck
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM auth.resource_permissions WHERE resource_id = $1", resourceID) //nolint:errcheck
	})

	rp, err := repo.GetResourcePermission(bg(), userID, "page", resourceID)
	if err != nil {
		t.Fatalf("GetResourcePermission: %v", err)
	}
	if rp != nil {
		t.Error("expected nil for expired resource permission")
	}
}

// TestAuthz_IsFeatureEnabled_AbsentKey_ReturnsTrue verifies the COALESCE default.
func TestAuthz_IsFeatureEnabled_AbsentKey_ReturnsTrue(t *testing.T) {
	repo := authzpg.New(testDB, nil)
	enabled, err := repo.IsFeatureEnabled(bg(), "nonexistent_feature_xyz")
	if err != nil {
		t.Fatalf("IsFeatureEnabled: %v", err)
	}
	if !enabled {
		t.Error("absent feature key must default to enabled")
	}
}

// TestAuthz_IsFeatureEnabled_ExplicitFalse verifies a disabled feature.
func TestAuthz_IsFeatureEnabled_ExplicitFalse(t *testing.T) {
	repo := authzpg.New(testDB, nil)

	// Write a disabled feature directly to the instance row.
	testDB.Exec(bg(), `UPDATE auth.instance SET features = features || '{"test_flag": false}'::jsonb`) //nolint:errcheck
	t.Cleanup(func() {
		testDB.Exec(bg(), `UPDATE auth.instance SET features = features - 'test_flag'`) //nolint:errcheck
	})

	enabled, err := repo.IsFeatureEnabled(bg(), "test_flag")
	if err != nil {
		t.Fatalf("IsFeatureEnabled: %v", err)
	}
	if enabled {
		t.Error("expected feature to be disabled")
	}
}

// TestAuthz_IsFeatureEnabled_ExplicitTrue verifies an explicitly enabled feature.
func TestAuthz_IsFeatureEnabled_ExplicitTrue(t *testing.T) {
	repo := authzpg.New(testDB, nil)

	testDB.Exec(bg(), `UPDATE auth.instance SET features = features || '{"test_flag2": true}'::jsonb`) //nolint:errcheck
	t.Cleanup(func() {
		testDB.Exec(bg(), `UPDATE auth.instance SET features = features - 'test_flag2'`) //nolint:errcheck
	})

	enabled, err := repo.IsFeatureEnabled(bg(), "test_flag2")
	if err != nil {
		t.Fatalf("IsFeatureEnabled: %v", err)
	}
	if !enabled {
		t.Error("expected explicitly true feature to be enabled")
	}
}
