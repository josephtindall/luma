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
	ID         string     `json:"id"`
	InviterID  string     `json:"inviter_id"`
	Email      string     `json:"email"` // optional — may be blank for QR-only invites
	Note       string     `json:"note"`
	TokenHash  string     `json:"-"` // SHA-256(raw), hex — never exposed via API
	Status     Status     `json:"status"`
	ExpiresAt  time.Time  `json:"expires_at"`
	AcceptedAt *time.Time `json:"accepted_at,omitempty"`
	RevokedAt  *time.Time `json:"revoked_at,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`
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
