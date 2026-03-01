package integration_test

import (
	"testing"

	"github.com/josephtindall/luma-auth/internal/device"
	devicepg "github.com/josephtindall/luma-auth/internal/device/postgres"
)

func TestDevice_Create_And_GetByID(t *testing.T) {
	repo := devicepg.New(testDB)
	userID := insertUser(t, uniqueEmail())

	params := device.RegisterParams{
		UserID:      userID,
		Name:        "Chrome on macOS",
		Platform:    device.PlatformWeb,
		Fingerprint: randHex(16),
		UserAgent:   "Mozilla/5.0",
	}

	d, err := repo.Create(bg(), params)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if d.ID == "" {
		t.Error("expected non-empty device ID")
	}

	got, err := repo.GetByID(bg(), d.ID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if got.UserID != userID {
		t.Errorf("UserID = %q, want %q", got.UserID, userID)
	}
	if got.Name != "Chrome on macOS" {
		t.Errorf("Name = %q, want Chrome on macOS", got.Name)
	}
	if got.Platform != device.PlatformWeb {
		t.Errorf("Platform = %q, want web", got.Platform)
	}
}

func TestDevice_GetByID_NotFound(t *testing.T) {
	repo := devicepg.New(testDB)
	_, err := repo.GetByID(bg(), genUUID(t))
	if err == nil {
		t.Error("expected error for missing device")
	}
}

func TestDevice_GetByFingerprint_Found(t *testing.T) {
	repo := devicepg.New(testDB)
	userID := insertUser(t, uniqueEmail())
	fp := randHex(16)
	d, _ := repo.Create(bg(), device.RegisterParams{
		UserID:      userID,
		Name:        "Safari",
		Platform:    device.PlatformIOS,
		Fingerprint: fp,
	})

	got, err := repo.GetByFingerprint(bg(), userID, fp)
	if err != nil {
		t.Fatalf("GetByFingerprint: %v", err)
	}
	if got == nil {
		t.Fatal("expected non-nil device")
	}
	if got.ID != d.ID {
		t.Errorf("ID = %q, want %q", got.ID, d.ID)
	}
}

func TestDevice_GetByFingerprint_NotFound_ReturnsNil(t *testing.T) {
	repo := devicepg.New(testDB)
	userID := insertUser(t, uniqueEmail())

	got, err := repo.GetByFingerprint(bg(), userID, "no-such-fingerprint")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != nil {
		t.Error("expected nil for missing fingerprint")
	}
}

func TestDevice_ListForUser(t *testing.T) {
	repo := devicepg.New(testDB)
	userID := insertUser(t, uniqueEmail())

	repo.Create(bg(), device.RegisterParams{UserID: userID, Name: "D1", Platform: device.PlatformWeb, Fingerprint: randHex(16)})     //nolint:errcheck
	repo.Create(bg(), device.RegisterParams{UserID: userID, Name: "D2", Platform: device.PlatformIOS, Fingerprint: randHex(16)})     //nolint:errcheck
	repo.Create(bg(), device.RegisterParams{UserID: userID, Name: "D3", Platform: device.PlatformAndroid, Fingerprint: randHex(16)}) //nolint:errcheck

	devices, err := repo.ListForUser(bg(), userID)
	if err != nil {
		t.Fatalf("ListForUser: %v", err)
	}
	if len(devices) != 3 {
		t.Errorf("count = %d, want 3", len(devices))
	}
}

func TestDevice_ListForUser_ExcludesRevoked(t *testing.T) {
	repo := devicepg.New(testDB)
	userID := insertUser(t, uniqueEmail())

	d1, _ := repo.Create(bg(), device.RegisterParams{UserID: userID, Name: "Active", Platform: device.PlatformWeb, Fingerprint: randHex(16)})
	d2, _ := repo.Create(bg(), device.RegisterParams{UserID: userID, Name: "Revoked", Platform: device.PlatformWeb, Fingerprint: randHex(16)})

	repo.Revoke(bg(), d2.ID) //nolint:errcheck

	devices, err := repo.ListForUser(bg(), userID)
	if err != nil {
		t.Fatalf("ListForUser: %v", err)
	}
	if len(devices) != 1 {
		t.Errorf("count = %d, want 1 (revoked excluded)", len(devices))
	}
	if devices[0].ID != d1.ID {
		t.Errorf("wrong device returned: %q", devices[0].ID)
	}
}

func TestDevice_UpdateLastSeen(t *testing.T) {
	repo := devicepg.New(testDB)
	userID := insertUser(t, uniqueEmail())
	d, _ := repo.Create(bg(), device.RegisterParams{
		UserID: userID, Name: "X", Platform: device.PlatformWeb, Fingerprint: randHex(16),
	})

	if err := repo.UpdateLastSeen(bg(), d.ID); err != nil {
		t.Fatalf("UpdateLastSeen: %v", err)
	}

	got, _ := repo.GetByID(bg(), d.ID)
	if got.LastSeenAt == nil {
		t.Error("expected LastSeenAt to be set")
	}
}

func TestDevice_Revoke(t *testing.T) {
	repo := devicepg.New(testDB)
	userID := insertUser(t, uniqueEmail())
	d, _ := repo.Create(bg(), device.RegisterParams{
		UserID: userID, Name: "ToRevoke", Platform: device.PlatformWeb, Fingerprint: randHex(16),
	})

	if err := repo.Revoke(bg(), d.ID); err != nil {
		t.Fatalf("Revoke: %v", err)
	}

	got, _ := repo.GetByID(bg(), d.ID)
	if got.RevokedAt == nil {
		t.Error("expected RevokedAt to be set after Revoke")
	}
	if !got.IsRevoked() {
		t.Error("IsRevoked() must return true")
	}
}
