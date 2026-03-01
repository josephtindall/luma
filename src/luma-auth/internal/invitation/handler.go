package invitation

import (
	"encoding/json"
	"net/http"

	"github.com/go-chi/chi/v5"
	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
	"github.com/josephtindall/luma-auth/pkg/httputil"
	"github.com/josephtindall/luma-auth/pkg/middleware"
)

// Handler serves invitation endpoints.
type Handler struct {
	svc     *Service
	baseURL string // HAVEN_BASE_URL — used to build join links, e.g. https://haven.example.com
}

// NewHandler constructs the invitation handler.
func NewHandler(svc *Service, baseURL string) *Handler {
	return &Handler{svc: svc, baseURL: baseURL}
}

// Create handles POST /api/haven/invitations — owner only.
func (h *Handler) Create(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}

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
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}

	// The join URL encodes the raw token — clients show a QR code and copyable link.
	httputil.WriteJSON(w, http.StatusCreated, map[string]any{
		"id":         inv.ID,
		"join_url":   h.baseURL + "/api/haven/join?token=" + rawToken,
		"expires_at": inv.ExpiresAt,
	})
}

// List handles GET /api/haven/invitations — owner only.
func (h *Handler) List(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}
	invs, err := h.svc.List(r.Context())
	if err != nil {
		httputil.WriteError(w, http.StatusInternalServerError, "INTERNAL_ERROR", err.Error())
		return
	}
	httputil.WriteJSON(w, http.StatusOK, invs)
}

// Revoke handles DELETE /api/haven/invitations/{id} — owner only.
func (h *Handler) Revoke(w http.ResponseWriter, r *http.Request) {
	claims := middleware.ClaimsFromContext(r.Context())
	if claims == nil {
		httputil.WriteError(w, http.StatusUnauthorized, "UNAUTHORIZED", "unauthorized")
		return
	}
	if claims.Role != "builtin:instance-owner" {
		httputil.WriteError(w, http.StatusForbidden, "FORBIDDEN", "owner role required")
		return
	}
	id := chi.URLParam(r, "id")
	if err := h.svc.Revoke(r.Context(), id); err != nil {
		httputil.WriteError(w, pkgerrors.HTTPStatus(err), pkgerrors.ErrorCode(err), err.Error())
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// Join handles GET /api/haven/join — renders the invitation landing page data.
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

