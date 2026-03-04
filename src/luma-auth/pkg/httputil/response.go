package httputil

import (
	"encoding/json"
	"net/http"

	pkgerrors "github.com/josephtindall/luma-auth/pkg/errors"
)

// WriteJSON writes v as a JSON response with the given HTTP status code.
func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// WriteError writes a standard error response using pkgerrors.ErrorResponse.
func WriteError(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(pkgerrors.ErrorResponse{Code: code, Message: msg})
}
