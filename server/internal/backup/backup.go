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
	"strings"
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

// manifest describes a snapshot. BlobIDs lists the attachments it needs ("<userID>/<blobID>"): pruning keeps
// them in the shared pool as long as the snapshot is kept.
type manifest struct {
	CreatedAt    string   `json:"createdAt"`
	Blobs        int      `json:"blobs"`
	NewBlobs     int      `json:"newBlobs"`
	BlobIDs      []string `json:"blobIds"`
	MissingBlobs []string `json:"missingBlobs,omitempty"`
}

const tmpPrefix = ".tmp-"

func run(ctx context.Context, cfg *config.Config, st *store.Store, now time.Time) (string, error) {
	root := Dir(cfg)
	snapshots := filepath.Join(root, "snapshots")
	if err := os.MkdirAll(snapshots, 0o700); err != nil {
		return "", err
	}
	// One backup at a time (the server's daily one, 'thevault-server backup', the one before an upgrade):
	// pruning must not remove what another backup is building.
	unlock, err := lockDir(root)
	if err != nil {
		return "", err
	}
	defer unlock()
	stamp := now.Format(stampLayout)
	// Built in a temporary folder and renamed at the end: an interrupted backup never looks like a snapshot.
	tmp, err := os.MkdirTemp(snapshots, tmpPrefix+stamp+"-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(tmp) // nothing left to remove after the rename
	if err := st.Backup(ctx, filepath.Join(tmp, "thevault.db")); err != nil {
		return "", fmt.Errorf("copia del database: %w", err)
	}
	ids, err := st.AllCompleteBlobIDs(ctx)
	if err != nil {
		return "", err
	}
	files := &blobs.Files{Dir: cfg.DataDir}
	m := manifest{CreatedAt: now.Format(time.RFC3339), Blobs: len(ids), BlobIDs: make([]string, 0, len(ids))}
	for _, ub := range ids {
		src, dst := files.BlobPath(ub[0], ub[1]), filepath.Join(root, "blobs", ub[0], ub[1])
		in, err := os.Stat(src)
		if errors.Is(err, os.ErrNotExist) {
			if needed, err := st.BlobNeeded(ctx, ub[0], ub[1]); err == nil && !needed {
				continue // an orphan deleted by the cleanup meanwhile: not lost
			}
			// Listed in the database but not on disk: one lost attachment must not stop every backup, and the
			// copy in the backups (now the only one) must stay.
			m.MissingBlobs = append(m.MissingBlobs, ub[0]+"/"+ub[1])
			if _, err := os.Stat(dst); err == nil {
				m.BlobIDs = append(m.BlobIDs, ub[0]+"/"+ub[1])
			}
			continue
		}
		if err != nil {
			return "", fmt.Errorf("allegato %s: %w", ub[1], err)
		}
		if out, err := os.Stat(dst); err != nil || out.Size() != in.Size() {
			if err := copyFile(src, dst); err != nil {
				return "", fmt.Errorf("copia allegato %s: %w", ub[1], err)
			}
			m.NewBlobs++
		}
		m.BlobIDs = append(m.BlobIDs, ub[0]+"/"+ub[1])
	}
	b, _ := json.MarshalIndent(m, "", "  ")
	if err := os.WriteFile(filepath.Join(tmp, "manifest.json"), b, 0o600); err != nil {
		return "", err
	}
	snap := filepath.Join(snapshots, stamp)
	if err := os.Rename(tmp, snap); err != nil {
		if _, serr := os.Stat(filepath.Join(snap, "manifest.json")); serr == nil {
			return snap, nil // another backup finished in the same second
		}
		return "", err
	}
	syncDir(snapshots)
	if err := prune(root, cfg.Backup.KeepDays, now); err != nil {
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
	if err := out.Sync(); err != nil {
		out.Close()
		os.Remove(tmp)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(tmp)
		return err
	}
	if err := os.Rename(tmp, dst); err != nil {
		return err
	}
	syncDir(filepath.Dir(dst))
	return nil
}

// syncDir makes a rename in dir survive a power cut (best effort).
func syncDir(dir string) {
	if d, err := os.Open(dir); err == nil {
		_ = d.Sync()
		d.Close()
	}
}

// missingBlobs returns the attachments a snapshot found missing on the server.
func missingBlobs(snap string) []string {
	var m manifest
	if b, err := os.ReadFile(filepath.Join(snap, "manifest.json")); err == nil {
		_ = json.Unmarshal(b, &m)
	}
	return m.MissingBlobs
}

// manifestBlobIDs returns the attachments listed by a snapshot; ok is false for a snapshot that does not
// list them (made by an older version, or incomplete).
func manifestBlobIDs(snap string) (ids []string, ok bool) {
	b, err := os.ReadFile(filepath.Join(snap, "manifest.json"))
	if err != nil {
		return nil, false
	}
	var m struct {
		BlobIDs *[]string `json:"blobIds"`
	}
	if json.Unmarshal(b, &m) != nil || m.BlobIDs == nil {
		return nil, false
	}
	return *m.BlobIDs, true
}

// prune removes the snapshots older than keepDays, unfinished ones left by an interruption, and the pooled
// attachments that no kept snapshot needs any more.
func prune(root string, keepDays int, now time.Time) error {
	cutoff := now.Add(-time.Duration(keepDays) * 24 * time.Hour)
	snapshots := filepath.Join(root, "snapshots")
	entries, err := os.ReadDir(snapshots)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	needed := map[string]bool{}
	complete := true
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		if strings.HasPrefix(e.Name(), tmpPrefix) {
			// Left by an interrupted backup (pruning runs under the lock: no other backup is in progress).
			_ = os.RemoveAll(filepath.Join(snapshots, e.Name()))
			continue
		}
		t, err := time.ParseInLocation(stampLayout, e.Name(), now.Location())
		if err != nil {
			continue
		}
		if t.Before(cutoff) {
			if err := os.RemoveAll(filepath.Join(snapshots, e.Name())); err != nil {
				return err
			}
			continue
		}
		ids, ok := manifestBlobIDs(filepath.Join(snapshots, e.Name()))
		if !ok {
			complete = false
		}
		for _, id := range ids {
			needed[id] = true
		}
	}
	if !complete {
		// A kept snapshot does not say which attachments it needs: keep them all until it is pruned.
		return nil
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
			if needed[u.Name()+"/"+f.Name()] {
				continue
			}
			// A ".tmp" is a copy left by an interruption (one of an older server still running during an
			// upgrade, which does not take the lock, is younger than an hour).
			if info, err := f.Info(); err == nil && strings.HasSuffix(f.Name(), ".tmp") && time.Since(info.ModTime()) < time.Hour {
				continue
			}
			_ = os.Remove(filepath.Join(root, "blobs", u.Name(), f.Name()))
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
	// MissingBlobs counts the attachments the database lists but the server no longer has (latest backup).
	MissingBlobs int `json:"missingBlobs,omitempty"`
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
		s.MissingBlobs = len(missingBlobs(dir))
	}
	if b, jerr := json.Marshal(s); jerr == nil {
		_ = os.WriteFile(statusPath(cfg), b, 0o600)
	}
	return dir, err
}

// RunDaily makes a backup every day at cfg.Backup.Hour:30 (local time), and soon after the start if the
// latest one was missed (e.g. the computer was off at backup time). It waits for a clock it can trust: after
// a power cut an NVIDIA Jetson starts in 1970 until the network time arrives.
func RunDaily(ctx context.Context, cfg *config.Config, st *store.Store, log *slog.Logger) {
	started := time.Now()
	timer := time.NewTimer(30 * time.Second)
	defer timer.Stop()
	var retryAt time.Time
	waiting := false
	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
		}
		timer.Reset(time.Minute)
		now := time.Now()
		if !ClockTrusted(now, time.Since(started)) {
			if !waiting {
				log.Info("backup: waiting for the clock to be synchronized", "now", now.Format(time.RFC3339))
				waiting = true
			}
			continue
		}
		waiting = false
		if now.Before(retryAt) || !due(now, latestSnapshot(cfg, now), cfg.Backup.Hour) {
			continue
		}
		if dir, err := RunAndRecord(ctx, cfg, st); err != nil {
			log.Error("backup failed", "dir", Dir(cfg), "error", err)
			retryAt = now.Add(time.Hour)
		} else {
			log.Info("backup done", "dir", dir)
			if missing := missingBlobs(dir); len(missing) > 0 {
				log.Warn("attachments missing on the server (the copies in the backups are kept)", "blobs", missing)
			}
		}
	}
}

// minTrustedTime is earlier than any real date this program can run at: a clock before it was reset.
var minTrustedTime = time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

// timesyncDir is where systemd-timesyncd marks a synchronized clock (Linux).
var timesyncDir = "/run/systemd/timesync"

// ClockTrusted reports whether the wall clock can name and schedule backups: not reset to 1970, and, where
// systemd-timesyncd is used, synchronized with the network (or up for a while: the network may be missing).
func ClockTrusted(now time.Time, up time.Duration) bool {
	if now.Before(minTrustedTime) {
		return false
	}
	if _, err := os.Stat(timesyncDir); err != nil {
		return true // no timesyncd (macOS, or another time service)
	}
	if _, err := os.Stat(filepath.Join(timesyncDir, "synchronized")); err == nil {
		return true
	}
	return up > 15*time.Minute
}

// lastSlot is the latest scheduled backup time (hour:30) at or before now.
func lastSlot(now time.Time, hour int) time.Time {
	t := time.Date(now.Year(), now.Month(), now.Day(), hour, 30, 0, 0, now.Location())
	if t.After(now) {
		t = time.Date(now.Year(), now.Month(), now.Day()-1, hour, 30, 0, 0, now.Location())
	}
	return t
}

// due reports whether a backup is needed at now: none yet, or the latest is older than the last slot.
func due(now, latest time.Time, hour int) bool {
	return latest.IsZero() || latest.Before(lastSlot(now, hour))
}

// latestSnapshot returns the time of the newest snapshot, ignoring any dated in the future (made while the
// clock was wrong); zero if there is none.
func latestSnapshot(cfg *config.Config, now time.Time) time.Time {
	names, _ := Snapshots(cfg)
	var latest time.Time
	for _, n := range names {
		t, err := time.ParseInLocation(stampLayout, n, now.Location())
		if err == nil && !t.After(now.Add(time.Hour)) && t.After(latest) {
			latest = t
		}
	}
	return latest
}
