package integration_test

import (
	"errors"
	"testing"
	"time"

	"github.com/josephtindall/luma-auth/internal/device"
	devicepg "github.com/josephtindall/luma-auth/internal/device/postgres"
	"github.com/josephtindall/luma-auth/internal/session"
	sessionpg "github.com/josephtindall/luma-auth/internal/session/postgres"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/token"
)

// setupSessionFixture creates a user + device and returns both IDs.
func setupSessionFixture(t *testing.T) (userID, deviceID string) {
	t.Helper()
	userID = insertUser(t, uniqueEmail())
	deviceID = insertDevice(t, userID, randHex(16))
	return userID, deviceID
}

func TestSession_Create_And_GetByHash(t *testing.T) {
	repo := sessionpg.New(testDB)
	_, deviceID := setupSessionFixture(t)

	raw, hash, err := token.GenerateRefreshToken()
	if err != nil {
		t.Fatalf("GenerateRefreshToken: %v", err)
	}
	_ = raw

	tok := &session.RefreshToken{
		DeviceID:  deviceID,
		TokenHash: hash,
		ExpiresAt: time.Now().Add(30 * 24 * time.Hour),
	}
	if err := repo.Create(bg(), tok); err != nil {
		t.Fatalf("Create: %v", err)
	}
	if tok.ID == "" {
		t.Error("expected token ID to be populated after Create")
	}

	got, err := repo.GetByHash(bg(), hash)
	if err != nil {
		t.Fatalf("GetByHash: %v", err)
	}
	if got.DeviceID != deviceID {
		t.Errorf("DeviceID = %q, want %q", got.DeviceID, deviceID)
	}
	if got.ConsumedAt != nil {
		t.Error("new token must not be consumed")
	}
	if got.RevokedAt != nil {
		t.Error("new token must not be revoked")
	}
}

func TestSession_GetByHash_NotFound(t *testing.T) {
	repo := sessionpg.New(testDB)
	_, err := repo.GetByHash(bg(), "deadbeef"+randHex(28))
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid, got %v", err)
	}
}

func TestSession_Consume(t *testing.T) {
	repo := sessionpg.New(testDB)
	_, deviceID := setupSessionFixture(t)

	_, hash, _ := token.GenerateRefreshToken()
	tok := &session.RefreshToken{DeviceID: deviceID, TokenHash: hash, ExpiresAt: time.Now().Add(time.Hour)}
	repo.Create(bg(), tok) //nolint:errcheck

	if err := repo.Consume(bg(), tok.ID); err != nil {
		t.Fatalf("Consume: %v", err)
	}

	got, _ := repo.GetByHash(bg(), hash)
	if got.ConsumedAt == nil {
		t.Error("expected ConsumedAt to be set after Consume")
	}
}

func TestSession_Consume_AlreadyConsumed_ReturnsError(t *testing.T) {
	repo := sessionpg.New(testDB)
	_, deviceID := setupSessionFixture(t)

	_, hash, _ := token.GenerateRefreshToken()
	tok := &session.RefreshToken{DeviceID: deviceID, TokenHash: hash, ExpiresAt: time.Now().Add(time.Hour)}
	repo.Create(bg(), tok)     //nolint:errcheck
	repo.Consume(bg(), tok.ID) //nolint:errcheck

	// Second Consume must fail — the token was already consumed.
	err := repo.Consume(bg(), tok.ID)
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid on double-consume, got %v", err)
	}
}

func TestSession_Consume_RevokedToken_ReturnsError(t *testing.T) {
	repo := sessionpg.New(testDB)
	_, deviceID := setupSessionFixture(t)

	_, hash, _ := token.GenerateRefreshToken()
	tok := &session.RefreshToken{DeviceID: deviceID, TokenHash: hash, ExpiresAt: time.Now().Add(time.Hour)}
	repo.Create(bg(), tok) //nolint:errcheck

	// Revoke the token first.
	testDB.Exec(bg(), "UPDATE haven.refresh_tokens SET revoked_at = NOW() WHERE id = $1::UUID", tok.ID) //nolint:errcheck

	err := repo.Consume(bg(), tok.ID)
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid for revoked token, got %v", err)
	}
}

func TestSession_RevokeAllForUser(t *testing.T) {
	repo := sessionpg.New(testDB)
	devRepo := devicepg.New(testDB)
	userID := insertUser(t, uniqueEmail())

	// Create two devices, each with a token.
	d1, _ := devRepo.Create(bg(), device.RegisterParams{UserID: userID, Name: "D1", Platform: device.PlatformWeb, Fingerprint: randHex(16)})
	d2, _ := devRepo.Create(bg(), device.RegisterParams{UserID: userID, Name: "D2", Platform: device.PlatformIOS, Fingerprint: randHex(16)})

	_, h1, _ := token.GenerateRefreshToken()
	_, h2, _ := token.GenerateRefreshToken()
	t1 := &session.RefreshToken{DeviceID: d1.ID, TokenHash: h1, ExpiresAt: time.Now().Add(time.Hour)}
	t2 := &session.RefreshToken{DeviceID: d2.ID, TokenHash: h2, ExpiresAt: time.Now().Add(time.Hour)}
	repo.Create(bg(), t1) //nolint:errcheck
	repo.Create(bg(), t2) //nolint:errcheck

	if err := repo.RevokeAllForUser(bg(), userID); err != nil {
		t.Fatalf("RevokeAllForUser: %v", err)
	}

	// Both tokens must now be revoked.
	got1, _ := repo.GetByHash(bg(), h1)
	got2, _ := repo.GetByHash(bg(), h2)
	if got1.RevokedAt == nil {
		t.Error("token 1 not revoked")
	}
	if got2.RevokedAt == nil {
		t.Error("token 2 not revoked")
	}
}

func TestSession_RevokeAllForDevice(t *testing.T) {
	repo := sessionpg.New(testDB)
	_, deviceID := setupSessionFixture(t)

	_, h1, _ := token.GenerateRefreshToken()
	_, h2, _ := token.GenerateRefreshToken()
	t1 := &session.RefreshToken{DeviceID: deviceID, TokenHash: h1, ExpiresAt: time.Now().Add(time.Hour)}
	t2 := &session.RefreshToken{DeviceID: deviceID, TokenHash: h2, ExpiresAt: time.Now().Add(time.Hour)}
	repo.Create(bg(), t1) //nolint:errcheck
	repo.Create(bg(), t2) //nolint:errcheck

	if err := repo.RevokeAllForDevice(bg(), deviceID); err != nil {
		t.Fatalf("RevokeAllForDevice: %v", err)
	}

	got1, _ := repo.GetByHash(bg(), h1)
	got2, _ := repo.GetByHash(bg(), h2)
	if got1.RevokedAt == nil {
		t.Error("token 1 not revoked")
	}
	if got2.RevokedAt == nil {
		t.Error("token 2 not revoked")
	}
}

func TestSession_RevokeAllForUser_DoesNotAffectOtherUsers(t *testing.T) {
	repo := sessionpg.New(testDB)

	// User A with a token.
	userA := insertUser(t, uniqueEmail())
	devA := insertDevice(t, userA, randHex(16))
	_, hashA, _ := token.GenerateRefreshToken()
	tokA := &session.RefreshToken{DeviceID: devA, TokenHash: hashA, ExpiresAt: time.Now().Add(time.Hour)}
	repo.Create(bg(), tokA) //nolint:errcheck

	// User B with a token.
	userB := insertUser(t, uniqueEmail())
	devB := insertDevice(t, userB, randHex(16))
	_, hashB, _ := token.GenerateRefreshToken()
	tokB := &session.RefreshToken{DeviceID: devB, TokenHash: hashB, ExpiresAt: time.Now().Add(time.Hour)}
	repo.Create(bg(), tokB) //nolint:errcheck

	// Revoke only user A's sessions.
	repo.RevokeAllForUser(bg(), userA) //nolint:errcheck

	// User B's token must still be valid.
	gotB, _ := repo.GetByHash(bg(), hashB)
	if gotB.RevokedAt != nil {
		t.Error("user B's token was incorrectly revoked")
	}
}
