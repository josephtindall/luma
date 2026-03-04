package mfa

import "time"

// TOTPSecret represents a row in auth.totp_secrets.
type TOTPSecret struct {
	ID              string
	UserID          string
	Name            string // user-chosen nickname, e.g. "Work phone"
	Secret          []byte // 20-byte raw TOTP seed
	Verified        bool
	LastUsedCounter int64 // last accepted TOTP time-step counter (replay guard)
	CreatedAt       time.Time
}

// MFAChallenge represents a row in auth.mfa_challenges.
// The raw token is never stored — only the hash.
type MFAChallenge struct {
	ID         string
	UserID     string
	DeviceID   string
	TokenHash  string
	ExpiresAt  time.Time
	ConsumedAt *time.Time
	CreatedAt  time.Time
}

// IsValid returns true if the challenge is not consumed and not expired.
func (c *MFAChallenge) IsValid() bool {
	return c.ConsumedAt == nil && time.Now().Before(c.ExpiresAt)
}

// Passkey represents a row in auth.passkeys.
type Passkey struct {
	ID             string
	UserID         string
	CredentialID   []byte
	PublicKey      []byte
	SignCount      int64
	Name           string
	AAGUID         []byte
	Transports     []string
	BackupEligible bool
	BackupState    bool
	LastUsedAt     *time.Time
	RevokedAt      *time.Time
	CreatedAt      time.Time
}

// IsRevoked returns true if the passkey has been revoked.
func (p *Passkey) IsRevoked() bool {
	return p.RevokedAt != nil
}

// TOTPSetupResult is returned when a user begins TOTP enrollment.
type TOTPSetupResult struct {
	ID         string // UUID of the pending secret — needed for confirm
	Secret     string // base32-encoded secret for manual entry
	OTPAuthURI string // otpauth:// URI for QR code generation
}

// ChallengeResult is returned when login requires MFA.
type ChallengeResult struct {
	MFAToken string   // raw opaque token — hand to client
	Methods  []string // e.g. ["totp", "passkey"]
}
