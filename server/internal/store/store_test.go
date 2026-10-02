package store

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
)

func newStore(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "db.sqlite"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestMigrateIsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "db.sqlite")
	for i := 0; i < 2; i++ {
		s, err := Open(path)
		if err != nil {
			t.Fatalf("open %d: %v", i, err)
		}
		s.Close()
	}
}

func setupUserDevice(t *testing.T, s *Store, status string) (*User, *Device) {
	t.Helper()
	ctx := context.Background()
	u, err := s.EnsureUser(ctx, "u1", "a@b.it")
	if err != nil {
		t.Fatal(err)
	}
	d := &Device{ID: "d-" + status, UserID: u.ID, Name: "Mac", Platform: "macos", PublicKey: []byte{1}, Status: status}
	if err := s.CreateDevice(ctx, d, []byte("hash-"+status)); err != nil {
		t.Fatal(err)
	}
	return u, d
}

func TestUsersDevicesAndVaultInit(t *testing.T) {
	ctx := context.Background()
	s := newStore(t)
	u, d1 := setupUserDevice(t, s, StatusSetup)
	again, err := s.EnsureUser(ctx, "other-id", "a@b.it")
	if err != nil || again.ID != u.ID {
		t.Fatalf("EnsureUser must return the existing user: %v %v", again, err)
	}
	got, err := s.DeviceByTokenHash(ctx, []byte("hash-setup"))
	if err != nil || got.ID != d1.ID {
		t.Fatalf("DeviceByTokenHash: %v %v", got, err)
	}
	if _, err := s.DeviceByTokenHash(ctx, []byte("nope")); !errors.Is(err, ErrNotFound) {
		t.Fatalf("want ErrNotFound, got %v", err)
	}

	// Second setup device racing for the init.
	d2 := &Device{ID: "d2", UserID: u.ID, Name: "PC", Platform: "windows", PublicKey: []byte{2}, Status: StatusSetup}
	if err := s.CreateDevice(ctx, d2, []byte("hash-d2")); err != nil {
		t.Fatal(err)
	}
	rec := Recovery{Salt: []byte("salt"), OpsLimit: 2, MemLimit: 64 << 20, Wrap: []byte("wrap"), AuthHash: []byte("auth")}
	if err := s.InitVault(ctx, u.ID, d1.ID, []byte("kc"), rec); err != nil {
		t.Fatalf("InitVault: %v", err)
	}
	if err := s.InitVault(ctx, u.ID, d2.ID, []byte("kc2"), rec); !errors.Is(err, ErrAlreadyInitialized) {
		t.Fatalf("second InitVault: want ErrAlreadyInitialized, got %v", err)
	}
	u, _ = s.User(ctx, u.ID)
	if !u.VaultInitialized || string(u.KeyCheck) != "kc" {
		t.Fatalf("vault not initialized correctly: %+v", u)
	}
	if d, _ := s.Device(ctx, d1.ID); d.Status != StatusActive {
		t.Fatalf("first device should be active, is %s", d.Status)
	}
	if d, _ := s.Device(ctx, d2.ID); d.Status != StatusPending {
		t.Fatalf("losing device should be pending, is %s", d.Status)
	}
}

func TestRecordsRevisionsConflictsAndTombstones(t *testing.T) {
	ctx := context.Background()
	s := newStore(t)
	u, d := setupUserDevice(t, s, StatusActive)

	rev1, _, err := s.PutRecord(ctx, u.ID, d.ID, "r1", 0, []byte("v1"), nil)
	if err != nil || rev1 != 1 {
		t.Fatalf("put r1: rev=%d err=%v", rev1, err)
	}
	rev2, _, err := s.PutRecord(ctx, u.ID, d.ID, "r2", 0, []byte("x"), nil)
	if err != nil || rev2 != 2 {
		t.Fatalf("put r2: rev=%d err=%v", rev2, err)
	}
	// Creating r1 again with baseRev 0 is a conflict.
	_, _, err = s.PutRecord(ctx, u.ID, d.ID, "r1", 0, []byte("v1b"), nil)
	var ce *ConflictError
	if !errors.As(err, &ce) || ce.Current.Rev != rev1 || string(ce.Current.Data) != "v1" {
		t.Fatalf("want conflict with current rev %d, got %v", rev1, err)
	}
	rev3, _, err := s.PutRecord(ctx, u.ID, d.ID, "r1", rev1, []byte("v2"), nil)
	if err != nil || rev3 != 3 {
		t.Fatalf("update r1: rev=%d err=%v", rev3, err)
	}
	recs, more, latest, err := s.RecordsSince(ctx, u.ID, 0, 10)
	if err != nil || more || latest != 3 || len(recs) != 2 || recs[0].ID != "r2" || recs[1].ID != "r1" {
		t.Fatalf("RecordsSince: %v more=%v latest=%d err=%v", recs, more, latest, err)
	}
	recs, more, _, _ = s.RecordsSince(ctx, u.ID, 0, 1)
	if len(recs) != 1 || !more {
		t.Fatalf("pagination: %d more=%v", len(recs), more)
	}
	// Tombstone.
	rev4, _, err := s.DeleteRecord(ctx, u.ID, d.ID, "r1", rev3)
	if err != nil || rev4 != 4 {
		t.Fatalf("delete: %d %v", rev4, err)
	}
	r, _ := s.Record(ctx, u.ID, "r1")
	if !r.Deleted || r.Data != nil {
		t.Fatalf("tombstone expected: %+v", r)
	}
	if _, _, err := s.DeleteRecord(ctx, u.ID, d.ID, "nope", 0); !errors.Is(err, ErrNotFound) {
		t.Fatalf("delete unknown: %v", err)
	}
}

func TestBlobReferencesAndOrphans(t *testing.T) {
	ctx := context.Background()
	s := newStore(t)
	u, d := setupUserDevice(t, s, StatusActive)

	// A record cannot reference an unknown or incomplete blob.
	_, _, err := s.PutRecord(ctx, u.ID, d.ID, "r1", 0, []byte("v"), []string{"b1"})
	var mb *MissingBlobError
	if !errors.As(err, &mb) || len(mb.IDs) != 1 {
		t.Fatalf("want missing blob, got %v", err)
	}
	if err := s.CreateBlob(ctx, &Blob{UserID: u.ID, ID: "b1", Size: 10, PartSize: 4}); err != nil {
		t.Fatal(err)
	}
	if _, _, err := s.PutRecord(ctx, u.ID, d.ID, "r1", 0, []byte("v"), []string{"b1"}); !errors.As(err, &mb) {
		t.Fatalf("incomplete blob must be rejected: %v", err)
	}
	if err := s.CompleteBlob(ctx, u.ID, "b1", "abc"); err != nil {
		t.Fatal(err)
	}
	rev, _, err := s.PutRecord(ctx, u.ID, d.ID, "r1", 0, []byte("v"), []string{"b1"})
	if err != nil {
		t.Fatal(err)
	}
	old := NowMillis
	defer func() { NowMillis = old }()
	future := NowMillis() + 10
	if orphans, _ := s.OrphanBlobs(ctx, future); len(orphans) != 0 {
		t.Fatalf("referenced blob must not be orphan: %v", orphans)
	}
	// Remove the reference: the blob becomes an orphan after the grace period.
	if _, _, err := s.PutRecord(ctx, u.ID, d.ID, "r1", rev, []byte("v2"), nil); err != nil {
		t.Fatal(err)
	}
	if orphans, _ := s.OrphanBlobs(ctx, future+10); len(orphans) != 1 || orphans[0].ID != "b1" {
		t.Fatalf("want orphan b1, got %v", orphans)
	}
}

func TestApprovalTransitions(t *testing.T) {
	ctx := context.Background()
	s := newStore(t)
	u, d1 := setupUserDevice(t, s, StatusActive)
	d2 := &Device{ID: "d2", UserID: u.ID, Name: "PC", Platform: "windows", PublicKey: []byte{2}, Status: StatusPending}
	if err := s.CreateDevice(ctx, d2, []byte("h2")); err != nil {
		t.Fatal(err)
	}
	a := &Approval{ID: "a1", UserID: u.ID, DeviceID: d2.ID, Commitment: []byte("c"), ExpiresAt: NowMillis() + 60_000}
	if _, err := s.CreateApproval(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := s.RevealApproval(ctx, "a1", []byte("n2")); !errors.Is(err, ErrApprovalState) {
		t.Fatalf("reveal before respond must fail: %v", err)
	}
	if err := s.RespondApproval(ctx, "a1", d1.ID, []byte("pk1"), []byte("n1")); err != nil {
		t.Fatal(err)
	}
	if err := s.RespondApproval(ctx, "a1", d1.ID, []byte("pk1"), []byte("n1")); !errors.Is(err, ErrApprovalState) {
		t.Fatalf("second respond must fail: %v", err)
	}
	if err := s.RevealApproval(ctx, "a1", []byte("n2")); err != nil {
		t.Fatal(err)
	}
	got, _ := s.Approval(ctx, "a1")
	if err := s.ApproveApproval(ctx, got, []byte("box"), []byte("bn")); err != nil {
		t.Fatal(err)
	}
	if d, _ := s.Device(ctx, d2.ID); d.Status != StatusActive {
		t.Fatalf("device should be active after approval, is %s", d.Status)
	}
	// A new request cancels the previous open one of the same device.
	b1 := &Approval{ID: "b1", UserID: u.ID, DeviceID: "d3", Commitment: []byte("c"), ExpiresAt: NowMillis() + 60_000}
	b2 := &Approval{ID: "b2", UserID: u.ID, DeviceID: "d3", Commitment: []byte("c"), ExpiresAt: NowMillis() + 60_000}
	s.CreateApproval(ctx, b1)
	cancelled, _ := s.CreateApproval(ctx, b2)
	if len(cancelled) != 1 || cancelled[0] != "b1" {
		t.Fatalf("want b1 cancelled, got %v", cancelled)
	}
	// Expiry.
	old := NowMillis
	defer func() { NowMillis = old }()
	base := NowMillis()
	NowMillis = func() int64 { return base + 120_000 }
	expired, err := s.ExpireApprovals(ctx)
	if err != nil || len(expired) != 1 || expired[0].ID != "b2" {
		t.Fatalf("want b2 expired, got %v %v", expired, err)
	}
}
