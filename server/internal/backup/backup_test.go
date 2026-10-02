package backup

import (
	"bytes"
	"context"
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

func TestNextRun(t *testing.T) {
	loc := time.Local
	n := nextRun(time.Date(2026, 10, 2, 1, 0, 0, 0, loc), 3)
	if n.Day() != 2 || n.Hour() != 3 || n.Minute() != 30 {
		t.Fatalf("same day: %v", n)
	}
	n = nextRun(time.Date(2026, 10, 2, 4, 0, 0, 0, loc), 3)
	if n.Day() != 3 || n.Hour() != 3 {
		t.Fatalf("next day: %v", n)
	}
}
