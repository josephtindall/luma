package preferences

import "time"

// Preferences holds per-user display and notification settings.
// A row is always created with defaults in the same transaction as the user row.
type Preferences struct {
	UserID         string
	Theme          string // "system" | "light" | "dark"
	Language       string // BCP-47
	Timezone       string // IANA
	DateFormat     string // e.g. "YYYY-MM-DD"
	TimeFormat     string // "12h" | "24h"
	NotifyOnLogin  bool
	NotifyOnRevoke bool
	CompactMode    bool
	UpdatedAt      time.Time
}

// UpdateParams holds the patchable subset of Preferences.
type UpdateParams struct {
	Theme          *string
	Language       *string
	Timezone       *string
	DateFormat     *string
	TimeFormat     *string
	NotifyOnLogin  *bool
	NotifyOnRevoke *bool
	CompactMode    *bool
}
