package integration_test

import (
	"testing"

	"github.com/josephtindall/luma-auth/internal/audit"
	auditpg "github.com/josephtindall/luma-auth/internal/audit/postgres"
)

func TestAudit_Insert_And_ListForUser(t *testing.T) {
	repo := auditpg.New(testDB)
	userID := insertUser(t, uniqueEmail())

	events := []string{audit.EventLoginSuccess, audit.EventTokenRefreshed, audit.EventLogout}
	for _, ev := range events {
		if err := repo.Insert(bg(), audit.Event{
			UserID:   userID,
			Event:    ev,
			Metadata: map[string]any{"test": true},
		}); err != nil {
			t.Fatalf("Insert(%q): %v", ev, err)
		}
	}

	rows, err := repo.ListForUser(bg(), userID, 10, 0)
	if err != nil {
		t.Fatalf("ListForUser: %v", err)
	}
	if len(rows) != 3 {
		t.Errorf("row count = %d, want 3", len(rows))
	}
	// Rows are ordered by occurred_at DESC — last inserted first.
	if rows[0].Event != audit.EventLogout {
		t.Errorf("first row event = %q, want %q", rows[0].Event, audit.EventLogout)
	}
}

func TestAudit_Insert_WithEmptyOptionalFields(t *testing.T) {
	repo := auditpg.New(testDB)

	// All optional fields empty — must not error.
	if err := repo.Insert(bg(), audit.Event{
		Event: "system_startup",
	}); err != nil {
		t.Fatalf("Insert with empty optional fields: %v", err)
	}
}

func TestAudit_Insert_WithDevice(t *testing.T) {
	repo := auditpg.New(testDB)
	userID := insertUser(t, uniqueEmail())
	deviceID := insertDevice(t, userID, randHex(16))

	if err := repo.Insert(bg(), audit.Event{
		UserID:   userID,
		DeviceID: deviceID,
		Event:    audit.EventDeviceRegistered,
		Metadata: map[string]any{"platform": "web"},
	}); err != nil {
		t.Fatalf("Insert with device: %v", err)
	}

	rows, err := repo.ListForUser(bg(), userID, 10, 0)
	if err != nil {
		t.Fatalf("ListForUser: %v", err)
	}
	if len(rows) == 0 {
		t.Fatal("expected at least one row")
	}
	if rows[0].DeviceID == nil || *rows[0].DeviceID != deviceID {
		t.Errorf("DeviceID mismatch: got %v", rows[0].DeviceID)
	}
}

func TestAudit_ListForUser_Pagination(t *testing.T) {
	repo := auditpg.New(testDB)
	userID := insertUser(t, uniqueEmail())

	for i := 0; i < 5; i++ {
		repo.Insert(bg(), audit.Event{UserID: userID, Event: audit.EventLoginSuccess}) //nolint:errcheck
	}

	page1, _ := repo.ListForUser(bg(), userID, 3, 0)
	page2, _ := repo.ListForUser(bg(), userID, 3, 3)

	if len(page1) != 3 {
		t.Errorf("page1 count = %d, want 3", len(page1))
	}
	if len(page2) != 2 {
		t.Errorf("page2 count = %d, want 2", len(page2))
	}
	// No overlap.
	if page1[0].ID == page2[0].ID {
		t.Error("pages overlap")
	}
}

func TestAudit_ListAll(t *testing.T) {
	repo := auditpg.New(testDB)
	userID := insertUser(t, uniqueEmail())

	before, _ := repo.ListAll(bg(), 1000, 0)

	repo.Insert(bg(), audit.Event{UserID: userID, Event: audit.EventProfileUpdated}) //nolint:errcheck

	after, _ := repo.ListAll(bg(), 1000, 0)
	if len(after) <= len(before) {
		t.Error("ListAll count did not increase after Insert")
	}
}

func TestAudit_ListForUser_IsolatesUsers(t *testing.T) {
	repo := auditpg.New(testDB)
	userA := insertUser(t, uniqueEmail())
	userB := insertUser(t, uniqueEmail())

	repo.Insert(bg(), audit.Event{UserID: userA, Event: audit.EventLoginSuccess}) //nolint:errcheck
	repo.Insert(bg(), audit.Event{UserID: userB, Event: audit.EventLoginSuccess}) //nolint:errcheck

	rowsA, _ := repo.ListForUser(bg(), userA, 10, 0)
	for _, r := range rowsA {
		if r.UserID != nil && *r.UserID != userA {
			t.Errorf("ListForUser returned row for wrong user: %q", *r.UserID)
		}
	}
}
