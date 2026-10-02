package api

import (
	"context"
	"time"

	"github.com/simonescoca/the.vault/server/internal/store"
)

// RunMaintenance runs periodic housekeeping until ctx is cancelled.
func (s *Server) RunMaintenance(ctx context.Context, every time.Duration) {
	t := time.NewTicker(every)
	defer t.Stop()
	for {
		s.MaintenanceOnce(ctx)
		select {
		case <-ctx.Done():
			return
		case <-t.C:
		}
	}
}

// MaintenanceOnce expires approval requests, purges old ones and garbage-collects orphan blobs.
func (s *Server) MaintenanceOnce(ctx context.Context) {
	expired, err := s.Store.ExpireApprovals(ctx)
	if err != nil {
		s.Log.Error("expire approvals", "error", err)
	}
	for _, a := range expired {
		ev := event("approval.closed", map[string]any{"approvalId": a.ID, "state": store.ApprovalExpired})
		s.Hub.ToDevice(a.UserID, a.DeviceID, ev)
		s.Hub.ToActive(a.UserID, "", ev)
	}
	if err := s.Store.PurgeApprovals(ctx, nowMs()-24*time.Hour.Milliseconds()); err != nil {
		s.Log.Error("purge approvals", "error", err)
	}
	orphans, err := s.Store.OrphanBlobs(ctx, nowMs()-blobGracePeriod.Milliseconds())
	if err != nil {
		s.Log.Error("orphan blobs", "error", err)
		return
	}
	for _, b := range orphans {
		if err := s.Files.Delete(b.UserID, b.ID); err != nil {
			s.Log.Error("delete blob file", "blob", b.ID, "error", err)
			continue
		}
		if err := s.Store.DeleteBlob(ctx, b.UserID, b.ID); err != nil {
			s.Log.Error("delete blob", "blob", b.ID, "error", err)
		}
	}
	if len(orphans) > 0 {
		s.Log.Info("orphan attachments removed", "count", len(orphans))
	}
}
