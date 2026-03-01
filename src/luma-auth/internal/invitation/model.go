package invitation

import "time"

// Status represents the invitation lifecycle.
type Status string

const (
	StatusPending  Status = "pending"
	StatusAccepted Status = "accepted"
	StatusExpired  Status = "expired"
	StatusRevoked  Status = "revoked"
)

// Invitation is a pending invite link. The raw token is sent to the invitee
// and never stored — only the SHA-256 hash is persisted.
type Invitation struct {
	ID         string
	InviterID  string
	Email      string // optional — may be blank for QR-only invites
	Note       string
	TokenHash  string // SHA-256(raw), hex — used for lookups
	Status     Status
	ExpiresAt  time.Time
	AcceptedAt *time.Time
	RevokedAt  *time.Time
	CreatedAt  time.Time
}

// IsValid returns true if the invitation can still be accepted.
// Invalid, expired, and revoked tokens must show the same error to the invitee.
func (i *Invitation) IsValid() bool {
	return i.Status == StatusPending && time.Now().Before(i.ExpiresAt)
}

// CreateParams holds the inputs for creating an invitation.
type CreateParams struct {
	InviterID string
	Email     string
	Note      string
}
