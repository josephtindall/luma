package integration_test

import (
	"errors"
	"testing"

	"github.com/josephtindall/luma-auth/internal/user"
	userpg "github.com/josephtindall/luma-auth/internal/user/postgres"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

func TestUser_Create_And_GetByID(t *testing.T) {
	repo := userpg.New(testDB)
	id := genUUID(t)
	email := uniqueEmail()

	u := &user.User{
		ID:             id,
		Email:          email,
		DisplayName:    "Alice",
		PasswordHash:   "$argon2id$stub",
		InstanceRoleID: "builtin:instance-member",
	}
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM auth.users WHERE id = $1::UUID", id) //nolint:errcheck
	})

	if err := repo.Create(bg(), u); err != nil {
		t.Fatalf("Create: %v", err)
	}

	got, err := repo.GetByID(bg(), id)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.Email != email {
		t.Errorf("Email = %q, want %q", got.Email, email)
	}
	if got.DisplayName != "Alice" {
		t.Errorf("DisplayName = %q, want Alice", got.DisplayName)
	}
	if got.InstanceRoleID != "builtin:instance-member" {
		t.Errorf("InstanceRoleID = %q", got.InstanceRoleID)
	}
}

func TestUser_GetByID_NotFound(t *testing.T) {
	repo := userpg.New(testDB)
	_, err := repo.GetByID(bg(), genUUID(t))
	if !errors.Is(err, pkgerrors.ErrUserNotFound) {
		t.Errorf("expected ErrUserNotFound, got %v", err)
	}
}

func TestUser_GetByEmail(t *testing.T) {
	repo := userpg.New(testDB)
	email := uniqueEmail()
	id := insertUser(t, email)

	got, err := repo.GetByEmail(bg(), email)
	if err != nil {
		t.Fatalf("GetByEmail: %v", err)
	}
	if got.ID != id {
		t.Errorf("ID = %q, want %q", got.ID, id)
	}
}

func TestUser_GetByEmail_NotFound(t *testing.T) {
	repo := userpg.New(testDB)
	_, err := repo.GetByEmail(bg(), "nobody@test.invalid")
	if !errors.Is(err, pkgerrors.ErrUserNotFound) {
		t.Errorf("expected ErrUserNotFound, got %v", err)
	}
}

func TestUser_Create_DuplicateEmail_ErrEmailTaken(t *testing.T) {
	email := uniqueEmail()
	insertUser(t, email) // first row

	repo := userpg.New(testDB)
	id2 := genUUID(t)
	err := repo.Create(bg(), &user.User{
		ID:             id2,
		Email:          email,
		DisplayName:    "Duplicate",
		PasswordHash:   "hash",
		InstanceRoleID: "builtin:instance-member",
	})
	if !errors.Is(err, pkgerrors.ErrEmailTaken) {
		t.Errorf("expected ErrEmailTaken, got %v", err)
	}
}

func TestUser_UpdateProfile_DisplayName(t *testing.T) {
	repo := userpg.New(testDB)
	id := insertUser(t, uniqueEmail())

	if err := repo.UpdateProfile(bg(), id, user.UpdateProfileParams{DisplayName: "Updated"}); err != nil {
		t.Fatalf("UpdateProfile: %v", err)
	}

	got, _ := repo.GetByID(bg(), id)
	if got.DisplayName != "Updated" {
		t.Errorf("DisplayName = %q, want Updated", got.DisplayName)
	}
}

func TestUser_UpdatePassword(t *testing.T) {
	repo := userpg.New(testDB)
	id := insertUser(t, uniqueEmail())
	newHash := "$argon2id$new-hash"

	if err := repo.UpdatePassword(bg(), id, newHash); err != nil {
		t.Fatalf("UpdatePassword: %v", err)
	}

	got, _ := repo.GetByID(bg(), id)
	if got.PasswordHash != newHash {
		t.Errorf("PasswordHash = %q, want %q", got.PasswordHash, newHash)
	}
}

func TestUser_IncrementFailedLogins(t *testing.T) {
	repo := userpg.New(testDB)
	id := insertUser(t, uniqueEmail())

	c1, err := repo.IncrementFailedLogins(bg(), id)
	if err != nil {
		t.Fatalf("IncrementFailedLogins: %v", err)
	}
	if c1 != 1 {
		t.Errorf("count = %d, want 1", c1)
	}

	c2, _ := repo.IncrementFailedLogins(bg(), id)
	if c2 != 2 {
		t.Errorf("count = %d, want 2", c2)
	}
}

func TestUser_ResetFailedLogins(t *testing.T) {
	repo := userpg.New(testDB)
	id := insertUser(t, uniqueEmail())

	repo.IncrementFailedLogins(bg(), id) //nolint:errcheck
	repo.IncrementFailedLogins(bg(), id) //nolint:errcheck

	if err := repo.ResetFailedLogins(bg(), id); err != nil {
		t.Fatalf("ResetFailedLogins: %v", err)
	}

	got, _ := repo.GetByID(bg(), id)
	if got.FailedLoginAttempts != 0 {
		t.Errorf("FailedLoginAttempts = %d, want 0", got.FailedLoginAttempts)
	}
}

func TestUser_LockAccount(t *testing.T) {
	repo := userpg.New(testDB)
	id := insertUser(t, uniqueEmail())

	if err := repo.LockAccount(bg(), id, "brute_force"); err != nil {
		t.Fatalf("LockAccount: %v", err)
	}

	got, _ := repo.GetByID(bg(), id)
	if got.LockedAt == nil {
		t.Error("expected LockedAt to be set")
	}
	if got.LockedReason != "brute_force" {
		t.Errorf("LockedReason = %q, want brute_force", got.LockedReason)
	}
}

func TestUser_UnlockAccount(t *testing.T) {
	repo := userpg.New(testDB)
	id := insertUser(t, uniqueEmail())

	repo.LockAccount(bg(), id, "brute_force") //nolint:errcheck
	repo.IncrementFailedLogins(bg(), id)      //nolint:errcheck

	if err := repo.UnlockAccount(bg(), id); err != nil {
		t.Fatalf("UnlockAccount: %v", err)
	}

	got, _ := repo.GetByID(bg(), id)
	if got.LockedAt != nil {
		t.Error("expected LockedAt to be nil after unlock")
	}
	if got.LockedReason != "" {
		t.Errorf("LockedReason = %q, want empty", got.LockedReason)
	}
	if got.FailedLoginAttempts != 0 {
		t.Errorf("FailedLoginAttempts = %d, want 0", got.FailedLoginAttempts)
	}
}

func TestUser_RegisterAtomic_CreatesUserAndAcceptsInvitation(t *testing.T) {
	repo := userpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())
	invID, _ := insertPendingInvitation(t, inviterID)
	email := uniqueEmail()

	userID, err := repo.RegisterAtomic(bg(), user.RegisterParams{
		Email:        email,
		DisplayName:  "New Member",
		PasswordHash: "$argon2id$stub",
		InvitationID: invID,
	})
	if err != nil {
		t.Fatalf("RegisterAtomic: %v", err)
	}
	if userID == "" {
		t.Error("expected non-empty userID")
	}
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM auth.users WHERE id = $1::UUID", userID) //nolint:errcheck
	})

	// User must be retrievable.
	got, err := repo.GetByID(bg(), userID)
	if err != nil {
		t.Fatalf("GetByID after RegisterAtomic: %v", err)
	}
	if got.Email != email {
		t.Errorf("Email = %q, want %q", got.Email, email)
	}
	if got.InstanceRoleID != "builtin:instance-member" {
		t.Errorf("InstanceRoleID = %q", got.InstanceRoleID)
	}

	// Invitation must be marked accepted.
	var status string
	testDB.QueryRow(bg(), "SELECT status FROM auth.invitations WHERE id = $1::UUID", invID).Scan(&status) //nolint:errcheck
	if status != "accepted" {
		t.Errorf("invitation status = %q, want accepted", status)
	}

	// user_preferences row must exist.
	var prefCount int
	testDB.QueryRow(bg(), "SELECT COUNT(*) FROM auth.user_preferences WHERE user_id = $1::UUID", userID).Scan(&prefCount) //nolint:errcheck
	if prefCount != 1 {
		t.Errorf("user_preferences count = %d, want 1", prefCount)
	}
}

func TestUser_RegisterAtomic_AlreadyAcceptedInvitation_ErrTokenInvalid(t *testing.T) {
	repo := userpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())
	invID, _ := insertPendingInvitation(t, inviterID)

	// Pre-accept the invitation.
	testDB.Exec(bg(), "UPDATE auth.invitations SET status = 'accepted' WHERE id = $1::UUID", invID) //nolint:errcheck

	_, err := repo.RegisterAtomic(bg(), user.RegisterParams{
		Email:        uniqueEmail(),
		DisplayName:  "Bob",
		PasswordHash: "hash",
		InvitationID: invID,
	})
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid, got %v", err)
	}
}

func TestUser_RegisterAtomic_DuplicateEmail_ErrEmailTaken(t *testing.T) {
	repo := userpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())
	email := uniqueEmail()
	insertUser(t, email) // email already taken

	invID, _ := insertPendingInvitation(t, inviterID)

	_, err := repo.RegisterAtomic(bg(), user.RegisterParams{
		Email:        email,
		DisplayName:  "Dup",
		PasswordHash: "hash",
		InvitationID: invID,
	})
	if !errors.Is(err, pkgerrors.ErrEmailTaken) {
		t.Errorf("expected ErrEmailTaken, got %v", err)
	}
}
