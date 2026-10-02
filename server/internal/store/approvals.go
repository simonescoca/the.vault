package store

import (
	"context"
	"database/sql"
	"errors"
)

// Approval states.
const (
	ApprovalRequested = "requested"
	ApprovalResponded = "responded"
	ApprovalRevealed  = "revealed"
	ApprovalApproved  = "approved"
	ApprovalRejected  = "rejected"
	ApprovalExpired   = "expired"
	ApprovalCancelled = "cancelled"
)

// ApprovalOpen reports whether a state can still change.
func ApprovalOpen(state string) bool {
	return state == ApprovalRequested || state == ApprovalResponded || state == ApprovalRevealed
}

type Approval struct {
	ID                 string
	UserID             string
	DeviceID           string
	State              string
	Commitment         []byte
	ResponderDeviceID  sql.NullString
	ResponderPublicKey []byte
	ResponderNonce     []byte
	RevealedNonce      []byte
	Box                []byte
	BoxNonce           []byte
	CreatedAt          int64
	UpdatedAt          int64
	ExpiresAt          int64
}

const approvalCols = `id, user_id, device_id, state, commitment, responder_device_id, responder_public_key, responder_nonce,
  revealed_nonce, box, box_nonce, created_at, updated_at, expires_at`

func scanApproval(r scanner) (*Approval, error) {
	var a Approval
	err := r.Scan(&a.ID, &a.UserID, &a.DeviceID, &a.State, &a.Commitment, &a.ResponderDeviceID, &a.ResponderPublicKey,
		&a.ResponderNonce, &a.RevealedNonce, &a.Box, &a.BoxNonce, &a.CreatedAt, &a.UpdatedAt, &a.ExpiresAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &a, nil
}

// CreateApproval inserts a new request and cancels the other open requests of the same device.
// It returns the ids of the cancelled requests.
func (s *Store) CreateApproval(ctx context.Context, a *Approval) (cancelled []string, err error) {
	now := NowMillis()
	a.CreatedAt, a.UpdatedAt, a.State = now, now, ApprovalRequested
	err = s.Tx(ctx, func(tx *sql.Tx) error {
		rows, err := tx.QueryContext(ctx, `SELECT id FROM approvals WHERE device_id = ? AND state IN (?, ?, ?)`,
			a.DeviceID, ApprovalRequested, ApprovalResponded, ApprovalRevealed)
		if err != nil {
			return err
		}
		for rows.Next() {
			var id string
			if err := rows.Scan(&id); err != nil {
				rows.Close()
				return err
			}
			cancelled = append(cancelled, id)
		}
		rows.Close()
		for _, id := range cancelled {
			if _, err := tx.ExecContext(ctx, `UPDATE approvals SET state = ?, updated_at = ? WHERE id = ?`, ApprovalCancelled, now, id); err != nil {
				return err
			}
		}
		_, err = tx.ExecContext(ctx, `INSERT INTO approvals(id, user_id, device_id, state, commitment, created_at, updated_at, expires_at)
		  VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, a.ID, a.UserID, a.DeviceID, a.State, a.Commitment, now, now, a.ExpiresAt)
		return err
	})
	return cancelled, err
}

func (s *Store) Approval(ctx context.Context, id string) (*Approval, error) {
	return scanApproval(s.DB.QueryRowContext(ctx, `SELECT `+approvalCols+` FROM approvals WHERE id = ?`, id))
}

// OpenApprovals lists the open, non-expired requests of a user.
func (s *Store) OpenApprovals(ctx context.Context, userID string) ([]*Approval, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT `+approvalCols+` FROM approvals WHERE user_id = ? AND state IN (?, ?, ?)
	  AND expires_at > ? ORDER BY created_at`, userID, ApprovalRequested, ApprovalResponded, ApprovalRevealed, NowMillis())
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Approval
	for rows.Next() {
		a, err := scanApproval(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

var ErrApprovalState = errors.New("approval is not in the expected state")

// transition updates an approval only if it is in state `from` and not expired.
func (s *Store) transition(ctx context.Context, id, from, to string, set string, args ...any) error {
	now := NowMillis()
	q := `UPDATE approvals SET state = ?, updated_at = ?` + set + ` WHERE id = ? AND state = ? AND expires_at > ?`
	all := append([]any{to, now}, args...)
	all = append(all, id, from, now)
	res, err := s.DB.ExecContext(ctx, q, all...)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrApprovalState
	}
	return nil
}

func (s *Store) RespondApproval(ctx context.Context, id, responderDeviceID string, pk, nonce []byte) error {
	return s.transition(ctx, id, ApprovalRequested, ApprovalResponded,
		`, responder_device_id = ?, responder_public_key = ?, responder_nonce = ?`, responderDeviceID, pk, nonce)
}

func (s *Store) RevealApproval(ctx context.Context, id string, nonce []byte) error {
	return s.transition(ctx, id, ApprovalResponded, ApprovalRevealed, `, revealed_nonce = ?`, nonce)
}

// ApproveApproval stores the sealed vault key and activates the requesting device, atomically.
func (s *Store) ApproveApproval(ctx context.Context, a *Approval, box, boxNonce []byte) error {
	now := NowMillis()
	return s.Tx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `UPDATE approvals SET state = ?, updated_at = ?, box = ?, box_nonce = ?
		  WHERE id = ? AND state = ? AND expires_at > ?`, ApprovalApproved, now, box, boxNonce, a.ID, ApprovalRevealed, now)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrApprovalState
		}
		res, err = tx.ExecContext(ctx, `UPDATE devices SET status = ?, activated_at = ? WHERE id = ? AND status = ?`,
			StatusActive, now, a.DeviceID, StatusPending)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrNotFound
		}
		return nil
	})
}

// CloseApproval moves an open approval to a final state (rejected, cancelled, expired).
func (s *Store) CloseApproval(ctx context.Context, id, state string) error {
	res, err := s.DB.ExecContext(ctx, `UPDATE approvals SET state = ?, updated_at = ? WHERE id = ? AND state IN (?, ?, ?)`,
		state, NowMillis(), id, ApprovalRequested, ApprovalResponded, ApprovalRevealed)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrApprovalState
	}
	return nil
}

// ExpireApprovals marks open requests past their deadline as expired and returns them.
func (s *Store) ExpireApprovals(ctx context.Context) ([]*Approval, error) {
	now := NowMillis()
	rows, err := s.DB.QueryContext(ctx, `UPDATE approvals SET state = ?, updated_at = ? WHERE state IN (?, ?, ?) AND expires_at <= ?
	  RETURNING `+approvalCols, ApprovalExpired, now, ApprovalRequested, ApprovalResponded, ApprovalRevealed, now)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Approval
	for rows.Next() {
		a, err := scanApproval(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// RejectionsSince counts the requests of a user rejected since the given time.
func (s *Store) RejectionsSince(ctx context.Context, userID string, since int64) (int, error) {
	var n int
	err := s.DB.QueryRowContext(ctx, `SELECT count(*) FROM approvals WHERE user_id = ? AND state = ? AND updated_at >= ?`,
		userID, ApprovalRejected, since).Scan(&n)
	return n, err
}

// PurgeApprovals deletes closed requests older than the given time.
func (s *Store) PurgeApprovals(ctx context.Context, before int64) error {
	_, err := s.DB.ExecContext(ctx, `DELETE FROM approvals WHERE state NOT IN (?, ?, ?) AND updated_at < ?`,
		ApprovalRequested, ApprovalResponded, ApprovalRevealed, before)
	return err
}
