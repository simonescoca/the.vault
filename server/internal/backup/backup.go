// Package backup makes daily snapshots of the server data.
//
// Everything in a backup is already end-to-end encrypted by the apps. The folder must be one that macOS
// lets a background service write to: not iCloud Drive, Desktop, Documents, Downloads or external disks
// (see setup.BlockedBackupLocation); Time Machine can then copy it elsewhere. Layout of the backup folder:
//
//	snapshots/2026-10-02_033000/thevault.db   consistent copy of the database
//	snapshots/2026-10-02_033000/manifest.json
//	blobs/<userID>/<blobID>                   attachments, shared by all snapshots (they never change)
package backup

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/simonescoca/the.vault/server/internal/blobs"
	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/store"
)

const stampLayout = "2006-01-02_150405"

// Dir returns the configured backup folder (default: <data>/backups).
func Dir(cfg *config.Config) string {
	if cfg.Backup.Dir != "" {
		return cfg.Backup.Dir
	}
	return filepath.Join(cfg.DataDir, "backups")
}

// Run makes one snapshot now and prunes old ones. It returns the snapshot folder.
func Run(ctx context.Context, cfg *config.Config, st *store.Store) (string, error) {
	return run(ctx, cfg, st, time.Now())
}

func run(ctx context.Context, cfg *config.Config, st *store.Store, now time.Time) (string, error) {
	root := Dir(cfg)
	snap := filepath.Join(root, "snapshots", now.Format(stampLayout))
	if err := os.MkdirAll(snap, 0o700); err != nil {
		return "", err
	}
	dbPath := filepath.Join(snap, "thevault.db")
	if err := st.Backup(ctx, dbPath); err != nil {
		os.RemoveAll(snap)
		return "", fmt.Errorf("copia del database: %w", err)
	}
	ids, err := st.AllCompleteBlobIDs(ctx)
	if err != nil {
		return "", err
	}
	files := &blobs.Files{Dir: cfg.DataDir}
	copied := 0
	for _, ub := range ids {
		dst := filepath.Join(root, "blobs", ub[0], ub[1])
		if _, err := os.Stat(dst); err == nil {
			continue
		}
		if err := copyFile(files.BlobPath(ub[0], ub[1]), dst); err != nil {
			return "", fmt.Errorf("copia allegato %s: %w", ub[1], err)
		}
		copied++
	}
	manifest, _ := json.MarshalIndent(map[string]any{
		"createdAt": now.Format(time.RFC3339), "blobs": len(ids), "newBlobs": copied,
	}, "", "  ")
	if err := os.WriteFile(filepath.Join(snap, "manifest.json"), manifest, 0o600); err != nil {
		return "", err
	}
	if err := prune(root, cfg.Backup.KeepDays, ids, now); err != nil {
		return snap, fmt.Errorf("pulizia vecchi backup: %w", err)
	}
	return snap, nil
}

func copyFile(src, dst string) error {
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	tmp := dst + ".tmp"
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(tmp)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	return os.Rename(tmp, dst)
}

// prune removes snapshots older than keepDays, and pooled blobs that no longer exist on the server
// and are older than keepDays (so every kept snapshot still finds its attachments).
func prune(root string, keepDays int, live [][2]string, now time.Time) error {
	cutoff := now.Add(-time.Duration(keepDays) * 24 * time.Hour)
	entries, err := os.ReadDir(filepath.Join(root, "snapshots"))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	for _, e := range entries {
		t, err := time.ParseInLocation(stampLayout, e.Name(), now.Location())
		if err != nil || !e.IsDir() {
			continue
		}
		if t.Before(cutoff) {
			if err := os.RemoveAll(filepath.Join(root, "snapshots", e.Name())); err != nil {
				return err
			}
		}
	}
	isLive := map[string]bool{}
	for _, ub := range live {
		isLive[ub[0]+"/"+ub[1]] = true
	}
	users, err := os.ReadDir(filepath.Join(root, "blobs"))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	for _, u := range users {
		files, err := os.ReadDir(filepath.Join(root, "blobs", u.Name()))
		if err != nil {
			continue
		}
		for _, f := range files {
			if isLive[u.Name()+"/"+f.Name()] {
				continue
			}
			info, err := f.Info()
			if err == nil && info.ModTime().Before(cutoff) {
				os.Remove(filepath.Join(root, "blobs", u.Name(), f.Name()))
			}
		}
	}
	return nil
}

// Snapshots lists the snapshot folders, newest first.
func Snapshots(cfg *config.Config) ([]string, error) {
	entries, err := os.ReadDir(filepath.Join(Dir(cfg), "snapshots"))
	if err != nil {
		return nil, err
	}
	var out []string
	for _, e := range entries {
		if _, err := time.Parse(stampLayout, e.Name()); err == nil && e.IsDir() {
			out = append(out, e.Name())
		}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(out)))
	return out, nil
}

// Status is the outcome of the latest backup, kept in <data>/backup-status.json for 'thevault-server status'.
type Status struct {
	LastAttempt int64  `json:"lastAttempt,omitempty"` // Unix milliseconds
	LastSuccess int64  `json:"lastSuccess,omitempty"`
	LastDir     string `json:"lastDir,omitempty"`
	LastError   string `json:"lastError,omitempty"` // empty when the latest attempt worked
}

func statusPath(cfg *config.Config) string { return filepath.Join(cfg.DataDir, "backup-status.json") }

// ReadStatus returns the outcome of the latest backup (zero if there was none yet).
func ReadStatus(cfg *config.Config) Status {
	var s Status
	if b, err := os.ReadFile(statusPath(cfg)); err == nil {
		_ = json.Unmarshal(b, &s)
	}
	return s
}

// RunAndRecord makes a backup now and records the outcome.
func RunAndRecord(ctx context.Context, cfg *config.Config, st *store.Store) (string, error) {
	dir, err := Run(ctx, cfg, st)
	s := ReadStatus(cfg)
	s.LastAttempt = time.Now().UnixMilli()
	if err != nil {
		s.LastError = err.Error()
	} else {
		s.LastSuccess, s.LastDir, s.LastError = s.LastAttempt, dir, ""
	}
	if b, jerr := json.Marshal(s); jerr == nil {
		_ = os.WriteFile(statusPath(cfg), b, 0o600)
	}
	return dir, err
}

// RunDaily makes a backup every day at cfg.Backup.Hour (local time). If the latest snapshot is older
// than a day (e.g. the Mac was off at backup time, or this is the first start) it makes one shortly after start.
func RunDaily(ctx context.Context, cfg *config.Config, st *store.Store, log *slog.Logger) {
	first := nextRun(time.Now(), cfg.Backup.Hour)
	if snaps, err := Snapshots(cfg); err != nil || len(snaps) == 0 || stale(snaps[0], time.Now()) {
		first = time.Now().Add(30 * time.Second)
	}
	timer := time.NewTimer(time.Until(first))
	defer timer.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
		}
		if dir, err := RunAndRecord(ctx, cfg, st); err != nil {
			log.Error("backup failed", "dir", Dir(cfg), "error", err)
		} else {
			log.Info("backup done", "dir", dir)
		}
		timer.Reset(time.Until(nextRun(time.Now(), cfg.Backup.Hour)))
	}
}

func stale(name string, now time.Time) bool {
	t, err := time.ParseInLocation(stampLayout, name, now.Location())
	return err != nil || now.Sub(t) > 25*time.Hour
}

func nextRun(now time.Time, hour int) time.Time {
	next := time.Date(now.Year(), now.Month(), now.Day(), hour, 30, 0, 0, now.Location())
	if !next.After(now) {
		next = next.Add(24 * time.Hour)
	}
	return next
}
