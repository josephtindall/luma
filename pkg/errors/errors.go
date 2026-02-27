package errors

import "errors"

// Sentinel errors used across the codebase. Handlers map these to HTTP status codes.
var (
	ErrNotFound      = errors.New("not found")
	ErrAlreadyExists = errors.New("already exists")
	ErrForbidden     = errors.New("forbidden")
	ErrUnauthorized  = errors.New("unauthorized")
	ErrValidation    = errors.New("validation error")
	ErrConflict      = errors.New("conflict")
	ErrArchived      = errors.New("resource is archived")
	ErrShortIDExhausted = errors.New("short id generation exhausted after max attempts")
)

// Is is a convenience re-export of errors.Is.
func Is(err, target error) bool {
	return errors.Is(err, target)
}

// As is a convenience re-export of errors.As.
func As(err error, target any) bool {
	return errors.As(err, target)
}
