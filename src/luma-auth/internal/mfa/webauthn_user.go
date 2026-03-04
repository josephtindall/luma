package mfa

import (
	"github.com/go-webauthn/webauthn/protocol"
	"github.com/go-webauthn/webauthn/webauthn"

	"github.com/josephtindall/luma-auth/internal/user"
)

// webAuthnUser wraps a User and their passkeys to satisfy webauthn.User.
type webAuthnUser struct {
	u        *user.User
	passkeys []*Passkey
}

func (w *webAuthnUser) WebAuthnID() []byte {
	return []byte(w.u.ID)
}

func (w *webAuthnUser) WebAuthnName() string {
	return w.u.Email
}

func (w *webAuthnUser) WebAuthnDisplayName() string {
	return w.u.DisplayName
}

func (w *webAuthnUser) WebAuthnCredentials() []webauthn.Credential {
	creds := make([]webauthn.Credential, 0, len(w.passkeys))
	for _, p := range w.passkeys {
		transports := make([]protocol.AuthenticatorTransport, 0, len(p.Transports))
		for _, t := range p.Transports {
			transports = append(transports, protocol.AuthenticatorTransport(t))
		}
		creds = append(creds, webauthn.Credential{
			ID:        p.CredentialID,
			PublicKey: p.PublicKey,
			Transport: transports,
			Authenticator: webauthn.Authenticator{
				AAGUID:    p.AAGUID,
				SignCount: uint32(p.SignCount),
			},
		})
	}
	return creds
}

// Compile-time check.
var _ webauthn.User = (*webAuthnUser)(nil)
