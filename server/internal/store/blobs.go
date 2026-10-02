package store

import (
	"context"
	"database/sql"
	"errors"
)

// Blob states.
const (
	BlobUploading = "uploading"
	BlobComplete  = "complete"
)

type Blob struct {
	UserID      string
	ID          string
	Size        int64
	PartSize    int64
	State       string
	SHA256      sql.NullString
	CreatedAt   int64
	CompletedAt sql.NullInt64
}

func (s *Store) Blob(ctx context.Context, userID, id string) (*Blob, error) {
	var b Blob
	err := s.DB.QueryRowContext(ctx, `SELECT user_id, id, size, part_size, state, sha256, created_at, completed_at
	  FROM blobs WHERE user_id = ? AND id = ?`, userID, id).
		Scan(&b.UserID, &b.ID, &b.Size, &b.PartSize, &b.State, &b.SHA256, &b.CreatedAt, &b.CompletedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	return &b, nil
}

// CreateBlob registers a new upload. A blob starts unreferenced: if no record uses it within the
// grace period it is garbage-collected.
func (s *Store) CreateBlob(ctx context.Context, b *Blob) error {
	now := NowMillis()
	b.CreatedAt, b.State = now, BlobUploading
	_, err := s.DB.ExecContext(ctx, `INSERT INTO blobs(user_id, id, size, part_size, state, created_at, unreferenced_since)
	  VALUES (?, ?, ?, ?, ?, ?, ?)`, b.UserID, b.ID, b.Size, b.PartSize, b.State, now, now)
	return err
}

func (s *Store) PutBlobPart(ctx context.Context, userID, blobID string, n int, size int64) error {
	_, err := s.DB.ExecContext(ctx, `INSERT INTO blob_parts(user_id, blob_id, n, size) VALUES (?, ?, ?, ?)
	  ON CONFLICT(user_id, blob_id, n) DO UPDATE SET size = excluded.size`, userID, blobID, n, size)
	return err
}

// BlobParts returns part number → size for an upload.
func (s *Store) BlobParts(ctx context.Context, userID, blobID string) (map[int]int64, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT n, size FROM blob_parts WHERE user_id = ? AND blob_id = ?`, userID, blobID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := map[int]int64{}
	for rows.Next() {
		var n int
		var size int64
		if err := rows.Scan(&n, &size); err != nil {
			return nil, err
		}
		out[n] = size
	}
	return out, rows.Err()
}

func (s *Store) CompleteBlob(ctx context.Context, userID, blobID, sha string) error {
	return s.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `UPDATE blobs SET state = ?, sha256 = ?, completed_at = ? WHERE user_id = ? AND id = ?`,
			BlobComplete, sha, NowMillis(), userID, blobID); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `DELETE FROM blob_parts WHERE user_id = ? AND blob_id = ?`, userID, blobID)
		return err
	})
}

// OrphanBlobs lists blobs not referenced by any record since before the given time.
func (s *Store) OrphanBlobs(ctx context.Context, before int64) ([]*Blob, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT user_id, id, size, part_size, state, sha256, created_at, completed_at FROM blobs b
	  WHERE unreferenced_since IS NOT NULL AND unreferenced_since < ?
	  AND NOT EXISTS (SELECT 1 FROM record_blobs r WHERE r.user_id = b.user_id AND r.blob_id = b.id)`, before)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Blob
	for rows.Next() {
		var b Blob
		if err := rows.Scan(&b.UserID, &b.ID, &b.Size, &b.PartSize, &b.State, &b.SHA256, &b.CreatedAt, &b.CompletedAt); err != nil {
			return nil, err
		}
		out = append(out, &b)
	}
	return out, rows.Err()
}

func (s *Store) DeleteBlob(ctx context.Context, userID, blobID string) error {
	return s.Tx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `DELETE FROM blob_parts WHERE user_id = ? AND blob_id = ?`, userID, blobID); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, `DELETE FROM blobs WHERE user_id = ? AND id = ?`, userID, blobID)
		return err
	})
}

// AllCompleteBlobIDs lists every complete blob (used by backups).
func (s *Store) AllCompleteBlobIDs(ctx context.Context) ([][2]string, error) {
	rows, err := s.DB.QueryContext(ctx, `SELECT user_id, id FROM blobs WHERE state = ?`, BlobComplete)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out [][2]string
	for rows.Next() {
		var u, id string
		if err := rows.Scan(&u, &id); err != nil {
			return nil, err
		}
		out = append(out, [2]string{u, id})
	}
	return out, rows.Err()
}
