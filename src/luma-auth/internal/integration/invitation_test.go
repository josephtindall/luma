package integration_test

import (
	"errors"
	"testing"
	"time"

	"github.com/josephtindall/luma-auth/internal/invitation"
	invitationpg "github.com/josephtindall/luma-auth/internal/invitation/postgres"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/token"
)

func TestInvitation_Create_And_GetByHash(t *testing.T) {
	repo := invitationpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())

	raw, hash, _ := token.GenerateRefreshToken() // re-use token gen for a random hash
	_ = raw
	inv := &invitation.Invitation{
		InviterID: inviterID,
		Email:     "invitee@example.com",
		Note:      "Welcome!",
		TokenHash: hash,
		Status:    invitation.StatusPending,
		ExpiresAt: time.Now().Add(48 * time.Hour),
	}
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM haven.invitations WHERE token_hash = $1", hash) //nolint:errcheck
	})

	if err := repo.Create(bg(), inv); err != nil {
		t.Fatalf("Create: %v", err)
	}
	if inv.ID == "" {
		t.Error("expected ID to be populated after Create")
	}

	got, err := repo.GetByHash(bg(), hash)
	if err != nil {
		t.Fatalf("GetByHash: %v", err)
	}
	if got.InviterID != inviterID {
		t.Errorf("InviterID = %q, want %q", got.InviterID, inviterID)
	}
	if got.Status != invitation.StatusPending {
		t.Errorf("Status = %q, want pending", got.Status)
	}
	if !got.IsValid() {
		t.Error("new invitation must be valid")
	}
}

func TestInvitation_GetByHash_NotFound(t *testing.T) {
	repo := invitationpg.New(testDB)
	_, err := repo.GetByHash(bg(), randHex(32))
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid, got %v", err)
	}
}

func TestInvitation_GetByID(t *testing.T) {
	repo := invitationpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())
	invID, tokenHash := insertPendingInvitation(t, inviterID)
	_ = tokenHash

	got, err := repo.GetByID(bg(), invID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.ID != invID {
		t.Errorf("ID = %q, want %q", got.ID, invID)
	}
	if got.Status != invitation.StatusPending {
		t.Errorf("Status = %q, want pending", got.Status)
	}
}

func TestInvitation_GetByID_NotFound(t *testing.T) {
	repo := invitationpg.New(testDB)
	_, err := repo.GetByID(bg(), genUUID(t))
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid, got %v", err)
	}
}

func TestInvitation_List_ReturnsPendingOnly(t *testing.T) {
	repo := invitationpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())

	// Create two pending and one accepted invitation.
	insertPendingInvitation(t, inviterID)
	insertPendingInvitation(t, inviterID)
	invID3, _ := insertPendingInvitation(t, inviterID)
	testDB.Exec(bg(), "UPDATE haven.invitations SET status = 'accepted' WHERE id = $1::UUID", invID3) //nolint:errcheck

	all, err := repo.List(bg())
	if err != nil {
		t.Fatalf("List: %v", err)
	}

	for _, inv := range all {
		if inv.Status != invitation.StatusPending {
			t.Errorf("List returned non-pending invitation with status %q", inv.Status)
		}
	}
}

func TestInvitation_Accept(t *testing.T) {
	repo := invitationpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())
	invID, hash := insertPendingInvitation(t, inviterID)
	_ = hash

	if err := repo.Accept(bg(), invID); err != nil {
		t.Fatalf("Accept: %v", err)
	}

	got, err := repo.GetByID(bg(), invID)
	if err != nil {
		t.Fatalf("GetByID after Accept: %v", err)
	}
	if got.Status != invitation.StatusAccepted {
		t.Errorf("Status = %q, want accepted", got.Status)
	}
	if got.AcceptedAt == nil {
		t.Error("expected AcceptedAt to be set")
	}
}

func TestInvitation_Revoke(t *testing.T) {
	repo := invitationpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())
	invID, _ := insertPendingInvitation(t, inviterID)

	if err := repo.Revoke(bg(), invID); err != nil {
		t.Fatalf("Revoke: %v", err)
	}

	got, err := repo.GetByID(bg(), invID)
	if err != nil {
		t.Fatalf("GetByID after Revoke: %v", err)
	}
	if got.Status != invitation.StatusRevoked {
		t.Errorf("Status = %q, want revoked", got.Status)
	}
	if got.RevokedAt == nil {
		t.Error("expected RevokedAt to be set")
	}
	if got.IsValid() {
		t.Error("revoked invitation must not be valid")
	}
}

func TestInvitation_Expired_IsNotValid(t *testing.T) {
	repo := invitationpg.New(testDB)
	inviterID := insertUser(t, uniqueEmail())

	hash := randHex(32)
	var invID string
	testDB.QueryRow(bg(), `
		INSERT INTO haven.invitations (inviter_id, token_hash, status, expires_at)
		VALUES ($1::UUID, $2, 'pending', NOW() - INTERVAL '1 hour')
		RETURNING id::TEXT
	`, inviterID, hash).Scan(&invID) //nolint:errcheck
	t.Cleanup(func() {
		testDB.Exec(bg(), "DELETE FROM haven.invitations WHERE id = $1::UUID", invID) //nolint:errcheck
	})

	got, err := repo.GetByID(bg(), invID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.IsValid() {
		t.Error("past-expiry invitation must not be valid")
	}
}
