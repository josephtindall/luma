package session

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/josephtindall/luma-auth/internal/audit"
	"github.com/josephtindall/luma-auth/internal/device"
	"github.com/josephtindall/luma-auth/internal/invitation"
	"github.com/josephtindall/luma-auth/internal/user"
	"github.com/josephtindall/luma-auth/pkg/crypto"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// ── Test fixtures ─────────────────────────────────────────────────────────────

const testPassword = "correct-horse-battery" // 21 chars — passes the 12-char minimum

var testPasswordHash string

// testJWTKey is a 512-bit key used for token generation in tests.
var testJWTKey = func() []byte {
	k := make([]byte, 64)
	for i := range k {
		k[i] = byte(i + 1)
	}
	return k
}()

// TestMain pre-computes the Argon2id hash once (~250 ms) so individual tests
// can reuse it without repeating the expensive operation.
func TestMain(m *testing.M) {
	var err error
	testPasswordHash, err = crypto.HashPassword(testPassword)
	if err != nil {
		panic("failed to hash test password: " + err.Error())
	}
	os.Exit(m.Run())
}

// ── Mock: user.Repository ─────────────────────────────────────────────────────

type mockUserRepo struct {
	user                   *user.User
	getUserErr             error
	failedLoginReturnCount int // returned by IncrementFailedLogins
	lockCalled             bool
	registerID             string
	registerErr            error
}

func (m *mockUserRepo) GetByID(_ context.Context, _ string) (*user.User, error) {
	return m.user, m.getUserErr
}
func (m *mockUserRepo) GetByEmail(_ context.Context, _ string) (*user.User, error) {
	return m.user, m.getUserErr
}
func (m *mockUserRepo) Create(_ context.Context, _ *user.User) error { return nil }
func (m *mockUserRepo) UpdateProfile(_ context.Context, _ string, _ user.UpdateProfileParams) error {
	return nil
}
func (m *mockUserRepo) UpdatePassword(_ context.Context, _, _ string) error { return nil }
func (m *mockUserRepo) IncrementFailedLogins(_ context.Context, _ string) (int, error) {
	return m.failedLoginReturnCount, nil
}
func (m *mockUserRepo) ResetFailedLogins(_ context.Context, _ string) error { return nil }
func (m *mockUserRepo) LockAccount(_ context.Context, _, _ string) error {
	m.lockCalled = true
	return nil
}
func (m *mockUserRepo) UnlockAccount(_ context.Context, _ string) error         { return nil }
func (m *mockUserRepo) SetMFAEnabled(_ context.Context, _ string, _ bool) error { return nil }
func (m *mockUserRepo) RegisterAtomic(_ context.Context, _ user.RegisterParams) (string, error) {
	return m.registerID, m.registerErr
}

// ── Mock: device.Repository ───────────────────────────────────────────────────

type mockDeviceRepo struct {
	device    *device.Device // returned by GetByFingerprint and GetByID
	createDev *device.Device // overrides the auto-created device on Create
}

func (m *mockDeviceRepo) GetByID(_ context.Context, _ string) (*device.Device, error) {
	if m.device == nil {
		return nil, pkgerrors.ErrDeviceNotFound
	}
	return m.device, nil
}
func (m *mockDeviceRepo) GetByFingerprint(_ context.Context, _, _ string) (*device.Device, error) {
	return m.device, nil // nil = not found, register a new device
}
func (m *mockDeviceRepo) ListForUser(_ context.Context, _ string) ([]*device.Device, error) {
	return nil, nil
}
func (m *mockDeviceRepo) Create(_ context.Context, p device.RegisterParams) (*device.Device, error) {
	if m.createDev != nil {
		return m.createDev, nil
	}
	return &device.Device{
		ID:       "dev-new",
		UserID:   p.UserID,
		Name:     p.Name,
		Platform: p.Platform,
	}, nil
}
func (m *mockDeviceRepo) UpdateLastSeen(_ context.Context, _ string) error { return nil }
func (m *mockDeviceRepo) Revoke(_ context.Context, _ string) error         { return nil }

// ── Mock: session.Repository ──────────────────────────────────────────────────

type mockTokenRepo struct {
	token           *RefreshToken
	getErr          error
	revokeAllCalled bool
}

func (m *mockTokenRepo) Create(_ context.Context, _ *RefreshToken) error { return nil }
func (m *mockTokenRepo) GetByHash(_ context.Context, _ string) (*RefreshToken, error) {
	return m.token, m.getErr
}
func (m *mockTokenRepo) Consume(_ context.Context, _ string) error { return nil }
func (m *mockTokenRepo) RevokeAllForUser(_ context.Context, _ string) error {
	m.revokeAllCalled = true
	return nil
}
func (m *mockTokenRepo) RevokeAllForDevice(_ context.Context, _ string) error { return nil }

// ── Mock: audit.Service ───────────────────────────────────────────────────────

type mockAuditSvc struct {
	events []string
}

func (m *mockAuditSvc) WriteAsync(_ context.Context, e audit.Event) {
	m.events = append(m.events, e.Event)
}

// ── Mock: invitation.Repository ───────────────────────────────────────────────

type mockInvRepo struct {
	inv    *invitation.Invitation
	getErr error
}

func (m *mockInvRepo) Create(_ context.Context, _ *invitation.Invitation) error { return nil }
func (m *mockInvRepo) GetByHash(_ context.Context, _ string) (*invitation.Invitation, error) {
	return m.inv, m.getErr
}
func (m *mockInvRepo) GetByID(_ context.Context, _ string) (*invitation.Invitation, error) {
	return m.inv, m.getErr
}
func (m *mockInvRepo) List(_ context.Context) ([]*invitation.Invitation, error) { return nil, nil }
func (m *mockInvRepo) Accept(_ context.Context, _ string) error                 { return nil }
func (m *mockInvRepo) Revoke(_ context.Context, _ string) error                 { return nil }

// ── Mock: MFAMethodChecker ────────────────────────────────────────────────────

type mockMFAChecker struct {
	totpCount    int
	passkeyCount int
}

func (m *mockMFAChecker) CountVerifiedTOTPSecrets(_ context.Context, _ string) (int, error) {
	return m.totpCount, nil
}
func (m *mockMFAChecker) CountActivePasskeys(_ context.Context, _ string) (int, error) {
	return m.passkeyCount, nil
}

// ── Helpers ───────────────────────────────────────────────────────────────────

func newSvc(
	users user.Repository,
	devices device.Repository,
	tokens Repository,
	auditSvc audit.Service,
	invs invitation.Repository,
) *Service {
	return NewService(users, devices, tokens, auditSvc, invs, nil, nil, testJWTKey)
}

func newSvcWithMFA(
	users user.Repository,
	devices device.Repository,
	tokens Repository,
	auditSvc audit.Service,
	invs invitation.Repository,
	checker MFAMethodChecker,
) *Service {
	return NewService(users, devices, tokens, auditSvc, invs, nil, checker, testJWTKey)
}

func activeUser() *user.User {
	return &user.User{
		ID:             "user-1",
		Email:          "alice@example.com",
		DisplayName:    "Alice",
		PasswordHash:   testPasswordHash,
		InstanceRoleID: "builtin:instance-member",
	}
}

func lockedUser() *user.User {
	u := activeUser()
	now := time.Now()
	u.LockedAt = &now
	return u
}

func validInvitation() *invitation.Invitation {
	return &invitation.Invitation{
		ID:        "inv-1",
		Status:    invitation.StatusPending,
		ExpiresAt: time.Now().Add(24 * time.Hour),
	}
}

func activeDevice(userID string) *device.Device {
	return &device.Device{ID: "dev-1", UserID: userID}
}

func validRefreshToken(deviceID string) *RefreshToken {
	return &RefreshToken{
		ID:        "rt-1",
		DeviceID:  deviceID,
		TokenHash: "hash",
		ExpiresAt: time.Now().Add(30 * 24 * time.Hour),
	}
}

// ── Login tests ───────────────────────────────────────────────────────────────

func TestLogin_Success(t *testing.T) {
	users := &mockUserRepo{user: activeUser()}
	svc := newSvc(users, &mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{})

	result, err := svc.Login(context.Background(), LoginParams{
		Email:    "alice@example.com",
		Password: testPassword,
	})
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if result.MFARequired {
		t.Error("expected MFARequired=false for user without MFA")
	}
	if result.Pair.AccessToken == "" || result.Pair.RefreshToken == "" {
		t.Error("expected non-empty token pair")
	}
}

func TestLogin_UserNotFound_ReturnsInvalidCredentials(t *testing.T) {
	users := &mockUserRepo{getUserErr: pkgerrors.ErrUserNotFound}
	svc := newSvc(users, &mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{})

	_, err := svc.Login(context.Background(), LoginParams{Email: "nobody@x.com", Password: "pw"})
	if !errors.Is(err, pkgerrors.ErrInvalidCredentials) {
		t.Errorf("user not found: expected ErrInvalidCredentials, got %v", err)
	}
}

func TestLogin_WrongPassword_ReturnsInvalidCredentials(t *testing.T) {
	users := &mockUserRepo{user: activeUser()}
	svc := newSvc(users, &mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{})

	_, err := svc.Login(context.Background(), LoginParams{
		Email:    "alice@example.com",
		Password: "definitely-wrong-password",
	})
	if !errors.Is(err, pkgerrors.ErrInvalidCredentials) {
		t.Errorf("wrong password: expected ErrInvalidCredentials, got %v", err)
	}
}

// TestLogin_IdenticalErrorForMissingAndWrongPassword verifies the security
// invariant: "email not found" and "wrong password" are indistinguishable.
func TestLogin_IdenticalErrorForMissingAndWrongPassword(t *testing.T) {
	svcNotFound := newSvc(
		&mockUserRepo{getUserErr: pkgerrors.ErrUserNotFound},
		&mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{},
	)
	svcWrongPw := newSvc(
		&mockUserRepo{user: activeUser()},
		&mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{},
	)

	_, errNotFound := svcNotFound.Login(context.Background(), LoginParams{Email: "x@x.com", Password: "pw"})
	_, errWrongPw := svcWrongPw.Login(context.Background(), LoginParams{Email: "x@x.com", Password: "wrong"})

	if !errors.Is(errNotFound, pkgerrors.ErrInvalidCredentials) {
		t.Errorf("not found: got %v, want ErrInvalidCredentials", errNotFound)
	}
	if !errors.Is(errWrongPw, pkgerrors.ErrInvalidCredentials) {
		t.Errorf("wrong pw: got %v, want ErrInvalidCredentials", errWrongPw)
	}
}

func TestLogin_LockedAccount_ReturnsAccountLocked(t *testing.T) {
	users := &mockUserRepo{user: lockedUser()}
	svc := newSvc(users, &mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{})

	_, err := svc.Login(context.Background(), LoginParams{
		Email:    "alice@example.com",
		Password: testPassword, // correct password — lock check comes after
	})
	if !errors.Is(err, pkgerrors.ErrAccountLocked) {
		t.Errorf("expected ErrAccountLocked, got %v", err)
	}
}

func TestLogin_RevokedDevice_ReturnsDeviceRevoked(t *testing.T) {
	revokedAt := time.Now()
	revokedDev := &device.Device{ID: "dev-1", UserID: "user-1", RevokedAt: &revokedAt}

	svc := newSvc(
		&mockUserRepo{user: activeUser()},
		&mockDeviceRepo{device: revokedDev},
		&mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{},
	)

	_, err := svc.Login(context.Background(), LoginParams{
		Email:       "alice@example.com",
		Password:    testPassword,
		Fingerprint: "fp-known",
	})
	if !errors.Is(err, pkgerrors.ErrDeviceRevoked) {
		t.Errorf("expected ErrDeviceRevoked, got %v", err)
	}
}

// TestLogin_BruteForce_LocksAt10 verifies that LockAccount is called when
// IncrementFailedLogins reports the threshold count.
// Uses a single wrong-password attempt with a mock that returns count=10.
func TestLogin_BruteForce_LocksAt10(t *testing.T) {
	users := &mockUserRepo{
		user:                   activeUser(),
		failedLoginReturnCount: 10,
	}
	svc := newSvc(users, &mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{})

	svc.Login(context.Background(), LoginParams{ //nolint:errcheck
		Email:    "alice@example.com",
		Password: "wrong-password",
	})

	if !users.lockCalled {
		t.Error("expected LockAccount to be called when failed attempt count reaches 10")
	}
}

func TestLogin_NewDevice_RegisteredAndAudited(t *testing.T) {
	auditSvc := &mockAuditSvc{}
	svc := newSvc(
		&mockUserRepo{user: activeUser()},
		&mockDeviceRepo{device: nil}, // nil = new device
		&mockTokenRepo{},
		auditSvc,
		&mockInvRepo{},
	)

	_, err := svc.Login(context.Background(), LoginParams{
		Email:       "alice@example.com",
		Password:    testPassword,
		Fingerprint: "brand-new-fingerprint",
		Platform:    "web",
	})
	if err != nil {
		t.Fatalf("Login: %v", err)
	}

	var found bool
	for _, ev := range auditSvc.events {
		if ev == audit.EventDeviceRegistered {
			found = true
		}
	}
	if !found {
		t.Errorf("expected device_registered audit event; got %v", auditSvc.events)
	}
}

// ── Refresh tests ─────────────────────────────────────────────────────────────

func TestRefresh_Success(t *testing.T) {
	dev := activeDevice("user-1")
	rt := validRefreshToken(dev.ID)

	svc := newSvc(
		&mockUserRepo{user: activeUser()},
		&mockDeviceRepo{device: dev},
		&mockTokenRepo{token: rt},
		&mockAuditSvc{},
		&mockInvRepo{},
	)

	pair, err := svc.Refresh(context.Background(), "raw-token-value")
	if err != nil {
		t.Fatalf("Refresh: %v", err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Error("expected non-empty token pair")
	}
}

func TestRefresh_InvalidToken(t *testing.T) {
	svc := newSvc(
		&mockUserRepo{},
		&mockDeviceRepo{},
		&mockTokenRepo{getErr: errors.New("not found")},
		&mockAuditSvc{},
		&mockInvRepo{},
	)

	_, err := svc.Refresh(context.Background(), "bad-token")
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid, got %v", err)
	}
}

func TestRefresh_RevokedToken(t *testing.T) {
	revokedAt := time.Now()
	rt := &RefreshToken{
		ID:        "rt-1",
		DeviceID:  "dev-1",
		TokenHash: "hash",
		ExpiresAt: time.Now().Add(30 * 24 * time.Hour),
		RevokedAt: &revokedAt,
	}

	svc := newSvc(
		&mockUserRepo{},
		&mockDeviceRepo{},
		&mockTokenRepo{token: rt},
		&mockAuditSvc{},
		&mockInvRepo{},
	)

	_, err := svc.Refresh(context.Background(), "raw-token")
	if !errors.Is(err, pkgerrors.ErrTokenRevoked) {
		t.Errorf("expected ErrTokenRevoked, got %v", err)
	}
}

func TestRefresh_ReuseDetection_RevokesAllSessions(t *testing.T) {
	consumedAt := time.Now().Add(-1 * time.Minute)
	rt := &RefreshToken{
		ID:         "rt-1",
		DeviceID:   "dev-1",
		TokenHash:  "hash",
		ExpiresAt:  time.Now().Add(30 * 24 * time.Hour),
		ConsumedAt: &consumedAt,
	}

	tokens := &mockTokenRepo{token: rt}
	svc := newSvc(
		&mockUserRepo{user: activeUser()},
		&mockDeviceRepo{device: activeDevice("user-1")},
		tokens,
		&mockAuditSvc{},
		&mockInvRepo{},
	)

	_, err := svc.Refresh(context.Background(), "reused-token")
	if !errors.Is(err, pkgerrors.ErrTokenReuseDetected) {
		t.Errorf("expected ErrTokenReuseDetected, got %v", err)
	}
	if !tokens.revokeAllCalled {
		t.Error("expected RevokeAllForUser to be called on token reuse")
	}
}

func TestRefresh_ExpiredToken(t *testing.T) {
	rt := &RefreshToken{
		ID:        "rt-1",
		DeviceID:  "dev-1",
		TokenHash: "hash",
		ExpiresAt: time.Now().Add(-1 * time.Hour), // expired
	}

	svc := newSvc(
		&mockUserRepo{},
		&mockDeviceRepo{},
		&mockTokenRepo{token: rt},
		&mockAuditSvc{},
		&mockInvRepo{},
	)

	_, err := svc.Refresh(context.Background(), "expired-token")
	if !errors.Is(err, pkgerrors.ErrTokenRevoked) {
		t.Errorf("expected ErrTokenRevoked for expired token, got %v", err)
	}
}

// ── Register tests ────────────────────────────────────────────────────────────

func TestRegister_Success(t *testing.T) {
	newUser := &user.User{
		ID:             "user-new",
		Email:          "bob@example.com",
		DisplayName:    "Bob",
		InstanceRoleID: "builtin:instance-member",
	}
	svc := newSvc(
		&mockUserRepo{registerID: "user-new", user: newUser},
		&mockDeviceRepo{},
		&mockTokenRepo{},
		&mockAuditSvc{},
		&mockInvRepo{inv: validInvitation()},
	)

	pair, err := svc.Register(context.Background(), SessionRegisterParams{
		InvitationID: "inv-1",
		Email:        "bob@example.com",
		DisplayName:  "Bob",
		Password:     "long-enough-password-here",
		Platform:     "web",
	})
	if err != nil {
		t.Fatalf("Register: %v", err)
	}
	if pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Error("expected non-empty token pair")
	}
}

func TestRegister_InvalidInvitation_ReturnsTokenInvalid(t *testing.T) {
	svc := newSvc(
		&mockUserRepo{},
		&mockDeviceRepo{},
		&mockTokenRepo{},
		&mockAuditSvc{},
		&mockInvRepo{getErr: errors.New("not found")},
	)

	_, err := svc.Register(context.Background(), SessionRegisterParams{
		InvitationID: "bad-inv",
		Email:        "x@x.com",
		Password:     "long-enough-password",
	})
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid for bad invitation, got %v", err)
	}
}

func TestRegister_ExpiredInvitation_ReturnsTokenInvalid(t *testing.T) {
	expiredInv := &invitation.Invitation{
		ID:        "inv-expired",
		Status:    invitation.StatusPending,
		ExpiresAt: time.Now().Add(-1 * time.Hour),
	}
	svc := newSvc(
		&mockUserRepo{},
		&mockDeviceRepo{},
		&mockTokenRepo{},
		&mockAuditSvc{},
		&mockInvRepo{inv: expiredInv},
	)

	_, err := svc.Register(context.Background(), SessionRegisterParams{
		InvitationID: "inv-expired",
		Email:        "x@x.com",
		Password:     "long-enough-password",
	})
	if !errors.Is(err, pkgerrors.ErrTokenInvalid) {
		t.Errorf("expected ErrTokenInvalid for expired invitation, got %v", err)
	}
}

func TestRegister_PasswordTooShort(t *testing.T) {
	svc := newSvc(
		&mockUserRepo{},
		&mockDeviceRepo{},
		&mockTokenRepo{},
		&mockAuditSvc{},
		&mockInvRepo{inv: validInvitation()},
	)

	_, err := svc.Register(context.Background(), SessionRegisterParams{
		InvitationID: "inv-1",
		Email:        "x@x.com",
		Password:     "short", // < 12 chars
	})
	if !errors.Is(err, pkgerrors.ErrPasswordTooShort) {
		t.Errorf("expected ErrPasswordTooShort, got %v", err)
	}
}

func TestRegister_EmailTaken(t *testing.T) {
	svc := newSvc(
		&mockUserRepo{registerErr: pkgerrors.ErrEmailTaken},
		&mockDeviceRepo{},
		&mockTokenRepo{},
		&mockAuditSvc{},
		&mockInvRepo{inv: validInvitation()},
	)

	_, err := svc.Register(context.Background(), SessionRegisterParams{
		InvitationID: "inv-1",
		Email:        "existing@x.com",
		Password:     "long-enough-password-here",
	})
	if !errors.Is(err, pkgerrors.ErrEmailTaken) {
		t.Errorf("expected ErrEmailTaken, got %v", err)
	}
}

func TestRegister_AuditsUserRegistered(t *testing.T) {
	auditSvc := &mockAuditSvc{}
	newUser := &user.User{
		ID:             "user-new",
		InstanceRoleID: "builtin:instance-member",
	}
	svc := newSvc(
		&mockUserRepo{registerID: "user-new", user: newUser},
		&mockDeviceRepo{},
		&mockTokenRepo{},
		auditSvc,
		&mockInvRepo{inv: validInvitation()},
	)

	_, err := svc.Register(context.Background(), SessionRegisterParams{
		InvitationID: "inv-1",
		Email:        "bob@example.com",
		Password:     "long-enough-password-here",
	})
	if err != nil {
		t.Fatalf("Register: %v", err)
	}

	var found bool
	for _, ev := range auditSvc.events {
		if ev == audit.EventUserRegistered {
			found = true
		}
	}
	if !found {
		t.Errorf("expected user_registered audit event; got %v", auditSvc.events)
	}
}

// ── Identify tests ────────────────────────────────────────────────────────────

func TestIdentify_ExistingUser_WithPasskeyAndTOTP(t *testing.T) {
	u := activeUser()
	u.MFAEnabled = true

	svc := newSvcWithMFA(
		&mockUserRepo{user: u},
		&mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{},
		&mockMFAChecker{totpCount: 1, passkeyCount: 2},
	)

	result, err := svc.Identify(context.Background(), "alice@example.com")
	if err != nil {
		t.Fatalf("Identify: %v", err)
	}
	if !result.HasMFA || !result.HasPasskey || !result.HasTOTP {
		t.Errorf("expected all MFA flags true, got %+v", result)
	}
}

func TestIdentify_ExistingUser_PasswordOnly(t *testing.T) {
	svc := newSvcWithMFA(
		&mockUserRepo{user: activeUser()}, // MFAEnabled = false
		&mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{},
		&mockMFAChecker{},
	)

	result, err := svc.Identify(context.Background(), "alice@example.com")
	if err != nil {
		t.Fatalf("Identify: %v", err)
	}
	if result.HasMFA || result.HasPasskey || result.HasTOTP {
		t.Errorf("expected all MFA flags false for password-only user, got %+v", result)
	}
}

func TestIdentify_UnknownEmail_ReturnsSameAsPasswordOnly(t *testing.T) {
	svc := newSvcWithMFA(
		&mockUserRepo{getUserErr: pkgerrors.ErrUserNotFound},
		&mockDeviceRepo{}, &mockTokenRepo{}, &mockAuditSvc{}, &mockInvRepo{},
		&mockMFAChecker{totpCount: 99, passkeyCount: 99}, // should never be reached
	)

	result, err := svc.Identify(context.Background(), "nobody@example.com")
	if err != nil {
		t.Fatalf("Identify: %v", err)
	}
	if result.HasMFA || result.HasPasskey || result.HasTOTP {
		t.Errorf("expected all MFA flags false for unknown email (anti-enumeration), got %+v", result)
	}
}
