package integration_test

import (
	"testing"
	"time"

	"github.com/josephtindall/luma-auth/internal/bootstrap"
	bootstrappg "github.com/josephtindall/luma-auth/internal/bootstrap/postgres"
)

func TestBootstrap_Get_ReturnsValidState(t *testing.T) {
	repo := bootstrappg.New(testDB)
	state, err := repo.Get(bg())
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	switch state.SetupState {
	case bootstrap.StateUnclaimed, bootstrap.StateSetup, bootstrap.StateActive:
		// valid
	default:
		t.Errorf("unexpected SetupState %q", state.SetupState)
	}
}

func TestBootstrap_EnsureRow_Idempotent(t *testing.T) {
	repo := bootstrappg.New(testDB)
	for i := 0; i < 3; i++ {
		if err := repo.EnsureRow(bg()); err != nil {
			t.Fatalf("EnsureRow call %d: %v", i+1, err)
		}
	}
	// Verify still exactly one row.
	var count int
	testDB.QueryRow(bg(), "SELECT COUNT(*) FROM haven.instance").Scan(&count) //nolint:errcheck
	if count != 1 {
		t.Errorf("row count = %d, want 1", count)
	}
}

func TestBootstrap_StoreSetupToken(t *testing.T) {
	repo := bootstrappg.New(testDB)
	resetInstanceToUnclaimed(t)
	t.Cleanup(func() { resetInstanceToUnclaimed(t) })

	hash := randHex(32)
	expires := time.Now().Add(30 * time.Minute).UTC().Truncate(time.Second)

	if err := repo.StoreSetupToken(bg(), hash, expires); err != nil {
		t.Fatalf("StoreSetupToken: %v", err)
	}

	state, err := repo.Get(bg())
	if err != nil {
		t.Fatalf("Get after StoreSetupToken: %v", err)
	}
	if state.SetupTokenHash == nil || *state.SetupTokenHash != hash {
		t.Errorf("SetupTokenHash = %v, want %q", state.SetupTokenHash, hash)
	}
	if state.SetupTokenFailures != 0 {
		t.Errorf("SetupTokenFailures = %d, want 0", state.SetupTokenFailures)
	}
}

func TestBootstrap_TransitionToSetup(t *testing.T) {
	repo := bootstrappg.New(testDB)
	resetInstanceToUnclaimed(t)
	t.Cleanup(func() { resetInstanceToUnclaimed(t) })

	expires := time.Now().Add(30 * time.Minute)
	if err := repo.TransitionToSetup(bg(), expires); err != nil {
		t.Fatalf("TransitionToSetup: %v", err)
	}

	state, _ := repo.Get(bg())
	if state.SetupState != bootstrap.StateSetup {
		t.Errorf("SetupState = %q, want setup", state.SetupState)
	}
}

func TestBootstrap_TransitionToSetup_WhenAlreadySetup_Fails(t *testing.T) {
	repo := bootstrappg.New(testDB)
	testDB.Exec(bg(), "UPDATE haven.instance SET setup_state = 'setup'") //nolint:errcheck
	t.Cleanup(func() { resetInstanceToUnclaimed(t) })

	err := repo.TransitionToSetup(bg(), time.Now().Add(30*time.Minute))
	if err == nil {
		t.Error("expected error when transitioning from non-unclaimed state")
	}
}

func TestBootstrap_IncrementTokenFailures(t *testing.T) {
	repo := bootstrappg.New(testDB)
	testDB.Exec(bg(), "UPDATE haven.instance SET setup_token_failures = 0") //nolint:errcheck
	t.Cleanup(func() { resetInstanceToUnclaimed(t) })

	count, err := repo.IncrementTokenFailures(bg())
	if err != nil {
		t.Fatalf("IncrementTokenFailures: %v", err)
	}
	if count != 1 {
		t.Errorf("count = %d, want 1", count)
	}

	count, _ = repo.IncrementTokenFailures(bg())
	if count != 2 {
		t.Errorf("second count = %d, want 2", count)
	}
}

func TestBootstrap_ResetToUnclaimed(t *testing.T) {
	repo := bootstrappg.New(testDB)
	// Put in SETUP state first.
	testDB.Exec(bg(), "UPDATE haven.instance SET setup_state = 'setup', setup_token_failures = 5") //nolint:errcheck
	t.Cleanup(func() { resetInstanceToUnclaimed(t) })

	newHash := randHex(32)
	newExpiry := time.Now().Add(30 * time.Minute)
	if err := repo.ResetToUnclaimed(bg(), newHash, newExpiry); err != nil {
		t.Fatalf("ResetToUnclaimed: %v", err)
	}

	state, _ := repo.Get(bg())
	if state.SetupState != bootstrap.StateUnclaimed {
		t.Errorf("SetupState = %q, want unclaimed", state.SetupState)
	}
	if state.SetupTokenFailures != 0 {
		t.Errorf("failures = %d, want 0", state.SetupTokenFailures)
	}
	if state.SetupTokenHash == nil || *state.SetupTokenHash != newHash {
		t.Errorf("SetupTokenHash mismatch")
	}
}

func TestBootstrap_ConfigureInstance(t *testing.T) {
	repo := bootstrappg.New(testDB)
	orig, _ := repo.Get(bg())
	t.Cleanup(func() {
		testDB.Exec(bg(), "UPDATE haven.instance SET name=$1, locale=$2, timezone=$3", //nolint:errcheck
			orig.Name, orig.Locale, orig.Timezone)
	})

	if err := repo.ConfigureInstance(bg(), "My Haven", "en-GB", "Europe/London"); err != nil {
		t.Fatalf("ConfigureInstance: %v", err)
	}

	state, _ := repo.Get(bg())
	if state.Name != "My Haven" {
		t.Errorf("Name = %q, want My Haven", state.Name)
	}
	if state.Locale != "en-GB" {
		t.Errorf("Locale = %q, want en-GB", state.Locale)
	}
	if state.Timezone != "Europe/London" {
		t.Errorf("Timezone = %q, want Europe/London", state.Timezone)
	}
}

func TestBootstrap_CreateOwnerAtomic(t *testing.T) {
	repo := bootstrappg.New(testDB)
	// Force SETUP state so the atomic operation can proceed.
	testDB.Exec(bg(), `UPDATE haven.instance SET setup_state = 'setup', setup_token_hash = 'testhash', setup_token_expires_at = NOW() + INTERVAL '30 minutes'`) //nolint:errcheck
	t.Cleanup(func() { resetInstanceToUnclaimed(t) })

	params := bootstrap.CreateOwnerParams{
		Email:        uniqueEmail(),
		DisplayName:  "Test Owner",
		PasswordHash: "$argon2id$stub",
		InstanceName: "Integration Test Haven",
		Locale:       "en-US",
		Timezone:     "UTC",
	}

	userID, err := repo.CreateOwnerAtomic(bg(), params)
	if err != nil {
		t.Fatalf("CreateOwnerAtomic: %v", err)
	}
	if userID == "" {
		t.Error("expected non-empty userID")
	}
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM haven.users WHERE id = $1::UUID", userID) //nolint:errcheck
	})

	// Instance must now be ACTIVE with token cleared.
	state, _ := repo.Get(bg())
	if state.SetupState != bootstrap.StateActive {
		t.Errorf("SetupState = %q, want active", state.SetupState)
	}
	if state.SetupTokenHash != nil {
		t.Error("expected setup_token_hash to be NULL after activation")
	}
	if state.ActivatedAt == nil {
		t.Error("expected activated_at to be set")
	}
}

func TestBootstrap_CreateOwnerAtomic_WhenNotSetup_Fails(t *testing.T) {
	repo := bootstrappg.New(testDB)
	resetInstanceToUnclaimed(t)
	t.Cleanup(func() { resetInstanceToUnclaimed(t) })

	_, err := repo.CreateOwnerAtomic(bg(), bootstrap.CreateOwnerParams{
		Email:        uniqueEmail(),
		DisplayName:  "X",
		PasswordHash: "hash",
	})
	if err == nil {
		t.Error("expected error when instance is not in SETUP state")
	}
}
