package session

import "time"

// RefreshToken represents a row in auth.refresh_tokens.
// The raw token is never stored here or in the database — only the hash.
type RefreshToken struct {
	ID         string
	DeviceID   string
	TokenHash  string // SHA-256(raw), hex — used for lookups
	ExpiresAt  time.Time
	ConsumedAt *time.Time
	RevokedAt  *time.Time
	CreatedAt  time.Time
}

// IsValid returns true if the token has not been consumed, revoked, or expired.
func (t *RefreshToken) IsValid() bool {
	return t.ConsumedAt == nil && t.RevokedAt == nil && time.Now().Before(t.ExpiresAt)
}

// LoginParams holds the validated inputs for a login request.
type LoginParams struct {
	Email       string
	Password    string
	DeviceName  string
	Platform    string
	Fingerprint string
	UserAgent   string
	IPAddress   string
}

// TokenPair is the response from a successful login or token refresh.
type TokenPair struct {
	AccessToken  string
	RefreshToken string // raw — hand to client; never store
	ExpiresAt    time.Time
}

// LoginResult is the outcome of a login attempt. Either Pair is set (no MFA)
// or MFARequired is true and MFAToken/MFAMethods are set.
type LoginResult struct {
	Pair        *TokenPair
	MFARequired bool
	MFAToken    string   // raw opaque token — only set when MFARequired
	MFAMethods  []string // e.g. ["totp", "passkey"]
}

// IdentifyResult tells the frontend which authentication steps to present
// after the user enters their email. For unknown emails, all fields are false
// to prevent email enumeration.
type IdentifyResult struct {
	HasPasskey bool `json:"has_passkey"`
	HasTOTP    bool `json:"has_totp"`
	HasMFA     bool `json:"has_mfa"`
}
