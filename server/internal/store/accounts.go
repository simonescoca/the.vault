package store

import (
	"context"
	"database/sql"
	"errors"
)

// Device status values.
const (
	StatusSetup   = "setup"
	StatusPending = "pending"
	StatusActive  = "active"
)

type User struct {
	ID                   string
	Email                string
	CreatedAt            int64
	VaultInitialized     bool
	KeyCheck             []byte
	RecoverySalt         []byte
	RecoveryOps          int64
	RecoveryMem          int64
	RecoveryWrap         []byte
	RecoveryAuthHash     []byte
	Rev                  int64
	ApprovalsPausedUntil int64
}

type Device struct {
	ID          string
	UserID      string
	Name        string
	Platform    string
	PublicKey   []byte
	Status      string
	CreatedAt   int64
	LastSeenAt  int64
	ActivatedAt sql.NullInt64
}

const userCols = `id, email, created_at, vault_initialized, key_check, recovery_salt, recovery_ops, recovery_mem,
  recovery_wrap, recovery_auth_hash, rev, approvals_paused_until`

type scanner interface{ Scan(dest ...any) error }

func scanUser(r scanner) (*User, error) {
	var u User
	var ops, mem sql.NullInt64
	err := r.Scan(&u.ID, &u.Email, &u.CreatedAt, &u.VaultInitialized, &u.KeyCheck, &u.RecoverySalt, &ops, &mem,
		&u.RecoveryWrap, &u.RecoveryAuthHash, &u.Rev, &u.ApprovalsPausedUntil)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	u.RecoveryOps, u.RecoveryMem = ops.Int64, mem.Int64
	return &u, nil
}

func (s *Store) UserByEmail(ctx context.Context, email string) (*User, error) {
	return scanUser(s.DB.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE email = ?`, email))
}

func (s *Store) User(ctx context.Context, id string) (*User, error) {
	return scanUser(s.DB.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE id = ?`, id))
}

// EnsureUser returns the user with this email, creating it if needed.
func (s *Store) EnsureUser(ctx context.Context, id, email string) (*User, error) {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO users(id, email, created_at) VALUES (?, ?, ?) ON CONFLICT(email) DO NOTHING`,
		id, email, NowMillis())
	if err != nil {
		return nil, err
	}
	return s.UserByEmail(ctx, email)
}

// Recovery is the emergency-kit bundle: the vault key wrapped with a key derived from the recovery code.
type Recovery struct {
	Salt     []byte
	OpsLimit int64
	MemLimit int64
	Wrap     []byte
	AuthHash []byte
}

var ErrAlreadyInitialized = errors.New("vault already initialized")

// InitVault stores the key check and the recovery bundle and activates the device, atomically.
// It fails with ErrAlreadyInitialized if another device initialized the vault first; in that case
// the calling device is moved to pending.
func (s *Store) InitVault(ctx context.Context, userID, deviceID string, keyCheck []byte, r Recovery) error {
	errInit := ErrAlreadyInitialized
	err := s.Tx(ctx, func(tx *sql.Tx) error {
		var initialized bool
		if err := tx.QueryRowContext(ctx, `SELECT vault_initialized FROM users WHERE id = ?`, userID).Scan(&initialized); err != nil {
			return err
		}
		if initialized {
			_, err := tx.ExecContext(ctx, `UPDATE devices SET status = ? WHERE id = ? AND status = ?`, StatusPending, deviceID, StatusSetup)
			if err != nil {
				return err
			}
			return nil
		}
		errInit = nil
		if _, err := tx.ExecContext(ctx, `UPDATE users SET vault_initialized = 1, key_check = ?, recovery_salt = ?, recovery_ops = ?,
		  recovery_mem = ?, recovery_wrap = ?, recovery_auth_hash = ? WHERE id = ?`,
			keyCheck, r.Salt, r.OpsLimit, r.MemLimit, r.Wrap, r.AuthHash, userID); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `UPDATE devices SET status = ?, activated_at = ? WHERE id = ?`, StatusActive, NowMillis(), deviceID)
		return err
	})
	if err != nil {
		return err
	}
	return errInit
}

func (s *Store) SetRecovery(ctx context.Context, userID string, r Recovery) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE users SET recovery_salt = ?, recovery_ops = ?, recovery_mem = ?, recovery_wrap = ?,
	  recovery_auth_hash = ? WHERE id = ?`, r.Salt, r.OpsLimit, r.MemLimit, r.Wrap, r.AuthHash, userID)
	return err
}

func (s *Store) SetApprovalsPausedUntil(ctx context.Context, userID string, until int64) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE users SET approvals_paused_until = ? WHERE id = ?`, until, userID)
	return err
}

// --- devices ---

const deviceCols = `id, user_id, name, platform, public_key, status, created_at, last_seen_at, activated_at`

func scanDevice(r scanner) (*Device, error) {
	var d Device
	err := r.Scan(&d.ID, &d.UserID, &d.Name, &d.Platform, &d.PublicKey, &d.Status, &d.CreatedAt, &d.LastSeenAt, &d.ActivatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &d, nil
}

func (s *Store) CreateDevice(ctx context.Context, d *Device, tokenHash []byte) error {
	now := NowMillis()
	d.CreatedAt, d.LastSeenAt = now, now
	_, err := s.DB.ExecContext(ctx, `INSERT INTO devices(id, user_id, name, platform, public_key, token_hash, status, created_at, last_seen_at)
	  VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`, d.ID, d.UserID, d.Name, d.Platform, d.PublicKey, tokenHash, d.Status, now, now)
	return err
}

func (s *Store) DeviceByTokenHash(ctx context.Context, tokenHash []byte) (*Device, error) {
	return scanDevice(s.DB.QueryRowContext(ctx, `SELECT `+deviceCols+` FROM devices WHERE token_hash = ?`, tokenHash))
}

func (s *Store) Device(ctx context.Context, id string) (*Device, error) {
	return scanDevice(s.DB.QueryRowContext(ctx, `SELECT `+deviceCols+` FROM devices WHERE id = ?`, id))
}

func (s *Store) Devices(ctx context.Context, userID string) ([]*Device, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT `+deviceCols+` FROM devices WHERE user_id = ? ORDER BY created_at`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Device
	for rows.Next() {
		d, err := scanDevice(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// ActiveDeviceCount counts the active devices of a user.
func (s *Store) ActiveDeviceCount(ctx context.Context, userID string) (int, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT count(*) FROM devices WHERE user_id = ? AND status = ?`, userID, StatusActive).Scan(&n)
	return n, err
}

func (s *Store) RenameDevice(ctx context.Context, id, name string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE devices SET name = ? WHERE id = ?`, name, id)
	return err
}

func (s *Store) ActivateDevice(ctx context.Context, id string) error {
	_, err := s.DB.ExecContext(ctx, `UPDATE devices SET status = ?, activated_at = ? WHERE id = ?`, StatusActive, NowMillis(), id)
	return err
}

func (s *Store) DeleteDevice(ctx context.Context, id string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM devices WHERE id = ?`, id)
	return err
}

// RevokeDevice deletes a device and remembers its token, so that it is told it was revoked.
func (s *Store) RevokeDevice(ctx context.Context, id string) error {
	return s.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO revoked_devices(token_hash, user_id, revoked_at)
		  SELECT token_hash, user_id, ? FROM devices WHERE id = ?`, NowMillis(), id); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `DELETE FROM devices WHERE id = ?`, id)
		return err
	})
}

// IsRevokedToken reports whether a token belonged to a device that was revoked.
func (s *Store) IsRevokedToken(ctx context.Context, tokenHash []byte) (bool, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT count(*) FROM revoked_devices WHERE token_hash = ?`, tokenHash).Scan(&n)
	return n > 0, err
}

// AbandonedDevices deletes devices that never got access (setup/pending) created before the given time,
// and returns them.
func (s *Store) AbandonedDevices(ctx context.Context, before int64) ([]*Device, error) {
	rows, err := s.DB.QueryContext(ctx, `DELETE FROM devices WHERE status IN (?, ?) AND created_at < ? RETURNING `+deviceCols,
		StatusSetup, StatusPending, before)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Device
	for rows.Next() {
		d, err := scanDevice(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, d)
	}
	return out, rows.Err()
}

// TouchDevice updates last_seen_at if it is older than one minute.
func (s *Store) TouchDevice(ctx context.Context, id string) error {
	now := NowMillis()
	_, err := s.DB.ExecContext(ctx, `UPDATE devices SET last_seen_at = ? WHERE id = ? AND last_seen_at < ?`, now, id, now-60_000)
	return err
}

// --- one-time codes ---

type OTP struct {
	Email     string
	CodeMAC   []byte
	ExpiresAt int64
	Attempts  int
	SentAt    int64
}

func (s *Store) PutOTP(ctx context.Context, o OTP) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO otps(email, code_mac, expires_at, attempts, sent_at) VALUES (?, ?, ?, 0, ?)
	  ON CONFLICT(email) DO UPDATE SET code_mac = excluded.code_mac, expires_at = excluded.expires_at, attempts = 0,
	  sent_at = excluded.sent_at`, o.Email, o.CodeMAC, o.ExpiresAt, o.SentAt)
	return err
}

func (s *Store) GetOTP(ctx context.Context, email string) (*OTP, error) {
	var o OTP
	err := s.DB.QueryRowContext(ctx, `SELECT email, code_mac, expires_at, attempts, sent_at FROM otps WHERE email = ?`, email).
		Scan(&o.Email, &o.CodeMAC, &o.ExpiresAt, &o.Attempts, &o.SentAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &o, err
}

// TakeOTPAttempt uses up one of the attempts of the code sent to email, before it is checked, so that
// concurrent requests cannot try more codes than allowed. It returns the code with the attempts used so far,
// or ErrNotFound if there is no valid code with attempts left.
func (s *Store) TakeOTPAttempt(ctx context.Context, email string, maxAttempts int, now int64) (*OTP, error) {
	var o OTP
	err := s.DB.QueryRowContext(ctx, `UPDATE otps SET attempts = attempts + 1
	  WHERE email = ? AND attempts < ? AND expires_at >= ?
	  RETURNING email, code_mac, expires_at, attempts, sent_at`, email, maxAttempts, now).
		Scan(&o.Email, &o.CodeMAC, &o.ExpiresAt, &o.Attempts, &o.SentAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &o, err
}

// ConsumeOTP deletes the code if it is still the one checked (codeMAC): only one request can use it.
func (s *Store) ConsumeOTP(ctx context.Context, email string, codeMAC []byte) (bool, error) {
	res, err := s.DB.ExecContext(ctx, `DELETE FROM otps WHERE email = ? AND code_mac = ?`, email, codeMAC)
	if err != nil {
		return false, err
	}
	n, err := res.RowsAffected()
	return n == 1, err
}

func (s *Store) DeleteOTP(ctx context.Context, email string) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM otps WHERE email = ?`, email)
	return err
}

// --- recovery attempts ---

func (s *Store) AddRecoveryAttempt(ctx context.Context, userID string) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO recovery_attempts(user_id, at) VALUES (?, ?)`, userID, NowMillis())
	return err
}

func (s *Store) RecoveryAttemptsSince(ctx context.Context, userID string, since int64) (int, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT count(*) FROM recovery_attempts WHERE user_id = ? AND at >= ?`, userID, since).Scan(&n)
	return n, err
}
