package vaults

import (
	"context"
	"fmt"
	"log/slog"

	"github.com/josephtindall/luma/pkg/errors"
)

// EnsurePersonalVault checks whether the user already has a personal vault and
// creates one if not. It handles race conditions gracefully: if two requests
// arrive simultaneously for a new user, only one will succeed and the other
// will see the already-created vault.
func (s *Service) EnsurePersonalVault(ctx context.Context, userID, displayName string) error {
	has, err := s.repo.HasPersonalVault(ctx, userID)
	if err != nil {
		return fmt.Errorf("checking personal vault: %w", err)
	}
	if has {
		return nil
	}

	_, err = s.CreatePersonalVault(ctx, userID, displayName)
	if err != nil {
		// A concurrent request may have created the vault between our check
		// and our insert. Treat already-exists as success.
		if errors.Is(err, errors.ErrAlreadyExists) {
			slog.InfoContext(ctx, "personal vault already created by concurrent request", "user_id", userID)
			return nil
		}
		return fmt.Errorf("creating personal vault: %w", err)
	}

	slog.InfoContext(ctx, "personal vault created", "user_id", userID)
	return nil
}
