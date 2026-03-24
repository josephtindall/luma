package auth

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"

	"github.com/josephtindall/luma/pkg/authz"
)

// Identity represents the authenticated user returned by the auth service's /validate endpoint.
type Identity struct {
	UserID       string `json:"user_id"`
	Role         string `json:"role"`
	DeviceID     string `json:"device_id"`
	InstanceRole string `json:"instance_role"`
}

// User represents user display info returned by the auth service's /users/{id} endpoint.
type User struct {
	ID          string `json:"id"`
	Email       string `json:"email"`
	DisplayName string `json:"display_name"`
	AvatarSeed  string `json:"avatar_seed"`
}

// checkResponse is the response from the auth service's /authz/check endpoint.
type checkResponse struct {
	Allowed bool   `json:"allowed"`
	Reason  string `json:"reason,omitempty"`
}

// Client is an HTTP client for all auth service API calls.
type Client struct {
	baseURL    string
	httpClient *http.Client
}

// NewClient creates a new auth service API client.
func NewClient(baseURL string) *Client {
	return &Client{
		baseURL: baseURL,
		httpClient: &http.Client{
			Timeout: 10 * time.Second,
		},
	}
}

// ValidateToken calls GET /api/auth/validate with the Bearer token.
func (c *Client) ValidateToken(ctx context.Context, token string) (*Identity, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/auth/validate", nil)
	if err != nil {
		return nil, fmt.Errorf("auth: creating validate request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: validate request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("auth: validate returned %d", resp.StatusCode)
	}

	var identity Identity
	if err := json.NewDecoder(resp.Body).Decode(&identity); err != nil {
		return nil, fmt.Errorf("auth: decoding validate response: %w", err)
	}
	return &identity, nil
}

// CheckPermission calls POST /api/auth/authz/check.
func (c *Client) CheckPermission(ctx context.Context, check authz.CheckRequest) (bool, error) {
	body, err := json.Marshal(check)
	if err != nil {
		return false, fmt.Errorf("auth: marshaling check request: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/api/auth/authz/check", bytes.NewReader(body))
	if err != nil {
		return false, fmt.Errorf("auth: creating check request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	// Forward the caller's auth token so the auth service can verify the request is legitimate.
	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return false, fmt.Errorf("auth: check request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return false, fmt.Errorf("auth: check returned %d", resp.StatusCode)
	}

	var result checkResponse
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		return false, fmt.Errorf("auth: decoding check response: %w", err)
	}
	return result.Allowed, nil
}

// SearchDirectoryUsers calls GET /api/auth/directory/users?search= — available
// to all authenticated users, returns non-hidden/non-locked users only.
func (c *Client) SearchDirectoryUsers(ctx context.Context, search string) ([]*User, error) {
	u := c.baseURL + "/api/auth/directory/users"
	if search != "" {
		u += "?search=" + url.QueryEscape(search)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: creating search directory users request: %w", err)
	}
	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: search directory users request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return []*User{}, nil
	}
	var users []*User
	if err := json.NewDecoder(resp.Body).Decode(&users); err != nil {
		return []*User{}, nil
	}
	return users, nil
}

// SearchDirectoryGroups calls GET /api/auth/directory/groups?search= — available
// to all authenticated users, returns non-hidden groups only.
func (c *Client) SearchDirectoryGroups(ctx context.Context, search string) ([]*Group, error) {
	u := c.baseURL + "/api/auth/directory/groups"
	if search != "" {
		u += "?search=" + url.QueryEscape(search)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: creating search directory groups request: %w", err)
	}
	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: search directory groups request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return []*Group{}, nil
	}
	var groups []*Group
	if err := json.NewDecoder(resp.Body).Decode(&groups); err != nil {
		return []*Group{}, nil
	}
	return groups, nil
}

// ListUsers calls GET /api/auth/admin/users with an optional search query.
// Returns an empty slice (no error) when the response is non-200 so callers
// can degrade gracefully without surfacing auth errors to end-users.
func (c *Client) ListUsers(ctx context.Context, search string) ([]*User, error) {
	u := c.baseURL + "/api/auth/admin/users"
	if search != "" {
		u += "?search=" + search
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: creating list users request: %w", err)
	}

	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: list users request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		// Non-200 means the caller lacks admin access — return empty, not an error.
		return []*User{}, nil
	}

	// luma-auth may wrap the list under {"users":[...]} or return a bare array.
	var raw json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return nil, fmt.Errorf("auth: decoding list users response: %w", err)
	}
	// Try bare array first.
	var users []*User
	if err := json.Unmarshal(raw, &users); err == nil {
		return users, nil
	}
	// Try {"users":[...]} wrapper.
	var wrapped struct {
		Users []*User `json:"users"`
	}
	if err := json.Unmarshal(raw, &wrapped); err == nil {
		return wrapped.Users, nil
	}
	return []*User{}, nil
}

// GetUserGroups calls GET /api/auth/users/{id}/groups to resolve the group IDs
// a user belongs to (direct + nested). Returns empty slice on non-200 responses.
func (c *Client) GetUserGroups(ctx context.Context, userID string) ([]string, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/auth/users/"+userID+"/groups", nil)
	if err != nil {
		return nil, fmt.Errorf("auth: creating get user groups request: %w", err)
	}
	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: get user groups request: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return []string{}, nil
	}
	var body struct {
		GroupIDs []string `json:"group_ids"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return []string{}, nil
	}
	return body.GroupIDs, nil
}

// GetUser calls GET /api/auth/users/{id} to resolve user display info.
func (c *Client) GetUser(ctx context.Context, userID string) (*User, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/auth/users/"+userID, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: creating get user request: %w", err)
	}

	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: get user request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("auth: get user returned %d", resp.StatusCode)
	}

	var user User
	if err := json.NewDecoder(resp.Body).Decode(&user); err != nil {
		return nil, fmt.Errorf("auth: decoding user response: %w", err)
	}
	return &user, nil
}

// Group represents a group returned by the auth service.
type Group struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Description string `json:"description,omitempty"`
}

// GetGroup calls GET /api/auth/admin/groups/{id} to resolve group display info.
func (c *Client) GetGroup(ctx context.Context, groupID string) (*Group, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.baseURL+"/api/auth/admin/groups/"+groupID, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: creating get group request: %w", err)
	}

	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: get group request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("auth: get group returned %d", resp.StatusCode)
	}

	var group Group
	if err := json.NewDecoder(resp.Body).Decode(&group); err != nil {
		return nil, fmt.Errorf("auth: decoding group response: %w", err)
	}
	return &group, nil
}

// AuditEvent is the payload for writing an audit event via the auth service.
type AuditEvent struct {
	Event     string         `json:"event"`
	UserID    string         `json:"user_id,omitempty"`
	Metadata  map[string]any `json:"metadata,omitempty"`
	IPAddress string         `json:"ip_address,omitempty"`
	UserAgent string         `json:"user_agent,omitempty"`
}

// WriteAudit calls POST /api/auth/audit/write to record an audit event.
// Errors are logged but not returned — audit should not block operations.
func (c *Client) WriteAudit(ctx context.Context, e AuditEvent) {
	body, err := json.Marshal(e)
	if err != nil {
		return
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/api/auth/audit/write", bytes.NewReader(body))
	if err != nil {
		return
	}
	req.Header.Set("Content-Type", "application/json")
	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return
	}
	resp.Body.Close()
}

// ListGroups calls GET /api/auth/admin/groups with an optional search query.
// Returns an empty slice (no error) when the response is non-200 so callers
// can degrade gracefully without surfacing auth errors to end-users.
func (c *Client) ListGroups(ctx context.Context, search string) ([]*Group, error) {
	u := c.baseURL + "/api/auth/admin/groups"
	if search != "" {
		u += "?search=" + url.QueryEscape(search)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, fmt.Errorf("auth: creating list groups request: %w", err)
	}

	if token := tokenFromContext(ctx); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("auth: list groups request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return []*Group{}, nil
	}

	var raw json.RawMessage
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return []*Group{}, nil
	}
	var groups []*Group
	if err := json.Unmarshal(raw, &groups); err == nil {
		return groups, nil
	}
	var wrapped struct {
		Groups []*Group `json:"groups"`
	}
	if err := json.Unmarshal(raw, &wrapped); err == nil {
		return wrapped.Groups, nil
	}
	return []*Group{}, nil
}
