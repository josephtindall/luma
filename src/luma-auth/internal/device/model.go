package device

import "time"

// Platform identifies the client type. The DB enforces this via CHECK constraint.
type Platform string

const (
	PlatformWeb     Platform = "web"
	PlatformIOS     Platform = "ios"
	PlatformAndroid Platform = "android"
	PlatformAgent   Platform = "agent"
)

// Device represents a registered client device for a user.
type Device struct {
	ID          string
	UserID      string
	Name        string
	Platform    Platform
	Fingerprint string
	UserAgent   string
	LastSeenAt  *time.Time
	RevokedAt   *time.Time
	CreatedAt   time.Time
}

// IsRevoked returns true if the device has been explicitly revoked.
func (d *Device) IsRevoked() bool {
	return d.RevokedAt != nil
}

// RegisterParams holds the values needed to register a new device.
type RegisterParams struct {
	UserID      string
	Name        string
	Platform    Platform
	Fingerprint string
	UserAgent   string
}
