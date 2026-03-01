package session

import "time"

// RefreshToken represents a row in haven.refresh_tokens.
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
