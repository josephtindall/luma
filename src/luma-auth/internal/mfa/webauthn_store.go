package mfa

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	"github.com/go-webauthn/webauthn/webauthn"
	"github.com/redis/go-redis/v9"
)

const webauthnSessionTTL = 5 * time.Minute

// WebAuthnSessionStore persists WebAuthn ceremony session data in Redis.
type WebAuthnSessionStore struct {
	rdb *redis.Client
}

// NewWebAuthnSessionStore constructs the store.
func NewWebAuthnSessionStore(rdb *redis.Client) *WebAuthnSessionStore {
	return &WebAuthnSessionStore{rdb: rdb}
}

func (s *WebAuthnSessionStore) Save(ctx context.Context, key string, data *webauthn.SessionData) error {
	b, err := json.Marshal(data)
	if err != nil {
		return fmt.Errorf("webauthn session store: marshal: %w", err)
	}
	if err := s.rdb.Set(ctx, key, b, webauthnSessionTTL).Err(); err != nil {
		return fmt.Errorf("webauthn session store: set: %w", err)
	}
	return nil
}

func (s *WebAuthnSessionStore) Get(ctx context.Context, key string) (*webauthn.SessionData, error) {
	b, err := s.rdb.Get(ctx, key).Bytes()
	if err != nil {
		return nil, fmt.Errorf("webauthn session store: get: %w", err)
	}

	var data webauthn.SessionData
	if err := json.Unmarshal(b, &data); err != nil {
		return nil, fmt.Errorf("webauthn session store: unmarshal: %w", err)
	}
	return &data, nil
}

func (s *WebAuthnSessionStore) Delete(ctx context.Context, key string) error {
	if err := s.rdb.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("webauthn session store: delete: %w", err)
	}
	return nil
}

func (s *WebAuthnSessionStore) SaveName(ctx context.Context, key, name string) error {
	if err := s.rdb.Set(ctx, key, name, webauthnSessionTTL).Err(); err != nil {
		return fmt.Errorf("webauthn session store: save name: %w", err)
	}
	return nil
}

func (s *WebAuthnSessionStore) GetName(ctx context.Context, key string) (string, error) {
	name, err := s.rdb.Get(ctx, key).Result()
	if err != nil {
		return "", fmt.Errorf("webauthn session store: get name: %w", err)
	}
	return name, nil
}

// Registration session keys.
func regSessionKey(userID string) string {
	return "webauthn_reg:" + userID
}

// Login session keys.
func loginSessionKey(userID string) string {
	return "webauthn_login:" + userID
}

// regNameKey stores the passkey nickname alongside the registration session.
func regNameKey(userID string) string {
	return "webauthn_reg_name:" + userID
}
