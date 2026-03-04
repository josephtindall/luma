package audit

import "time"

// Event is a single audit log entry. All fields are optional except Event.
// The DB row is insert-only — no updates, no deletes, ever.
type Event struct {
	UserID    string // may be empty for pre-authentication events
	DeviceID  string // may be empty
	Event     string // canonical event name from the audit event reference
	IPAddress string // client IP address
	UserAgent string
	Metadata  map[string]any // arbitrary structured context
}

// Row is the persisted form of an audit event (includes DB-assigned fields).
type Row struct {
	ID         int64
	UserID     *string
	DeviceID   *string
	Event      string
	IPAddress  *string
	UserAgent  *string
	Metadata   map[string]any
	OccurredAt time.Time
}

// Canonical event name constants — the complete set from the design spec.
const (
	EventLoginSuccess       = "login_success"
	EventLoginFailed        = "login_failed"
	EventLogout             = "logout"
	EventLogoutAll          = "logout_all"
	EventTokenRefreshed     = "token_refreshed"
	EventTokenReuseDetected = "token_reuse_detected"
	EventDeviceRegistered   = "device_registered"
	EventDeviceRevoked      = "device_revoked"
	EventPasswordChanged    = "password_changed"
	EventAccountLocked      = "account_locked"
	EventAccountUnlocked    = "account_unlocked"
	EventProfileUpdated     = "profile_updated"
	EventAuthzDenied        = "authz_denied"
	EventUserRegistered     = "user_registered"
	EventTOTPEnrolled       = "totp_enrolled"
	EventTOTPRemoved        = "totp_removed"
	EventMFAChallengeOK     = "mfa_challenge_success"
	EventMFAChallengeFail   = "mfa_challenge_failed"
	EventPasskeyRegistered  = "passkey_registered"
	EventPasskeyLogin       = "passkey_login"
	EventPasskeyRevoked     = "passkey_revoked"
)
