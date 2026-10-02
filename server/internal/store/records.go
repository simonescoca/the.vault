package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
)

// Record is an encrypted vault entry as stored by the server.
type Record struct {
	ID        string
	Rev       int64
	Data      []byte // nil when Deleted
	Deleted   bool
	UpdatedAt int64
	UpdatedBy string
	Blobs     []string
}

// ConflictError is returned by PutRecord/DeleteRecord when baseRev is stale.
type ConflictError struct{ Current *Record }

func (e *ConflictError) Error() string { return "conflict" }

// MissingBlobError is returned when a record references blobs that are not complete.
type MissingBlobError struct{ IDs []string }

func (e *MissingBlobError) Error() string { return "missing blob: " + strings.Join(e.IDs, ",") }

func (s *Store) recordTx(ctx context.Context, tx *sql.Tx, userID, id string) (*Record, error) {
	var r Record
	err := tx.QueryRowContext(ctx, `SELECT id, rev, data, deleted, updated_at, updated_by FROM records WHERE user_id = ? AND id = ?`,
		userID, id).Scan(&r.ID, &r.Rev, &r.Data, &r.Deleted, &r.UpdatedAt, &r.UpdatedBy)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	blobs, err := recordBlobs(ctx, tx, userID, id)
	if err != nil {
		return nil, err
	}
	r.Blobs = blobs
	return &r, nil
}

type querier interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

func recordBlobs(ctx context.Context, q querier, userID, id string) ([]string, error) {
	rows, err := q.QueryContext(ctx, `SELECT blob_id FROM record_blobs WHERE user_id = ? AND record_id = ? ORDER BY blob_id`, userID, id)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []string{}
	for rows.Next() {
		var b string
		if err := rows.Scan(&b); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

// Record returns one record (live or tombstone).
func (s *Store) Record(ctx context.Context, userID, id string) (*Record, error) {
	var out *Record
	err := s.Tx(ctx, func(tx *sql.Tx) error {
		r, err := s.recordTx(ctx, tx, userID, id)
		out = r
		return err
	})
	return out, err
}

// PutRecord creates or updates a record if baseRev matches its current revision (0 = must not exist).
// It returns the new revision.
func (s *Store) PutRecord(ctx context.Context, userID, deviceID, id string, baseRev int64, data []byte, blobs []string) (int64, int64, error) {
	return s.writeRecord(ctx, userID, deviceID, id, baseRev, data, blobs, false)
}

// DeleteRecord turns a record into a tombstone if baseRev matches.
func (s *Store) DeleteRecord(ctx context.Context, userID, deviceID, id string, baseRev int64) (int64, int64, error) {
	return s.writeRecord(ctx, userID, deviceID, id, baseRev, nil, nil, true)
}

func (s *Store) writeRecord(ctx context.Context, userID, deviceID, id string, baseRev int64, data []byte, blobs []string, deleted bool) (int64, int64, error) {
	var newRev int64
	now := NowMillis()
	err := s.Tx(ctx, func(tx *sql.Tx) error {
		cur, err := s.recordTx(ctx, tx, userID, id)
		if err != nil && !errors.Is(err, ErrNotFound) {
			return err
		}
		curRev := int64(0)
		if cur != nil {
			curRev = cur.Rev
		}
		if curRev != baseRev {
			if cur == nil {
				// The client believes the record exists but it does not: report an empty tombstone.
				cur = &Record{ID: id, Rev: 0, Deleted: true, Blobs: []string{}}
			}
			return &ConflictError{Current: cur}
		}
		if deleted && cur == nil {
			return ErrNotFound
		}
		// All referenced blobs must be complete.
		var missing []string
		for _, b := range blobs {
			var state string
			err := tx.QueryRowContext(ctx, `SELECT state FROM blobs WHERE user_id = ? AND id = ?`, userID, b).Scan(&state)
			if errors.Is(err, sql.ErrNoRows) || (err == nil && state != BlobComplete) {
				missing = append(missing, b)
			} else if err != nil {
				return err
			}
		}
		if len(missing) > 0 {
			return &MissingBlobError{IDs: missing}
		}
		if err := tx.QueryRowContext(ctx, `UPDATE users SET rev = rev + 1 WHERE id = ? RETURNING rev`, userID).Scan(&newRev); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO records(user_id, id, rev, data, deleted, updated_at, updated_by)
		  VALUES (?, ?, ?, ?, ?, ?, ?)
		  ON CONFLICT(user_id, id) DO UPDATE SET rev = excluded.rev, data = excluded.data, deleted = excluded.deleted,
		  updated_at = excluded.updated_at, updated_by = excluded.updated_by`,
			userID, id, newRev, data, deleted, now, deviceID); err != nil {
			return err
		}
		// Replace blob references; blobs that lose their last reference start their grace period.
		var old []string
		if cur != nil {
			old = cur.Blobs
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM record_blobs WHERE user_id = ? AND record_id = ?`, userID, id); err != nil {
			return err
		}
		for _, b := range blobs {
			if _, err := tx.ExecContext(ctx, `INSERT OR IGNORE INTO record_blobs(user_id, record_id, blob_id) VALUES (?, ?, ?)`, userID, id, b); err != nil {
				return err
			}
			if _, err := tx.ExecContext(ctx, `UPDATE blobs SET unreferenced_since = NULL WHERE user_id = ? AND id = ?`, userID, b); err != nil {
				return err
			}
		}
		for _, b := range old {
			if _, err := tx.ExecContext(ctx, `UPDATE blobs SET unreferenced_since = ? WHERE user_id = ? AND id = ?
			  AND NOT EXISTS (SELECT 1 FROM record_blobs WHERE user_id = ? AND blob_id = ?)`, now, userID, b, userID, b); err != nil {
				return err
			}
		}
		return nil
	})
	return newRev, now, err
}

// RecordsSince returns up to limit records with rev > since, ordered by rev, and whether more exist.
func (s *Store) RecordsSince(ctx context.Context, userID string, since int64, limit int) ([]*Record, bool, int64, error) {
	var out []*Record
	var more bool
	var latest int64
	err := s.Tx(ctx, func(tx *sql.Tx) error {
		if err := tx.QueryRowContext(ctx, `SELECT rev FROM users WHERE id = ?`, userID).Scan(&latest); err != nil {
			return err
		}
		rows, err := tx.QueryContext(ctx, `SELECT id, rev, data, deleted, updated_at, updated_by FROM records
		  WHERE user_id = ? AND rev > ? ORDER BY rev LIMIT ?`, userID, since, limit+1)
		if err != nil {
			return err
		}
		for rows.Next() {
			var r Record
			if err := rows.Scan(&r.ID, &r.Rev, &r.Data, &r.Deleted, &r.UpdatedAt, &r.UpdatedBy); err != nil {
				rows.Close()
				return err
			}
			out = append(out, &r)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		if len(out) > limit {
			out, more = out[:limit], true
		}
		for _, r := range out {
			b, err := recordBlobs(ctx, tx, userID, r.ID)
			if err != nil {
				return err
			}
			r.Blobs = b
		}
		return nil
	})
	return out, more, latest, err
}

// LatestRev returns the user's latest record revision.
func (s *Store) LatestRev(ctx context.Context, userID string) (int64, error) {
	var rev int64
	err := s.DB.QueryRowContext(ctx, `SELECT rev FROM users WHERE id = ?`, userID).Scan(&rev)
	return rev, err
}
