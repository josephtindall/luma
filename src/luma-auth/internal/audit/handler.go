package audit

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// PermChecker reports whether userID has permission to perform action.
// Defined as a function type to avoid a circular import: authz already imports audit.
type PermChecker func(ctx context.Context, userID, action string) (bool, error)

// Handler serves the audit log HTTP endpoints.
type Handler struct {
	repo  Repository
	canDo PermChecker // may be nil — falls back to owner-only check via claims.Role
}

// NewHandler constructs an audit Handler.
// canDo may be nil; if nil, All() falls back to the "builtin:instance-owner" role check.
func NewHandler(repo Repository, canDo PermChecker) *Handler {
	return &Handler{repo: repo, canDo: canDo}
}

// Me handles GET /api/auth/audit/me — returns the caller's own audit events.
func (h *Handler) Me(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	q := parseQuery(r, 10)
	page, err := h.repo.ListForUser(r.Context(), claims.Subject, q)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to load audit log")
		return
	}

	canViewPII := claims.Role == "builtin:instance-owner"
	if !canViewPII && h.canDo != nil {
		canViewPII, _ = h.canDo(r.Context(), claims.Subject, "audit:read-pii")
	}

	httputil.WriteJSON(w, http.StatusOK, pageResponse(page, q, canViewPII))
}

// All handles GET /api/auth/audit — returns the global audit log.
// Requires the audit:read-all permission (or instance-owner role).
func (h *Handler) All(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	allowed := claims.Role == "builtin:instance-owner"
	if !allowed && h.canDo != nil {
		var err error
		allowed, err = h.canDo(r.Context(), claims.Subject, "audit:read-all")
		if err != nil {
			httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "permission check failed")
			return
		}
	}
	if !allowed {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "audit:read-all required")
		return
	}

	q := parseQuery(r, 30)
	page, err := h.repo.ListAll(r.Context(), q)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to load audit log")
		return
	}

	canViewPII := claims.Role == "builtin:instance-owner"
	if !canViewPII && h.canDo != nil {
		canViewPII, _ = h.canDo(r.Context(), claims.Subject, "audit:read-pii")
	}

	httputil.WriteJSON(w, http.StatusOK, pageResponse(page, q, canViewPII))
}

// Write handles POST /api/auth/audit/write — accepts an audit event from
// trusted internal services (e.g. luma). The caller must be authenticated and
// have audit:read-all permission (i.e. an admin).
func (h *Handler) Write(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}

	var body struct {
		Event     string         `json:"event"`
		UserID    string         `json:"user_id"`
		Metadata  map[string]any `json:"metadata"`
		IPAddress string         `json:"ip_address"`
		UserAgent string         `json:"user_agent"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid request body")
		return
	}
	if body.Event == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "event is required")
		return
	}

	userID := body.UserID
	if userID == "" {
		userID = claims.Subject
	}

	if err := h.repo.Insert(r.Context(), Event{
		UserID:    userID,
		Event:     body.Event,
		IPAddress: body.IPAddress,
		UserAgent: body.UserAgent,
		Metadata:  body.Metadata,
	}); err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "failed to write audit event")
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// parseQuery reads filter + pagination params from the request.
func parseQuery(r *http.Request, defaultLimit int) AuditQuery {
	q := AuditQuery{
		Limit:       defaultLimit,
		Search:      r.URL.Query().Get("search"),
		EventFilter: r.URL.Query().Get("event"),
		Exclude:     r.URL.Query().Get("exclude"),
	}

	if v := r.URL.Query().Get("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			if n > 100 {
				n = 100
			}
			q.Limit = n
		}
	}
	if v := r.URL.Query().Get("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			if n > 100_000 {
				n = 100_000
			}
			q.Offset = n
		}
	}
	if v := r.URL.Query().Get("after"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			q.After = &t
		}
	}
	if v := r.URL.Query().Get("before"); v != "" {
		if t, err := time.Parse(time.RFC3339, v); err == nil {
			q.Before = &t
		}
	}

	return q
}

// eventJSON is the JSON shape emitted for each audit row.
type eventJSON struct {
	ID              int64          `json:"id"`
	UserID          *string        `json:"user_id,omitempty"`
	UserEmail       *string        `json:"user_email,omitempty"`
	UserDisplayName *string        `json:"user_display_name,omitempty"`
	DeviceID        *string        `json:"device_id,omitempty"`
	Event           string         `json:"event"`
	IPAddress       *string        `json:"ip_address,omitempty"`
	UserAgent       *string        `json:"user_agent,omitempty"`
	Metadata        map[string]any `json:"metadata,omitempty"`
	OccurredAt      time.Time      `json:"occurred_at"`
}

func rowToJSON(row *Row) eventJSON {
	return eventJSON{
		ID:              row.ID,
		UserID:          row.UserID,
		UserEmail:       row.UserEmail,
		UserDisplayName: row.UserDisplayName,
		DeviceID:        row.DeviceID,
		Event:           row.Event,
		IPAddress:       row.IPAddress,
		UserAgent:       row.UserAgent,
		Metadata:        row.Metadata,
		OccurredAt:      row.OccurredAt,
	}
}

type pageJSON struct {
	Events []eventJSON `json:"events"`
	Total  int         `json:"total"`
	Limit  int         `json:"limit"`
	Offset int         `json:"offset"`
}

func pageResponse(page *Page, q AuditQuery, canViewPII bool) pageJSON {
	events := make([]eventJSON, len(page.Rows))
	for i, r := range page.Rows {
		ej := rowToJSON(r)
		if !canViewPII {
			ej.IPAddress = nil
			ej.UserEmail = nil
		}
		events[i] = ej
	}
	return pageJSON{
		Events: events,
		Total:  page.Total,
		Limit:  q.Limit,
		Offset: q.Offset,
	}
}
