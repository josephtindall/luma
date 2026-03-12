package invitation

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/josephtindall/luma-auth/internal/audit"
	"github.com/josephtindall/luma-auth/internal/authz"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// Handler serves invitation endpoints.
type Handler struct {
	svc      *Service
	baseURL  string // AUTH_BASE_URL — used to build join links, e.g. https://auth.example.com
	authzSvc authz.Authorizer
	audit    audit.Service
}

// NewHandler constructs the invitation handler.
func NewHandler(svc *Service, baseURL string) *Handler {
	return &Handler{svc: svc, baseURL: baseURL}
}

// SetAuthorizer injects the authz evaluator.
func (h *Handler) SetAuthorizer(a authz.Authorizer) { h.authzSvc = a }

// SetAuditor injects the audit service.
func (h *Handler) SetAuditor(a audit.Service) { h.audit = a }

func (h *Handler) requirePerm(w http.ResponseWriter, r *http.Request, action string) bool {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return false
	}
	if claims.Role == "builtin:instance-owner" {
		return true
	}
	if h.authzSvc == nil {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "forbidden")
		return false
	}
	result, err := h.authzSvc.Check(r.Context(), authz.CheckRequest{
		UserID: claims.Subject,
		Action: action,
	})
	if err != nil || !result.Allowed {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "forbidden")
		return false
	}
	return true
}

// Create handles POST /api/auth/invitations.
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "invitation:create") {
		return
	}
	claims := middleware.ClaimsFromContext(r.Context())

	var req struct {
		Email string `json:"email"`
		Note  string `json:"note"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "invalid body")
		return
	}

	rawToken, inv, err := h.svc.Create(r.Context(), CreateParams{
		InviterID: claims.Subject,
		Email:     req.Email,
		Note:      req.Note,
	})
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
		return
	}

	if h.audit != nil {
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: claims.Subject,
			Event:  audit.EventInvitationCreated,
			Metadata: map[string]any{
				"invitation_id": inv.ID,
				"email":         inv.Email,
				"note":          inv.Note,
			},
		})
	}
	// The join URL encodes the raw token — clients show a QR code and copyable link.
	httputil.WriteJSON(w, http.StatusCreated, map[string]any{
		"id":         inv.ID,
		"join_url":   h.baseURL + "/api/auth/join?token=" + rawToken,
		"expires_at": inv.ExpiresAt,
	})
}

// List handles GET /api/auth/invitations.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "invitation:list") {
		return
	}
	invs, err := h.svc.List(r.Context())
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
		return
	}
	httputil.WriteJSON(w, http.StatusOK, invs)
}

// Revoke handles DELETE /api/auth/invitations/{id}.
func (h *Handler) Revoke(w http.ResponseWriter, r *http.Request) {
	if !h.requirePerm(w, r, "invitation:revoke") {
		return
	}
	id := chi.URLParam(r, "id")
	if err := h.svc.Revoke(r.Context(), id); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	if h.audit != nil {
		claims := middleware.ClaimsFromContext(r.Context())
		actorID := ""
		if claims != nil {
			actorID = claims.Subject
		}
		h.audit.WriteAsync(r.Context(), audit.Event{
			UserID: actorID,
			Event:  audit.EventInvitationRevoked,
			Metadata: map[string]any{
				"invitation_id": id,
			},
		})
	}
	w.WriteHeader(http.StatusNoContent)
}

// Join handles GET /api/auth/join — renders the invitation landing page data.
func (h *Handler) Join(w http.ResponseWriter, r *http.Request) {
	rawToken := r.URL.Query().Get("token")
	if rawToken == "" {
		httputil.WriteError(w, http.StatusBadRequest, "BAD_REQUEST", "token required")
		return
	}
	inv, err := h.svc.Validate(r.Context(), rawToken)
	if err != nil {
		// Do not distinguish invalid/expired/revoked — same message always.
		httputil.WriteError(w, http.StatusNotFound, "NOT_FOUND", "invitation not found or expired")
		return
	}
	httputil.WriteJSON(w, http.StatusOK, map[string]any{
		"invitation_id": inv.ID,
		"email":         inv.Email,
		"note":          inv.Note,
	})
}

