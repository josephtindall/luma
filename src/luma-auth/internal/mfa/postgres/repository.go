package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/josephtindall/luma-auth/internal/mfa"
)

// Repository implements mfa.Repository against PostgreSQL.
type Repository struct {
	db *pgxpool.Pool
}

// New constructs the PostgreSQL MFA repository.
func New(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

// ── TOTP ────────────────────────────────────────────────────────────────────

func (r *Repository) CreateTOTPSecret(ctx context.Context, userID, name string, secret []byte) (string, error) {
	const q = `
		INSERT INTO auth.totp_secrets (user_id, name, secret)
		VALUES ($1, $2, $3)
		RETURNING id`

	var id string
	err := r.db.QueryRow(ctx, q, userID, name, secret).Scan(&id)
	if err != nil {
		return "", fmt.Errorf("mfa.postgres.CreateTOTPSecret: %w", err)
	}
	return id, nil
}

func (r *Repository) GetTOTPSecretByID(ctx context.Context, id string) (*mfa.TOTPSecret, error) {
	const q = `
		SELECT id, user_id, name, secret, verified, last_used_counter, created_at
		FROM auth.totp_secrets
		WHERE id = $1`

	s := &mfa.TOTPSecret{}
	err := r.db.QueryRow(ctx, q, id).Scan(&s.ID, &s.UserID, &s.Name, &s.Secret, &s.Verified, &s.LastUsedCounter, &s.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("mfa.postgres.GetTOTPSecretByID: %w", err)
	}
	return s, nil
}

func (r *Repository) ListTOTPSecrets(ctx context.Context, userID string) ([]*mfa.TOTPSecret, error) {
	const q = `
		SELECT id, user_id, name, secret, verified, last_used_counter, created_at
		FROM auth.totp_secrets
		WHERE user_id = $1
		ORDER BY created_at DESC`

	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("mfa.postgres.ListTOTPSecrets: %w", err)
	}
	defer rows.Close()

	var secrets []*mfa.TOTPSecret
	for rows.Next() {
		s := &mfa.TOTPSecret{}
		if err := rows.Scan(&s.ID, &s.UserID, &s.Name, &s.Secret, &s.Verified, &s.LastUsedCounter, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("mfa.postgres.ListTOTPSecrets scan: %w", err)
		}
		secrets = append(secrets, s)
	}
	return secrets, rows.Err()
}

func (r *Repository) ListVerifiedTOTPSecrets(ctx context.Context, userID string) ([]*mfa.TOTPSecret, error) {
	const q = `
		SELECT id, user_id, name, secret, verified, last_used_counter, created_at
		FROM auth.totp_secrets
		WHERE user_id = $1 AND verified = true
		ORDER BY created_at DESC`

	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("mfa.postgres.ListVerifiedTOTPSecrets: %w", err)
	}
	defer rows.Close()

	var secrets []*mfa.TOTPSecret
	for rows.Next() {
		s := &mfa.TOTPSecret{}
		if err := rows.Scan(&s.ID, &s.UserID, &s.Name, &s.Secret, &s.Verified, &s.LastUsedCounter, &s.CreatedAt); err != nil {
			return nil, fmt.Errorf("mfa.postgres.ListVerifiedTOTPSecrets scan: %w", err)
		}
		secrets = append(secrets, s)
	}
	return secrets, rows.Err()
}

func (r *Repository) VerifyTOTPSecret(ctx context.Context, id string) error {
	const q = `UPDATE auth.totp_secrets SET verified = true WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("mfa.postgres.VerifyTOTPSecret: %w", err)
	}
	return nil
}

func (r *Repository) DeleteTOTPSecret(ctx context.Context, id string) error {
	const q = `DELETE FROM auth.totp_secrets WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("mfa.postgres.DeleteTOTPSecret: %w", err)
	}
	return nil
}

func (r *Repository) DeleteUnverifiedTOTPSecrets(ctx context.Context, userID string) error {
	const q = `DELETE FROM auth.totp_secrets WHERE user_id = $1 AND verified = false`
	_, err := r.db.Exec(ctx, q, userID)
	if err != nil {
		return fmt.Errorf("mfa.postgres.DeleteUnverifiedTOTPSecrets: %w", err)
	}
	return nil
}

func (r *Repository) CountVerifiedTOTPSecrets(ctx context.Context, userID string) (int, error) {
	const q = `SELECT COUNT(*) FROM auth.totp_secrets WHERE user_id = $1 AND verified = true`
	var count int
	err := r.db.QueryRow(ctx, q, userID).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("mfa.postgres.CountVerifiedTOTPSecrets: %w", err)
	}
	return count, nil
}

func (r *Repository) UpdateTOTPLastUsedCounter(ctx context.Context, id string, counter int64) error {
	const q = `UPDATE auth.totp_secrets SET last_used_counter = $2 WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id, counter)
	if err != nil {
		return fmt.Errorf("mfa.postgres.UpdateTOTPLastUsedCounter: %w", err)
	}
	return nil
}

// ── MFA Challenges ──────────────────────────────────────────────────────────

func (r *Repository) CreateChallenge(ctx context.Context, userID, deviceID, tokenHash string, expiresAt time.Time) error {
	const q = `
		INSERT INTO auth.mfa_challenges (user_id, device_id, token_hash, expires_at)
		VALUES ($1, $2, $3, $4)`

	_, err := r.db.Exec(ctx, q, userID, deviceID, tokenHash, expiresAt)
	if err != nil {
		return fmt.Errorf("mfa.postgres.CreateChallenge: %w", err)
	}
	return nil
}

func (r *Repository) GetChallengeByHash(ctx context.Context, tokenHash string) (*mfa.MFAChallenge, error) {
	const q = `
		SELECT id, user_id, device_id, token_hash, expires_at, consumed_at, created_at
		FROM auth.mfa_challenges
		WHERE token_hash = $1`

	c := &mfa.MFAChallenge{}
	err := r.db.QueryRow(ctx, q, tokenHash).Scan(
		&c.ID, &c.UserID, &c.DeviceID, &c.TokenHash, &c.ExpiresAt, &c.ConsumedAt, &c.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("mfa.postgres.GetChallengeByHash: %w", err)
	}
	return c, nil
}

func (r *Repository) ConsumeChallenge(ctx context.Context, id string) error {
	const q = `
		UPDATE auth.mfa_challenges SET consumed_at = NOW()
		WHERE id = $1 AND consumed_at IS NULL
		RETURNING id`

	var consumed string
	err := r.db.QueryRow(ctx, q, id).Scan(&consumed)
	if errors.Is(err, pgx.ErrNoRows) {
		return fmt.Errorf("mfa.postgres.ConsumeChallenge: already consumed")
	}
	if err != nil {
		return fmt.Errorf("mfa.postgres.ConsumeChallenge: %w", err)
	}
	return nil
}

// ── Passkeys ────────────────────────────────────────────────────────────────

func (r *Repository) CreatePasskey(ctx context.Context, p *mfa.Passkey) error {
	const q = `
		INSERT INTO auth.passkeys (user_id, credential_id, public_key, sign_count, name, aaguid, transports, backup_eligible, backup_state)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`

	_, err := r.db.Exec(ctx, q,
		p.UserID, p.CredentialID, p.PublicKey, p.SignCount, p.Name, p.AAGUID, p.Transports,
		p.BackupEligible, p.BackupState)
	if err != nil {
		return fmt.Errorf("mfa.postgres.CreatePasskey: %w", err)
	}
	return nil
}

func (r *Repository) GetPasskeyByCredentialID(ctx context.Context, credentialID []byte) (*mfa.Passkey, error) {
	const q = `
		SELECT id, user_id, credential_id, public_key, sign_count, name,
		       aaguid, transports, backup_eligible, backup_state,
		       last_used_at, revoked_at, created_at
		FROM auth.passkeys
		WHERE credential_id = $1 AND revoked_at IS NULL`

	p, err := scanPasskey(r.db.QueryRow(ctx, q, credentialID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("mfa.postgres.GetPasskeyByCredentialID: %w", err)
	}
	return p, nil
}

func (r *Repository) ListPasskeysForUser(ctx context.Context, userID string) ([]*mfa.Passkey, error) {
	const q = `
		SELECT id, user_id, credential_id, public_key, sign_count, name,
		       aaguid, transports, backup_eligible, backup_state,
		       last_used_at, revoked_at, created_at
		FROM auth.passkeys
		WHERE user_id = $1 AND revoked_at IS NULL
		ORDER BY created_at DESC`

	rows, err := r.db.Query(ctx, q, userID)
	if err != nil {
		return nil, fmt.Errorf("mfa.postgres.ListPasskeysForUser: %w", err)
	}
	defer rows.Close()

	var passkeys []*mfa.Passkey
	for rows.Next() {
		p, err := scanPasskey(rows)
		if err != nil {
			return nil, fmt.Errorf("mfa.postgres.ListPasskeysForUser scan: %w", err)
		}
		passkeys = append(passkeys, p)
	}
	return passkeys, rows.Err()
}

func (r *Repository) UpdatePasskeySignCount(ctx context.Context, id string, signCount int64) error {
	const q = `UPDATE auth.passkeys SET sign_count = $2, last_used_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id, signCount)
	if err != nil {
		return fmt.Errorf("mfa.postgres.UpdatePasskeySignCount: %w", err)
	}
	return nil
}

func (r *Repository) RevokePasskey(ctx context.Context, id string) error {
	const q = `UPDATE auth.passkeys SET revoked_at = NOW() WHERE id = $1`
	_, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("mfa.postgres.RevokePasskey: %w", err)
	}
	return nil
}

func (r *Repository) GetPasskeyByID(ctx context.Context, id string) (*mfa.Passkey, error) {
	const q = `
		SELECT id, user_id, credential_id, public_key, sign_count, name,
		       aaguid, transports, backup_eligible, backup_state,
		       last_used_at, revoked_at, created_at
		FROM auth.passkeys
		WHERE id = $1`

	p, err := scanPasskey(r.db.QueryRow(ctx, q, id))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("mfa.postgres.GetPasskeyByID: %w", err)
	}
	return p, nil
}

func (r *Repository) CountActivePasskeys(ctx context.Context, userID string) (int, error) {
	const q = `SELECT COUNT(*) FROM auth.passkeys WHERE user_id = $1 AND revoked_at IS NULL`
	var count int
	err := r.db.QueryRow(ctx, q, userID).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("mfa.postgres.CountActivePasskeys: %w", err)
	}
	return count, nil
}

func scanPasskey(row pgx.Row) (*mfa.Passkey, error) {
	p := &mfa.Passkey{}
	err := row.Scan(
		&p.ID, &p.UserID, &p.CredentialID, &p.PublicKey, &p.SignCount, &p.Name,
		&p.AAGUID, &p.Transports, &p.BackupEligible, &p.BackupState,
		&p.LastUsedAt, &p.RevokedAt, &p.CreatedAt,
	)
	return p, err
}

// ── Recovery Codes ──────────────────────────────────────────────────────────

func (r *Repository) ReplaceRecoveryCodes(ctx context.Context, userID string, codeHashes []string) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("mfa.postgres.ReplaceRecoveryCodes begin: %w", err)
	}
	defer tx.Rollback(ctx)

	// Delete existing unused codes
	_, err = tx.Exec(ctx, `DELETE FROM auth.recovery_codes WHERE user_id = $1 AND used_at IS NULL`, userID)
	if err != nil {
		return fmt.Errorf("mfa.postgres.ReplaceRecoveryCodes delete: %w", err)
	}

	// Insert new codes (using pgx.CopyFrom for efficiency, or just simple inserts since it's only 8 items)
	// For simplicity, we'll use a loop of Execs, as the batch is small.
	const insertQ = `INSERT INTO auth.recovery_codes (user_id, code_hash) VALUES ($1, $2)`
	for _, hash := range codeHashes {
		if _, err := tx.Exec(ctx, insertQ, userID, hash); err != nil {
			return fmt.Errorf("mfa.postgres.ReplaceRecoveryCodes insert: %w", err)
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("mfa.postgres.ReplaceRecoveryCodes commit: %w", err)
	}
	return nil
}

func (r *Repository) GetRecoveryCodeByHash(ctx context.Context, userID, codeHash string) (*mfa.RecoveryCode, error) {
	const q = `
		SELECT id, user_id, code_hash, used_at, created_at
		FROM auth.recovery_codes
		WHERE user_id = $1 AND code_hash = $2`

	var code mfa.RecoveryCode
	err := r.db.QueryRow(ctx, q, userID, codeHash).Scan(
		&code.ID, &code.UserID, &code.CodeHash, &code.UsedAt, &code.CreatedAt,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil // Not an error, just not found
	}
	if err != nil {
		return nil, fmt.Errorf("mfa.postgres.GetRecoveryCodeByHash: %w", err)
	}
	return &code, nil
}

func (r *Repository) ConsumeRecoveryCode(ctx context.Context, id string) error {
	const q = `UPDATE auth.recovery_codes SET used_at = NOW() WHERE id = $1 AND used_at IS NULL`
	cmd, err := r.db.Exec(ctx, q, id)
	if err != nil {
		return fmt.Errorf("mfa.postgres.ConsumeRecoveryCode: %w", err)
	}
	if cmd.RowsAffected() == 0 {
		return errors.New("mfa.postgres.ConsumeRecoveryCode: already used or not found")
	}
	return nil
}

func (r *Repository) CountUnusedRecoveryCodes(ctx context.Context, userID string) (int, error) {
	const q = `SELECT COUNT(*) FROM auth.recovery_codes WHERE user_id = $1 AND used_at IS NULL`
	var count int
	if err := r.db.QueryRow(ctx, q, userID).Scan(&count); err != nil {
		return 0, fmt.Errorf("mfa.postgres.CountUnusedRecoveryCodes: %w", err)
	}
	return count, nil
}

// ensure we implement the interface.
var _ mfa.Repository = (*Repository)(nil)
