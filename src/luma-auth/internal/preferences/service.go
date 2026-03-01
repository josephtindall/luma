package preferences

import (
	"context"
	"fmt"
	"regexp"
	"time"
)

var bcp47Pattern = regexp.MustCompile(`^[a-zA-Z]{2,8}(-[a-zA-Z0-9]{1,8})*$`)

// Service manages user preferences.
type Service struct {
	repo Repository
}

// NewService constructs the preferences service.
func NewService(repo Repository) *Service {
	return &Service{repo: repo}
}

// Get returns the preferences for a user.
func (s *Service) Get(ctx context.Context, userID string) (*Preferences, error) {
	p, err := s.repo.Get(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("preferences.Service.Get: %w", err)
	}
	return p, nil
}

// Update applies a partial preferences update.
func (s *Service) Update(ctx context.Context, userID string, params UpdateParams) error {
	if params.Theme != nil {
		switch *params.Theme {
		case "system", "light", "dark":
		default:
			return fmt.Errorf("preferences: invalid theme %q: must be \"system\", \"light\", or \"dark\"", *params.Theme)
		}
	}
	if params.TimeFormat != nil {
		switch *params.TimeFormat {
		case "12h", "24h":
		default:
			return fmt.Errorf("preferences: invalid time_format %q: must be \"12h\" or \"24h\"", *params.TimeFormat)
		}
	}
	if params.Timezone != nil {
		if _, err := time.LoadLocation(*params.Timezone); err != nil {
			return fmt.Errorf("preferences: invalid timezone %q: must be a valid IANA timezone (e.g. \"America/New_York\")", *params.Timezone)
		}
	}
	if params.Language != nil {
		if !bcp47Pattern.MatchString(*params.Language) {
			return fmt.Errorf("preferences: invalid language %q: must be a valid BCP-47 language tag (e.g. \"en-US\")", *params.Language)
		}
	}
	if err := s.repo.Update(ctx, userID, params); err != nil {
		return fmt.Errorf("preferences.Service.Update: %w", err)
	}
	return nil
}
