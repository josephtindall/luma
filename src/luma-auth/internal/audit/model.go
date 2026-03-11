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
// UserEmail and UserDisplayName are populated only by ListAll (via JOIN).
type Row struct {
	ID              int64
	UserID          *string
	DeviceID        *string
	Event           string
	IPAddress       *string
	UserAgent       *string
	Metadata        map[string]any
	OccurredAt      time.Time
	UserEmail       *string // populated by ListAll JOIN; nil otherwise
	UserDisplayName *string // populated by ListAll JOIN; nil otherwise
}

// AuditQuery holds filter + pagination parameters for listing audit events.
type AuditQuery struct {
	Limit       int        // max rows; 0 → use handler default
	Offset      int        // rows to skip
	Search      string     // ILIKE match against event + user_agent (empty = no filter)
	EventFilter string     // exact event type to include (empty = all types)
	Exclude     string     // exact event type to exclude (empty = none)
	After       *time.Time // occurred_at >= After
	Before      *time.Time // occurred_at <= Before
}

// Page is a paginated result set returned by list queries.
type Page struct {
	Rows  []*Row
	Total int // total matching rows (ignoring Limit/Offset)
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
