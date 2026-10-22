package backup

import (
	"bytes"
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/simonescoca/the.vault/server/internal/blobs"
	"github.com/simonescoca/the.vault/server/internal/config"
	"github.com/simonescoca/the.vault/server/internal/store"
)

const uid = "11111111-1111-4111-8111-111111111111"
const bid = "22222222-2222-4222-8222-222222222222"

func TestSnapshotsBlobsAndPruning(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	cfg := config.Default(dir)
	cfg.Backup.Dir = filepath.Join(t.TempDir(), "backups")
	cfg.Backup.KeepDays = 2
	st, err := store.Open(filepath.Join(dir, "thevault.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	if _, err := st.EnsureUser(ctx, uid, "a@b.it"); err != nil {
		t.Fatal(err)
	}
	// One complete blob on disk.
	files := &blobs.Files{Dir: dir}
	content := []byte("encrypted attachment bytes")
	if err := files.WritePart(uid, bid, 0, int64(len(content)), bytes.NewReader(content)); err != nil {
		t.Fatal(err)
	}
	if _, err := files.Finalize(uid, bid, int64(len(content))); err != nil {
		t.Fatal(err)
	}
	st.CreateBlob(ctx, &store.Blob{UserID: uid, ID: bid, Size: int64(len(content)), PartSize: 1024})
	st.CompleteBlob(ctx, uid, bid, "x")

	now := time.Date(2026, 10, 2, 3, 30, 0, 0, time.Local)
	old, err := run(ctx, cfg, st, now.Add(-5*24*time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	snap, err := run(ctx, cfg, st, now)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(old); !os.IsNotExist(err) {
		t.Fatalf("old snapshot must be pruned: %v", err)
	}
	// The snapshot is a valid database.
	copyDB, err := store.Open(filepath.Join(snap, "thevault.db"))
	if err != nil {
		t.Fatalf("snapshot db: %v", err)
	}
	if u, err := copyDB.UserByEmail(ctx, "a@b.it"); err != nil || u.ID != uid {
		t.Fatalf("snapshot content: %v %v", u, err)
	}
	copyDB.Close()
	got, err := os.ReadFile(filepath.Join(cfg.Backup.Dir, "blobs", uid, bid))
	if err != nil || !bytes.Equal(got, content) {
		t.Fatalf("pooled blob: %v", err)
	}
	snaps, _ := Snapshots(cfg)
	if len(snaps) != 1 {
		t.Fatalf("snapshots: %v", snaps)
	}
}

func TestScheduleSlotsAndCatchUp(t *testing.T) {
	rome, err := time.LoadLocation("Europe/Rome")
	if err != nil {
		t.Skip("no time zone data:", err)
	}
	at := func(m time.Month, d, h, min int) time.Time { return time.Date(2026, m, d, h, min, 0, 0, rome) }
	cases := []struct {
		now, latest time.Time
		want        bool
	}{
		{at(10, 2, 10, 0), time.Time{}, true},         // never made one
		{at(10, 2, 10, 0), at(10, 1, 3, 30), true},    // off at 03:30 today: catch up now
		{at(10, 2, 10, 0), at(10, 2, 3, 30), false},   // today's is there
		{at(10, 2, 3, 29), at(10, 1, 3, 30), false},   // not yet time
		{at(10, 2, 3, 31), at(10, 1, 3, 30), true},    // time
		{at(10, 25, 3, 31), at(10, 24, 3, 30), true},  // end of summer time: one backup that night
		{at(10, 25, 2, 31), at(10, 24, 3, 30), false}, // ...not two (the old timer added 24 hours)
		{at(10, 26, 1, 0), at(10, 25, 3, 31), false},  // next night not yet
		{at(3, 29, 3, 31), at(3, 28, 3, 30), true},    // start of summer time
		{at(10, 2, 10, 0), at(10, 3, 3, 30), true},    // a snapshot "from the future" does not count…
	}
	for i, c := range cases {
		latest := c.latest
		if latest.After(c.now.Add(time.Hour)) {
			latest = time.Time{} // …latestSnapshot ignores it
		}
		if got := due(c.now, latest, 3); got != c.want {
			t.Errorf("case %d: due(%v, %v) = %v, want %v", i, c.now, c.latest, got, c.want)
		}
	}
	if s := lastSlot(at(10, 25, 12, 0), 3); s.Hour() != 3 || s.Minute() != 30 || s.Day() != 25 {
		t.Fatalf("slot on the day summer time ends: %v", s)
	}
}

func TestClockTrusted(t *testing.T) {
	ts := t.TempDir()
	old := timesyncDir
	t.Cleanup(func() { timesyncDir = old })
	now := time.Date(2026, 10, 22, 18, 0, 0, 0, time.UTC)

	timesyncDir = filepath.Join(ts, "absent")
	if !ClockTrusted(now, 0) {
		t.Fatal("no timesyncd: a plausible clock is trusted")
	}
	if ClockTrusted(time.Date(1970, 1, 1, 0, 0, 23, 0, time.UTC), time.Hour) {
		t.Fatal("1970 (a Jetson after a power cut) must not be trusted")
	}
	timesyncDir = ts
	if ClockTrusted(now, time.Minute) {
		t.Fatal("timesyncd not synchronized yet: wait")
	}
	if !ClockTrusted(now, 20*time.Minute) {
		t.Fatal("no network for a long time: go on with the clock we have")
	}
	os.WriteFile(filepath.Join(ts, "synchronized"), nil, 0o600)
	if !ClockTrusted(now, time.Minute) {
		t.Fatal("synchronized clock not trusted")
	}
}

// pool lays out a backup folder: snapshots (name → attachments listed, nil = old manifest) and pooled files.
func pool(t *testing.T, snaps map[string][]string, files ...string) string {
	t.Helper()
	root := t.TempDir()
	for name, ids := range snaps {
		dir := filepath.Join(root, "snapshots", name)
		os.MkdirAll(dir, 0o700)
		m := map[string]any{"createdAt": name}
		if ids != nil {
			m["blobIds"] = ids
		}
		b, _ := json.Marshal(m)
		os.WriteFile(filepath.Join(dir, "manifest.json"), b, 0o600)
	}
	for _, f := range files {
		os.MkdirAll(filepath.Join(root, "blobs", filepath.Dir(f)), 0o700)
		os.WriteFile(filepath.Join(root, "blobs", f), []byte("x"), 0o600)
	}
	return root
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func TestPruneKeepsAttachmentsOfKeptSnapshots(t *testing.T) {
	now := time.Date(2026, 11, 30, 3, 30, 0, 0, time.Local)
	// "u/a" was uploaded long ago and deleted on the server since; the snapshot of 15 days ago still needs it.
	root := pool(t, map[string][]string{
		"2026-10-01_033000": {"u/a"},
		"2026-11-15_033000": {"u/a", "u/b"},
		"2026-11-30_033000": {"u/b"},
	}, "u/a", "u/b", "u/old")
	old := filepath.Join(root, "blobs", "u", "a")
	os.Chtimes(old, now.AddDate(0, -3, 0), now.AddDate(0, -3, 0))
	if err := prune(root, 30, now); err != nil {
		t.Fatal(err)
	}
	if exists(filepath.Join(root, "snapshots", "2026-10-01_033000")) {
		t.Fatal("snapshot older than 30 days kept")
	}
	if !exists(old) || !exists(filepath.Join(root, "blobs", "u", "b")) {
		t.Fatal("an attachment needed by a kept snapshot was deleted")
	}
	if exists(filepath.Join(root, "blobs", "u", "old")) {
		t.Fatal("an attachment no snapshot needs was kept")
	}
	// Once the last snapshot that needs it is gone, it goes too.
	if err := prune(root, 30, now.AddDate(0, 0, 16)); err != nil {
		t.Fatal(err)
	}
	if exists(old) {
		t.Fatal("attachment of pruned snapshots kept")
	}
}

func TestPruneWithAnOldManifestKeepsThePool(t *testing.T) {
	now := time.Date(2026, 11, 30, 3, 30, 0, 0, time.Local)
	root := pool(t, map[string][]string{"2026-11-20_033000": nil, "2026-11-30_033000": {}}, "u/a")
	if err := prune(root, 30, now); err != nil {
		t.Fatal(err)
	}
	if !exists(filepath.Join(root, "blobs", "u", "a")) {
		t.Fatal("a snapshot that does not list its attachments may need this one")
	}
}

func TestMissingAttachmentAndUnfinishedSnapshots(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	cfg := config.Default(dir)
	cfg.Backup.Dir = filepath.Join(t.TempDir(), "backups")
	st, err := store.Open(filepath.Join(dir, "thevault.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	st.EnsureUser(ctx, uid, "a@b.it")
	// Complete in the database, but its file is gone.
	st.CreateBlob(ctx, &store.Blob{UserID: uid, ID: bid, Size: 10, PartSize: 1024})
	st.CompleteBlob(ctx, uid, bid, "x")
	// Left by a backup interrupted two hours ago.
	stale := filepath.Join(cfg.Backup.Dir, "snapshots", ".tmp-2026-10-01_033000-123")
	os.MkdirAll(stale, 0o700)
	os.Chtimes(stale, time.Now().Add(-2*time.Hour), time.Now().Add(-2*time.Hour))

	snap, err := Run(ctx, cfg, st)
	if err != nil {
		t.Fatalf("a missing attachment must not fail the backup: %v", err)
	}
	b, _ := os.ReadFile(filepath.Join(snap, "manifest.json"))
	var m manifest
	json.Unmarshal(b, &m)
	if len(m.MissingBlobs) != 1 || len(m.BlobIDs) != 0 {
		t.Fatalf("manifest: %s", b)
	}
	if exists(stale) {
		t.Fatal("unfinished snapshot not removed")
	}
	if snaps, _ := Snapshots(cfg); len(snaps) != 1 {
		t.Fatalf("snapshots: %v", snaps)
	}
	if latest := latestSnapshot(cfg, time.Now()); latest.IsZero() || time.Since(latest) > time.Minute {
		t.Fatalf("latest snapshot: %v", latest)
	}
}

func TestRunAndRecordKeepsTheOutcome(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	cfg := config.Default(dir)
	cfg.Backup.Dir = filepath.Join(t.TempDir(), "backups")
	st, err := store.Open(filepath.Join(dir, "thevault.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	if s := ReadStatus(cfg); s.LastAttempt != 0 {
		t.Fatalf("status before any backup: %+v", s)
	}
	snap, err := RunAndRecord(ctx, cfg, st)
	if err != nil {
		t.Fatal(err)
	}
	ok := ReadStatus(cfg)
	if ok.LastSuccess == 0 || ok.LastSuccess != ok.LastAttempt || ok.LastDir != snap || ok.LastError != "" {
		t.Fatalf("after a good backup: %+v", ok)
	}
	// A folder that cannot be written (here: a file where the folder should be) is recorded as a failure,
	// and the last good backup is still known.
	blocker := filepath.Join(t.TempDir(), "not-a-folder")
	if err := os.WriteFile(blocker, []byte("x"), 0o600); err != nil {
		t.Fatal(err)
	}
	cfg.Backup.Dir = blocker
	if _, err := RunAndRecord(ctx, cfg, st); err == nil {
		t.Fatal("backup into a file should fail")
	}
	bad := ReadStatus(cfg)
	if bad.LastError == "" || bad.LastSuccess != ok.LastSuccess || bad.LastAttempt < ok.LastAttempt {
		t.Fatalf("after a failed backup: %+v", bad)
	}
}

func TestTheOnlyCopyOfALostAttachmentIsKept(t *testing.T) {
	ctx := context.Background()
	dir := t.TempDir()
	cfg := config.Default(dir)
	cfg.Backup.Dir = filepath.Join(t.TempDir(), "backups")
	cfg.Backup.KeepDays = 2
	st, err := store.Open(filepath.Join(dir, "thevault.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	st.EnsureUser(ctx, uid, "a@b.it")
	files := &blobs.Files{Dir: dir}
	content := []byte("encrypted attachment bytes")
	files.WritePart(uid, bid, 0, int64(len(content)), bytes.NewReader(content))
	files.Finalize(uid, bid, int64(len(content)))
	st.CreateBlob(ctx, &store.Blob{UserID: uid, ID: bid, Size: int64(len(content)), PartSize: 1024})
	st.CompleteBlob(ctx, uid, bid, "x")
	now := time.Date(2026, 10, 2, 3, 30, 0, 0, time.Local)
	if _, err := run(ctx, cfg, st, now); err != nil {
		t.Fatal(err)
	}
	// The server loses the file; weeks later the first snapshot is pruned, but the pooled copy must stay.
	os.Remove(files.BlobPath(uid, bid))
	snap, err := run(ctx, cfg, st, now.AddDate(0, 0, 20))
	if err != nil {
		t.Fatal(err)
	}
	if !exists(filepath.Join(cfg.Backup.Dir, "blobs", uid, bid)) {
		t.Fatal("the only remaining copy of the attachment was pruned")
	}
	if m := missingBlobs(snap); len(m) != 1 {
		t.Fatalf("missing: %v", m)
	}
	if _, err := RunAndRecord(ctx, cfg, st); err != nil {
		t.Fatal(err)
	}
	if s := ReadStatus(cfg); s.MissingBlobs != 1 {
		t.Fatalf("status: %+v", s)
	}
}
