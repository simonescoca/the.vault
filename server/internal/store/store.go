// Package store is the SQLite persistence layer of the server.
//
// The server never sees plaintext vault data: records and blobs are opaque ciphertext
// produced by the apps. The store only keeps accounts, devices, one-time codes,
// approval requests, encrypted records and blob metadata.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

var ErrNotFound = errors.New("not found")

type Store struct {
	DB   *sql.DB
	path string
}

// Open opens (and migrates) the database at path. Use ":memory:" only in tests with a single connection.
func Open(path string) (*Store, error) {
	if path != ":memory:" {
		if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
			return nil, err
		}
	}
	q := url.Values{}
	q.Add("_pragma", "journal_mode(WAL)")
	q.Add("_pragma", "busy_timeout(10000)")
	q.Add("_pragma", "foreign_keys(1)")
	q.Add("_pragma", "synchronous(NORMAL)")
	q.Set("_txlock", "immediate")
	dsn := "file:" + path + "?" + q.Encode()
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	if path == ":memory:" {
		db.SetMaxOpenConns(1)
	} else {
		db.SetMaxOpenConns(8)
	}
	s := &Store{DB: db, path: path}
	if err := s.migrate(context.Background()); err != nil {
		db.Close()
		return nil, fmt.Errorf("migrazione database: %w", err)
	}
	if path != ":memory:" {
		_ = os.Chmod(path, 0o600)
	}
	return s, nil
}

func (s *Store) Close() error { return s.DB.Close() }

// Path returns the database file path.
func (s *Store) Path() string { return s.path }

// NowMillis is the clock used by the store; tests may replace it.
var NowMillis = func() int64 { return time.Now().UnixMilli() }

var migrations = []string{
	// 1: initial schema
	`
CREATE TABLE users (
  id                     TEXT PRIMARY KEY,
  email                  TEXT NOT NULL UNIQUE,
  created_at             INTEGER NOT NULL,
  vault_initialized      INTEGER NOT NULL DEFAULT 0,
  key_check              BLOB,
  recovery_salt          BLOB,
  recovery_ops           INTEGER,
  recovery_mem           INTEGER,
  recovery_wrap          BLOB,
  recovery_auth_hash     BLOB,
  rev                    INTEGER NOT NULL DEFAULT 0,
  approvals_paused_until INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE devices (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  platform     TEXT NOT NULL,
  public_key   BLOB NOT NULL,
  token_hash   BLOB NOT NULL UNIQUE,
  status       TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  activated_at INTEGER
);
CREATE INDEX devices_user ON devices(user_id);

CREATE TABLE otps (
  email      TEXT PRIMARY KEY,
  code_mac   BLOB NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts   INTEGER NOT NULL DEFAULT 0,
  sent_at    INTEGER NOT NULL
);

CREATE TABLE approvals (
  id                   TEXT PRIMARY KEY,
  user_id              TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id            TEXT NOT NULL,
  state                TEXT NOT NULL,
  commitment           BLOB NOT NULL,
  responder_device_id  TEXT,
  responder_public_key BLOB,
  responder_nonce      BLOB,
  revealed_nonce       BLOB,
  box                  BLOB,
  box_nonce            BLOB,
  created_at           INTEGER NOT NULL,
  updated_at           INTEGER NOT NULL,
  expires_at           INTEGER NOT NULL
);
CREATE INDEX approvals_user ON approvals(user_id, state);

CREATE TABLE records (
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id         TEXT NOT NULL,
  rev        INTEGER NOT NULL,
  data       BLOB,
  deleted    INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  updated_by TEXT NOT NULL,
  PRIMARY KEY (user_id, id)
);
CREATE INDEX records_rev ON records(user_id, rev);

CREATE TABLE record_blobs (
  user_id   TEXT NOT NULL,
  record_id TEXT NOT NULL,
  blob_id   TEXT NOT NULL,
  PRIMARY KEY (user_id, record_id, blob_id)
);
CREATE INDEX record_blobs_blob ON record_blobs(user_id, blob_id);

CREATE TABLE blobs (
  user_id       TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id            TEXT NOT NULL,
  size          INTEGER NOT NULL,
  part_size     INTEGER NOT NULL,
  state         TEXT NOT NULL,
  sha256        TEXT,
  created_at    INTEGER NOT NULL,
  completed_at  INTEGER,
  unreferenced_since INTEGER,
  PRIMARY KEY (user_id, id)
);

CREATE TABLE blob_parts (
  user_id TEXT NOT NULL,
  blob_id TEXT NOT NULL,
  n       INTEGER NOT NULL,
  size    INTEGER NOT NULL,
  PRIMARY KEY (user_id, blob_id, n)
);

CREATE TABLE recovery_attempts (
  user_id TEXT NOT NULL,
  at      INTEGER NOT NULL
);
CREATE INDEX recovery_attempts_user ON recovery_attempts(user_id, at);
`,
}

func (s *Store) migrate(ctx context.Context) error {
	if _, err := s.DB.ExecContext(ctx, `CREATE TABLE IF NOT EXISTS schema_version (version INTEGER NOT NULL)`); err != nil {
		return err
	}
	var v int
	err := s.DB.QueryRowContext(ctx, `SELECT version FROM schema_version`).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		if _, err := s.DB.ExecContext(ctx, `INSERT INTO schema_version(version) VALUES (0)`); err != nil {
			return err
		}
		v = 0
	} else if err != nil {
		return err
	}
	for i := v; i < len(migrations); i++ {
		tx, err := s.DB.BeginTx(ctx, nil)
		if err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, migrations[i]); err != nil {
			tx.Rollback()
			return fmt.Errorf("migration %d: %w", i+1, err)
		}
		if _, err := tx.ExecContext(ctx, `UPDATE schema_version SET version = ?`, i+1); err != nil {
			tx.Rollback()
			return err
		}
		if err := tx.Commit(); err != nil {
			return err
		}
	}
	return nil
}

// Tx runs fn inside an IMMEDIATE transaction.
func (s *Store) Tx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.DB.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

// Backup writes a consistent snapshot of the database to dst (which must not exist).
func (s *Store) Backup(ctx context.Context, dst string) error {
	_, err := s.DB.ExecContext(ctx, `VACUUM INTO ?`, dst)
	return err
}
