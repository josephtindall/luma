package vaults

import (
	"context"
	"testing"

	"github.com/josephtindall/luma/pkg/errors"
)

// mockRepository is a test double for Repository.
type mockRepository struct {
	vaults       map[string]*Vault
	members      map[string]map[string]*VaultMember // vaultID -> userID -> member
	adminCounts  map[string]int
	createCalled int
	createErr    error
}

func newMockRepo() *mockRepository {
	return &mockRepository{
		vaults:      make(map[string]*Vault),
		members:     make(map[string]map[string]*VaultMember),
		adminCounts: make(map[string]int),
	}
}

func (m *mockRepository) Create(_ context.Context, vault *Vault) error {
	m.createCalled++
	if m.createErr != nil {
		return m.createErr
	}
	if vault.ID == "" {
		vault.ID = "generated-uuid"
	}
	m.vaults[vault.ID] = vault
	return nil
}

func (m *mockRepository) GetByID(_ context.Context, id string) (*Vault, error) {
	v, ok := m.vaults[id]
	if !ok {
		return nil, errors.ErrNotFound
	}
	return v, nil
}

func (m *mockRepository) ListByUser(_ context.Context, _ string, _ bool) ([]*Vault, error) {
	var result []*Vault
	for _, v := range m.vaults {
		result = append(result, v)
	}
	return result, nil
}

func (m *mockRepository) Update(_ context.Context, vault *Vault) error {
	m.vaults[vault.ID] = vault
	return nil
}

func (m *mockRepository) Archive(_ context.Context, id, _ string) error {
	v, ok := m.vaults[id]
	if !ok {
		return errors.ErrNotFound
	}
	v.IsArchived = true
	return nil
}

func (m *mockRepository) HasPersonalVault(_ context.Context, userID string) (bool, error) {
	for _, v := range m.vaults {
		if v.OwnerID == userID && v.Type == VaultTypePersonal {
			return true, nil
		}
	}
	return false, nil
}

func (m *mockRepository) AddMember(_ context.Context, member *VaultMember) error {
	if m.members[member.VaultID] == nil {
		m.members[member.VaultID] = make(map[string]*VaultMember)
	}
	m.members[member.VaultID][member.UserID] = member
	if member.RoleID == "builtin:vault-admin" {
		m.adminCounts[member.VaultID]++
	}
	return nil
}

func (m *mockRepository) RemoveMember(_ context.Context, vaultID, userID string) error {
	members := m.members[vaultID]
	if members == nil {
		return errors.ErrNotFound
	}
	member, ok := members[userID]
	if !ok {
		return errors.ErrNotFound
	}
	if member.RoleID == "builtin:vault-admin" {
		m.adminCounts[vaultID]--
	}
	delete(members, userID)
	return nil
}

func (m *mockRepository) UpdateMemberRole(_ context.Context, vaultID, userID, roleID string) error {
	members := m.members[vaultID]
	if members == nil {
		return errors.ErrNotFound
	}
	member, ok := members[userID]
	if !ok {
		return errors.ErrNotFound
	}
	oldRole := member.RoleID
	member.RoleID = roleID
	if oldRole == "builtin:vault-admin" && roleID != "builtin:vault-admin" {
		m.adminCounts[vaultID]--
	}
	if oldRole != "builtin:vault-admin" && roleID == "builtin:vault-admin" {
		m.adminCounts[vaultID]++
	}
	return nil
}

func (m *mockRepository) ListMembers(_ context.Context, vaultID string) ([]*VaultMember, error) {
	var result []*VaultMember
	for _, member := range m.members[vaultID] {
		result = append(result, member)
	}
	return result, nil
}

func (m *mockRepository) GetMember(_ context.Context, vaultID, userID string) (*VaultMember, error) {
	members := m.members[vaultID]
	if members == nil {
		return nil, errors.ErrNotFound
	}
	member, ok := members[userID]
	if !ok {
		return nil, errors.ErrNotFound
	}
	return member, nil
}

func (m *mockRepository) CountAdmins(_ context.Context, vaultID string) (int, error) {
	return m.adminCounts[vaultID], nil
}

// --- Tests ---

func TestCreateSharedVault_Success(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	vault, err := svc.CreateSharedVault(context.Background(), "user-1", CreateVaultRequest{
		Name: "Engineering",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if vault.Name != "Engineering" {
		t.Errorf("expected name 'Engineering', got %q", vault.Name)
	}
	if vault.Type != VaultTypeShared {
		t.Errorf("expected type 'shared', got %q", vault.Type)
	}
	if vault.OwnerID != "user-1" {
		t.Errorf("expected owner 'user-1', got %q", vault.OwnerID)
	}
}

func TestCreateSharedVault_EmptyName(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	_, err := svc.CreateSharedVault(context.Background(), "user-1", CreateVaultRequest{
		Name: "   ",
	})
	if !errors.Is(err, errors.ErrValidation) {
		t.Fatalf("expected ErrValidation, got: %v", err)
	}
}

func TestCreatePersonalVault_Success(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	vault, err := svc.CreatePersonalVault(context.Background(), "user-1", "Alice")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if vault.Type != VaultTypePersonal {
		t.Errorf("expected type 'personal', got %q", vault.Type)
	}
	if vault.OwnerID != "user-1" {
		t.Errorf("expected owner 'user-1', got %q", vault.OwnerID)
	}
}

func TestArchiveVault_Success(t *testing.T) {
	repo := newMockRepo()
	repo.vaults["v-1"] = &Vault{ID: "v-1", Name: "Test", IsArchived: false}
	svc := NewService(repo)

	err := svc.ArchiveVault(context.Background(), "v-1", "user-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestArchiveVault_AlreadyArchived(t *testing.T) {
	repo := newMockRepo()
	repo.vaults["v-1"] = &Vault{ID: "v-1", Name: "Test", IsArchived: true}
	svc := NewService(repo)

	err := svc.ArchiveVault(context.Background(), "v-1", "user-1")
	if !errors.Is(err, errors.ErrConflict) {
		t.Fatalf("expected ErrConflict, got: %v", err)
	}
}

func TestUpdateVault_ArchivedVault(t *testing.T) {
	repo := newMockRepo()
	repo.vaults["v-1"] = &Vault{ID: "v-1", Name: "Old", IsArchived: true}
	svc := NewService(repo)

	name := "New Name"
	_, err := svc.UpdateVault(context.Background(), "v-1", UpdateVaultRequest{Name: &name})
	if !errors.Is(err, errors.ErrArchived) {
		t.Fatalf("expected ErrArchived, got: %v", err)
	}
}

func TestAddMember_Success(t *testing.T) {
	repo := newMockRepo()
	repo.vaults["v-1"] = &Vault{ID: "v-1", Name: "Test"}
	svc := NewService(repo)

	err := svc.AddMember(context.Background(), "v-1", AddMemberRequest{
		UserID: "user-2",
		RoleID: "builtin:vault-member",
	}, "user-1")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestAddMember_AlreadyExists(t *testing.T) {
	repo := newMockRepo()
	repo.vaults["v-1"] = &Vault{ID: "v-1", Name: "Test"}
	repo.members["v-1"] = map[string]*VaultMember{
		"user-2": {VaultID: "v-1", UserID: "user-2", RoleID: "builtin:vault-member"},
	}
	svc := NewService(repo)

	err := svc.AddMember(context.Background(), "v-1", AddMemberRequest{
		UserID: "user-2",
		RoleID: "builtin:vault-member",
	}, "user-1")
	if !errors.Is(err, errors.ErrAlreadyExists) {
		t.Fatalf("expected ErrAlreadyExists, got: %v", err)
	}
}

func TestAddMember_ArchivedVault(t *testing.T) {
	repo := newMockRepo()
	repo.vaults["v-1"] = &Vault{ID: "v-1", Name: "Test", IsArchived: true}
	svc := NewService(repo)

	err := svc.AddMember(context.Background(), "v-1", AddMemberRequest{
		UserID: "user-2",
		RoleID: "builtin:vault-member",
	}, "user-1")
	if !errors.Is(err, errors.ErrArchived) {
		t.Fatalf("expected ErrArchived, got: %v", err)
	}
}

func TestRemoveMember_Success(t *testing.T) {
	repo := newMockRepo()
	repo.vaults["v-1"] = &Vault{ID: "v-1", Name: "Test"}
	repo.members["v-1"] = map[string]*VaultMember{
		"user-1": {VaultID: "v-1", UserID: "user-1", RoleID: "builtin:vault-admin"},
		"user-2": {VaultID: "v-1", UserID: "user-2", RoleID: "builtin:vault-member"},
	}
	repo.adminCounts["v-1"] = 1
	svc := NewService(repo)

	err := svc.RemoveMember(context.Background(), "v-1", "user-2")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestRemoveMember_LastAdmin(t *testing.T) {
	repo := newMockRepo()
	repo.vaults["v-1"] = &Vault{ID: "v-1", Name: "Test"}
	repo.members["v-1"] = map[string]*VaultMember{
		"user-1": {VaultID: "v-1", UserID: "user-1", RoleID: "builtin:vault-admin"},
	}
	repo.adminCounts["v-1"] = 1
	svc := NewService(repo)

	err := svc.RemoveMember(context.Background(), "v-1", "user-1")
	if !errors.Is(err, errors.ErrConflict) {
		t.Fatalf("expected ErrConflict for last admin removal, got: %v", err)
	}
}

func TestUpdateMemberRole_Success(t *testing.T) {
	repo := newMockRepo()
	repo.members["v-1"] = map[string]*VaultMember{
		"user-1": {VaultID: "v-1", UserID: "user-1", RoleID: "builtin:vault-admin"},
		"user-2": {VaultID: "v-1", UserID: "user-2", RoleID: "builtin:vault-member"},
	}
	repo.adminCounts["v-1"] = 1
	svc := NewService(repo)

	err := svc.UpdateMemberRole(context.Background(), "v-1", "user-2", "builtin:vault-admin")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestUpdateMemberRole_LastAdminDowngrade(t *testing.T) {
	repo := newMockRepo()
	repo.members["v-1"] = map[string]*VaultMember{
		"user-1": {VaultID: "v-1", UserID: "user-1", RoleID: "builtin:vault-admin"},
	}
	repo.adminCounts["v-1"] = 1
	svc := NewService(repo)

	err := svc.UpdateMemberRole(context.Background(), "v-1", "user-1", "builtin:vault-member")
	if !errors.Is(err, errors.ErrConflict) {
		t.Fatalf("expected ErrConflict for last admin downgrade, got: %v", err)
	}
}

func TestEnsurePersonalVault_Idempotency(t *testing.T) {
	repo := newMockRepo()
	svc := NewService(repo)

	// First call creates the vault.
	err := svc.EnsurePersonalVault(context.Background(), "user-1", "Alice")
	if err != nil {
		t.Fatalf("first EnsurePersonalVault: %v", err)
	}
	if repo.createCalled != 1 {
		t.Fatalf("expected 1 create call, got %d", repo.createCalled)
	}

	// Second call is a no-op because vault already exists.
	err = svc.EnsurePersonalVault(context.Background(), "user-1", "Alice")
	if err != nil {
		t.Fatalf("second EnsurePersonalVault: %v", err)
	}
	if repo.createCalled != 1 {
		t.Errorf("expected no additional create call, got %d total", repo.createCalled)
	}
}
