package errors

import (
	"errors"
	"net/http"
)

// Sentinel errors returned by the service layer.
// Handlers map these to HTTP status codes via HTTPStatus.
var (
	ErrInvalidCredentials     = errors.New("invalid credentials")      // 401
	ErrAccountLocked          = errors.New("account locked")           // 403
	ErrTokenExpired           = errors.New("token expired")            // 401
	ErrTokenInvalid           = errors.New("token invalid")            // 401
	ErrTokenRevoked           = errors.New("token revoked")            // 401
	ErrTokenReuseDetected     = errors.New("token reuse detected")     // 401 — triggers full revocation
	ErrUserNotFound           = errors.New("user not found")           // 404
	ErrEmailTaken             = errors.New("email taken")              // 409
	ErrPasswordTooShort       = errors.New("password too short")       // 422
	ErrDeviceNotFound         = errors.New("device not found")         // 404
	ErrDeviceRevoked          = errors.New("device revoked")           // 403
	ErrForbidden              = errors.New("forbidden")                // 403
	ErrSetupRequired          = errors.New("setup required")           // 503
	ErrSetupComplete          = errors.New("setup complete")           // 410
	ErrMFARequired            = errors.New("mfa required")             // 200 (not an HTTP error)
	ErrMFATokenInvalid        = errors.New("mfa token invalid")        // 401
	ErrMFACodeInvalid         = errors.New("invalid mfa code")         // 401
	ErrTOTPAlreadySetup       = errors.New("totp already set up")      // 409
	ErrTOTPNotSetup           = errors.New("totp not set up")          // 404
	ErrPasskeyNotFound        = errors.New("passkey not found")        // 404
	ErrTOTPLimitReached       = errors.New("totp app limit reached")   // 409
	ErrPasskeyLimitReached    = errors.New("passkey limit reached")    // 409
	ErrWebAuthnSessionExpired = errors.New("webauthn session expired") // 400
	ErrMFANotEnabled          = errors.New("mfa not enabled")          // 400
	ErrPasswordReused         = errors.New("password was recently used") // 422
	ErrGroupCycle             = errors.New("group cycle detected")       // 409
	ErrGroupNotEmpty          = errors.New("group is not empty")         // 409
)

// HTTPStatus maps a sentinel error to its canonical HTTP status code.
// Returns 500 for unrecognised errors.
func HTTPStatus(err error) int {
	switch {
	case errors.Is(err, ErrInvalidCredentials):
		return http.StatusUnauthorized
	case errors.Is(err, ErrAccountLocked):
		return http.StatusForbidden
	case errors.Is(err, ErrTokenExpired):
		return http.StatusUnauthorized
	case errors.Is(err, ErrTokenInvalid):
		return http.StatusUnauthorized
	case errors.Is(err, ErrTokenRevoked):
		return http.StatusUnauthorized
	case errors.Is(err, ErrTokenReuseDetected):
		return http.StatusUnauthorized
	case errors.Is(err, ErrUserNotFound):
		return http.StatusNotFound
	case errors.Is(err, ErrEmailTaken):
		return http.StatusConflict
	case errors.Is(err, ErrPasswordTooShort):
		return http.StatusUnprocessableEntity
	case errors.Is(err, ErrDeviceNotFound):
		return http.StatusNotFound
	case errors.Is(err, ErrDeviceRevoked):
		return http.StatusForbidden
	case errors.Is(err, ErrForbidden):
		return http.StatusForbidden
	case errors.Is(err, ErrSetupRequired):
		return http.StatusServiceUnavailable
	case errors.Is(err, ErrSetupComplete):
		return http.StatusGone
	case errors.Is(err, ErrMFATokenInvalid):
		return http.StatusUnauthorized
	case errors.Is(err, ErrMFACodeInvalid):
		return http.StatusUnauthorized
	case errors.Is(err, ErrTOTPAlreadySetup):
		return http.StatusConflict
	case errors.Is(err, ErrTOTPNotSetup):
		return http.StatusNotFound
	case errors.Is(err, ErrPasskeyNotFound):
		return http.StatusNotFound
	case errors.Is(err, ErrTOTPLimitReached):
		return http.StatusConflict
	case errors.Is(err, ErrPasskeyLimitReached):
		return http.StatusConflict
	case errors.Is(err, ErrWebAuthnSessionExpired):
		return http.StatusBadRequest
	case errors.Is(err, ErrMFANotEnabled):
		return http.StatusBadRequest
	case errors.Is(err, ErrPasswordReused):
		return http.StatusUnprocessableEntity
	case errors.Is(err, ErrGroupCycle):
		return http.StatusConflict
	case errors.Is(err, ErrGroupNotEmpty):
		return http.StatusConflict
	default:
		return http.StatusInternalServerError
	}
}

// ErrorCode maps a sentinel error to a machine-readable screaming snake case
// code suitable for JSON error responses. Returns "INTERNAL_ERROR" for
// unrecognised errors.
func ErrorCode(err error) string {
	switch {
	case errors.Is(err, ErrInvalidCredentials):
		return "INVALID_CREDENTIALS"
	case errors.Is(err, ErrAccountLocked):
		return "ACCOUNT_LOCKED"
	case errors.Is(err, ErrTokenExpired):
		return "TOKEN_EXPIRED"
	case errors.Is(err, ErrTokenInvalid):
		return "TOKEN_INVALID"
	case errors.Is(err, ErrTokenRevoked):
		return "TOKEN_REVOKED"
	case errors.Is(err, ErrTokenReuseDetected):
		return "TOKEN_REUSE_DETECTED"
	case errors.Is(err, ErrUserNotFound):
		return "USER_NOT_FOUND"
	case errors.Is(err, ErrEmailTaken):
		return "EMAIL_TAKEN"
	case errors.Is(err, ErrPasswordTooShort):
		return "PASSWORD_TOO_SHORT"
	case errors.Is(err, ErrDeviceNotFound):
		return "DEVICE_NOT_FOUND"
	case errors.Is(err, ErrDeviceRevoked):
		return "DEVICE_REVOKED"
	case errors.Is(err, ErrForbidden):
		return "FORBIDDEN"
	case errors.Is(err, ErrSetupRequired):
		return "SETUP_REQUIRED"
	case errors.Is(err, ErrSetupComplete):
		return "SETUP_COMPLETE"
	case errors.Is(err, ErrMFATokenInvalid):
		return "MFA_TOKEN_INVALID"
	case errors.Is(err, ErrMFACodeInvalid):
		return "MFA_CODE_INVALID"
	case errors.Is(err, ErrTOTPAlreadySetup):
		return "TOTP_ALREADY_SETUP"
	case errors.Is(err, ErrTOTPNotSetup):
		return "TOTP_NOT_SETUP"
	case errors.Is(err, ErrPasskeyNotFound):
		return "PASSKEY_NOT_FOUND"
	case errors.Is(err, ErrTOTPLimitReached):
		return "TOTP_LIMIT_REACHED"
	case errors.Is(err, ErrPasskeyLimitReached):
		return "PASSKEY_LIMIT_REACHED"
	case errors.Is(err, ErrWebAuthnSessionExpired):
		return "WEBAUTHN_SESSION_EXPIRED"
	case errors.Is(err, ErrMFANotEnabled):
		return "MFA_NOT_ENABLED"
	case errors.Is(err, ErrPasswordReused):
		return "PASSWORD_REUSED"
	case errors.Is(err, ErrGroupCycle):
		return "GROUP_CYCLE"
	case errors.Is(err, ErrGroupNotEmpty):
		return "GROUP_NOT_EMPTY"
	default:
		return "INTERNAL_ERROR"
	}
}

// ErrorResponse is the JSON envelope for all error responses.
type ErrorResponse struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Is re-exports errors.Is for callers who import only this package.
var Is = errors.Is
