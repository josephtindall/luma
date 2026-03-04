package authz

import (
	"encoding/json"
	"net/http"

	"github.com/josephtindall/luma-auth/internal/audit"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	pkgmiddleware "github.com/josephtindall/luma-auth/pkg/middleware"
)

// Handler serves POST /api/auth/authz/check.
type Handler struct {
	authz Authorizer
	audit audit.Service
}

// NewHandler constructs the authz handler.
func NewHandler(authz Authorizer, auditSvc audit.Service) *Handler {
	return &Handler{authz: authz, audit: auditSvc}
}

// Check handles POST /api/auth/authz/check.
// Called by Luma before every protected action.
func (h *Handler) Check(w http.ResponseWriter, r *http.Request) {
	var req CheckRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}

	result, err := h.authz.Check(r.Context(), req)
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "permission check failed")
		return
	}

	if !result.Allowed {
		claims := pkgmiddleware.ClaimsFromContext(r.Context())
		deviceID := ""
		userID := ""
		if claims != nil {
			userID = claims.Subject
			deviceID = claims.DeviceID
		}
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID:   userID,
			DeviceID: deviceID,
			Event:    audit.EventAuthzDenied,
			Metadata: map[string]any{
				"action":        req.Action,
				"resource_type": req.ResourceType,
				"resource_id":   req.ResourceID,
			},
		})
	}

	httputil.WriteJSON(w, http.StatusOK, result)
}

