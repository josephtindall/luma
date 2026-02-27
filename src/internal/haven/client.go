package haven

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/josephtindall/luma/pkg/authz"
)

// Identity represents the authenticated user returned by Haven's /validate endpoint.
type Identity struct {
	UserID       string `json:"user_id"`
	Role         string `json:"role"`
	DeviceID     string `json:"device_id"`
	InstanceRole string `json:"instance_role"`
}

// User represents user display info returned by Haven's /users/{id} endpoint.
type User struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	AvatarSeed  string `json:"avatar_seed"`
}

// checkResponse is the response from Haven's /authz/check endpoint.
type checkResponse struct {
	Allowed bool   `json:"allowed"`
	Reason  string `json:"reason,omitempty"`
}

// Client is an HTTP client for all Haven API calls.
type Client struct {
	baseURL    string
	httpClient *http.Client
}

// NewClient creates a new Haven API client.
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// ValidateToken calls GET /api/haven/validate with the Bearer token.
func (c *Client) ValidateToken(ctx context.Context, token string) (*Identity, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/haven/validate", nil)
	if err != nil {
		return nil, fmt.Errorf("haven: creating validate request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("haven: validate request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("haven: validate returned %d", resp.StatusCode)
	}

	var identity Identity
	if err := json.NewDecoder(resp.Body).Decode(&identity); err != nil {
		return nil, fmt.Errorf("haven: decoding validate response: %w", err)
	}
	return &identity, nil
}

// CheckPermission calls POST /api/haven/authz/check.
func (c *Client) CheckPermission(ctx context.Context, check authz.CheckRequest) (bool, error) {
	body, err := json.Marshal(check)
	if err != nil {
		return false, fmt.Errorf("haven: marshaling check request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/api/haven/authz/check", bytes.NewReader(body))
	if err != nil {
		return false, fmt.Errorf("haven: creating check request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// Forward the caller's auth token so Haven can verify the request is legitimate.
	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("haven: check request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("haven: check returned %d", resp.StatusCode)
	}

	var result checkResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return false, fmt.Errorf("haven: decoding check response: %w", err)
	}
	return result.Allowed, nil
}

// GetUser calls GET /api/haven/users/{id} to resolve user display info.
func (c *Client) GetUser(ctx context.Context, userID string) (*User, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/haven/users/"+userID, nil)
	if err != nil {
		return nil, fmt.Errorf("haven: creating get user request: %w", err)
	}

	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("haven: get user request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("haven: get user returned %d", resp.StatusCode)
	}

	var user User
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return nil, fmt.Errorf("haven: decoding user response: %w", err)
	}
	return &user, nil
}
