package api

import (
	"crypto/sha256"
	"crypto/subtle"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/simonescoca/the.vault/server/internal/hub"
	"github.com/simonescoca/the.vault/server/internal/mail"
	"github.com/simonescoca/the.vault/server/internal/store"
)

func event(typ string, data map[string]any) hub.Event { return hub.Event{Type: typ, Data: data} }

// --- devices ---

func (s *Server) listDevices(w http.ResponseWriter, r *http.Request) {
	me := device(r)
	devs, err := s.Store.Devices(r.Context(), me.UserID)
	if err != nil {
		s.internal(w, err)
		return
	}
	out := []map[string]any{}
	for _, d := range devs {
		out = append(out, map[string]any{"id": d.ID, "name": d.Name, "platform": d.Platform, "status": d.Status,
			"createdAt": d.CreatedAt, "lastSeenAt": d.LastSeenAt, "current": d.ID == me.ID})
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": out})
}

func (s *Server) renameSelf(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name string `json:"name"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	name := strings.TrimSpace(req.Name)
	if name == "" || utf8.RuneCountInString(name) > 64 {
		writeError(w, http.StatusBadRequest, "invalid_field", "invalid name")
		return
	}
	d := device(r)
	if err := s.Store.RenameDevice(r.Context(), d.ID, name); err != nil {
		s.internal(w, err)
		return
	}
	s.Hub.ToActive(d.UserID, "", event("devices.changed", nil))
	writeJSON(w, http.StatusOK, map[string]any{})
}

func (s *Server) deleteSelf(w http.ResponseWriter, r *http.Request) {
	d := device(r)
	s.closeApprovalsOf(r, d)
	if err := s.Store.DeleteDevice(r.Context(), d.ID); err != nil {
		s.internal(w, err)
		return
	}
	s.Hub.Disconnect(d.UserID, d.ID, nil)
	s.Hub.ToActive(d.UserID, d.ID, event("devices.changed", nil))
	s.Log.Info("device signed out", "device", d.ID)
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) revokeDevice(w http.ResponseWriter, r *http.Request) {
	me := device(r)
	id := r.PathValue("id")
	if id == me.ID {
		writeError(w, http.StatusBadRequest, "bad_request", "use DELETE /v1/devices/self to sign out")
		return
	}
	target, err := s.Store.Device(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) || (err == nil && target.UserID != me.UserID) {
		writeError(w, http.StatusNotFound, "not_found", "no such device")
		return
	}
	if err != nil {
		s.internal(w, err)
		return
	}
	s.closeApprovalsOf(r, target)
	if err := s.Store.DeleteDevice(r.Context(), id); err != nil {
		s.internal(w, err)
		return
	}
	final := event("device.revoked", nil)
	s.Hub.Disconnect(me.UserID, id, &final)
	s.Hub.ToActive(me.UserID, "", event("devices.changed", nil))
	s.Log.Info("device revoked", "device", id, "by", me.ID)
	w.WriteHeader(http.StatusNoContent)
}

// closeApprovalsOf cancels the open approval requests of a device that is going away.
func (s *Server) closeApprovalsOf(r *http.Request, d *store.Device) {
	open, err := s.Store.OpenApprovals(r.Context(), d.UserID)
	if err != nil {
		return
	}
	for _, a := range open {
		if a.DeviceID == d.ID && s.Store.CloseApproval(r.Context(), a.ID, store.ApprovalCancelled) == nil {
			s.Hub.ToActive(d.UserID, "", event("approval.closed", map[string]any{"approvalId": a.ID, "state": store.ApprovalCancelled}))
		}
	}
}

// --- approvals ---

// approvalView renders an approval for a viewer. The sealed box is only shown to the requesting device.
func (s *Server) approvalView(a *store.Approval, viewer *store.Device, reqDev *store.Device) map[string]any {
	state := a.State
	if store.ApprovalOpen(state) && nowMs() > a.ExpiresAt {
		state = store.ApprovalExpired
	}
	v := map[string]any{
		"id":                 a.ID,
		"state":              state,
		"commitment":         b64(a.Commitment),
		"responderPublicKey": b64OrNil(a.ResponderPublicKey),
		"responderNonce":     b64OrNil(a.ResponderNonce),
		"revealedNonce":      b64OrNil(a.RevealedNonce),
		"box":                nil,
		"boxNonce":           nil,
		"createdAt":          a.CreatedAt,
		"expiresAt":          a.ExpiresAt,
	}
	if reqDev != nil {
		v["device"] = map[string]any{"id": reqDev.ID, "name": reqDev.Name, "platform": reqDev.Platform, "publicKey": b64(reqDev.PublicKey)}
	}
	if a.ResponderDeviceID.Valid {
		v["responderDeviceId"] = a.ResponderDeviceID.String
	}
	if viewer != nil && viewer.ID == a.DeviceID {
		v["box"], v["boxNonce"] = b64OrNil(a.Box), b64OrNil(a.BoxNonce)
	}
	return v
}

// loadApproval loads an approval visible to the caller: its own request, or any request of the
// same user for an active device.
func (s *Server) loadApproval(w http.ResponseWriter, r *http.Request) (*store.Approval, *store.Device, bool) {
	me := device(r)
	a, err := s.Store.Approval(r.Context(), r.PathValue("id"))
	if errors.Is(err, store.ErrNotFound) || (err == nil && (a.UserID != me.UserID || (me.Status != store.StatusActive && a.DeviceID != me.ID))) {
		writeError(w, http.StatusNotFound, "not_found", "no such approval request")
		return nil, nil, false
	}
	if err != nil {
		s.internal(w, err)
		return nil, nil, false
	}
	reqDev, err := s.Store.Device(r.Context(), a.DeviceID)
	if err != nil && !errors.Is(err, store.ErrNotFound) {
		s.internal(w, err)
		return nil, nil, false
	}
	return a, reqDev, true
}

func (s *Server) stateError(w http.ResponseWriter, a *store.Approval) {
	if nowMs() > a.ExpiresAt && store.ApprovalOpen(a.State) {
		writeError(w, http.StatusGone, "approval_expired", "the request has expired")
		return
	}
	writeError(w, http.StatusConflict, "conflict", "the request is in state "+a.State)
}

func (s *Server) createApproval(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Commitment string `json:"commitment"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	c, ok := decodeField(w, "commitment", req.Commitment, 32, true)
	if !ok {
		return
	}
	me := device(r)
	u, err := s.Store.User(r.Context(), me.UserID)
	if err != nil {
		s.internal(w, err)
		return
	}
	if u.ApprovalsPausedUntil > nowMs() {
		tooMany(w, time.Duration(u.ApprovalsPausedUntil-nowMs())*time.Millisecond)
		return
	}
	a := &store.Approval{ID: newID(), UserID: me.UserID, DeviceID: me.ID, Commitment: c, ExpiresAt: nowMs() + approvalTTL.Milliseconds()}
	cancelled, err := s.Store.CreateApproval(r.Context(), a)
	if err != nil {
		s.internal(w, err)
		return
	}
	for _, id := range cancelled {
		s.Hub.ToActive(me.UserID, "", event("approval.closed", map[string]any{"approvalId": id, "state": store.ApprovalCancelled}))
	}
	s.Hub.ToActive(me.UserID, "", event("approval.requested", map[string]any{"approval": s.approvalView(a, nil, me)}))
	s.Log.Info("approval requested", "approval", a.ID, "device", me.ID)
	writeJSON(w, http.StatusCreated, map[string]any{"approvalId": a.ID, "expiresAt": a.ExpiresAt})
}

func (s *Server) listApprovals(w http.ResponseWriter, r *http.Request) {
	me := device(r)
	open, err := s.Store.OpenApprovals(r.Context(), me.UserID)
	if err != nil {
		s.internal(w, err)
		return
	}
	out := []map[string]any{}
	for _, a := range open {
		reqDev, err := s.Store.Device(r.Context(), a.DeviceID)
		if err != nil {
			continue
		}
		out = append(out, s.approvalView(a, me, reqDev))
	}
	writeJSON(w, http.StatusOK, map[string]any{"approvals": out})
}

func (s *Server) getApproval(w http.ResponseWriter, r *http.Request) {
	a, reqDev, ok := s.loadApproval(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, s.approvalView(a, device(r), reqDev))
}

func (s *Server) cancelApproval(w http.ResponseWriter, r *http.Request) {
	a, _, ok := s.loadApproval(w, r)
	if !ok {
		return
	}
	if err := s.Store.CloseApproval(r.Context(), a.ID, store.ApprovalCancelled); err != nil {
		if errors.Is(err, store.ErrApprovalState) {
			s.stateError(w, a)
			return
		}
		s.internal(w, err)
		return
	}
	s.Hub.ToActive(a.UserID, "", event("approval.closed", map[string]any{"approvalId": a.ID, "state": store.ApprovalCancelled}))
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) respondApproval(w http.ResponseWriter, r *http.Request) {
	var req struct {
		PublicKey string `json:"publicKey"`
		Nonce     string `json:"nonce"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	pk, ok := decodeField(w, "publicKey", req.PublicKey, 32, true)
	if !ok {
		return
	}
	n1, ok := decodeField(w, "nonce", req.Nonce, 32, true)
	if !ok {
		return
	}
	a, reqDev, ok := s.loadApproval(w, r)
	if !ok {
		return
	}
	me := device(r)
	if err := s.Store.RespondApproval(r.Context(), a.ID, me.ID, pk, n1); err != nil {
		if errors.Is(err, store.ErrApprovalState) {
			s.stateError(w, a)
			return
		}
		s.internal(w, err)
		return
	}
	a, _ = s.Store.Approval(r.Context(), a.ID)
	s.Hub.ToDevice(a.UserID, a.DeviceID, event("approval.responded", map[string]any{"approval": s.approvalView(a, reqDev, reqDev)}))
	s.Hub.ToActive(a.UserID, me.ID, event("approval.closed", map[string]any{"approvalId": a.ID, "state": "claimed"}))
	writeJSON(w, http.StatusOK, s.approvalView(a, me, reqDev))
}

func (s *Server) revealApproval(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Nonce string `json:"nonce"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	n2, ok := decodeField(w, "nonce", req.Nonce, 32, true)
	if !ok {
		return
	}
	a, reqDev, ok := s.loadApproval(w, r)
	if !ok {
		return
	}
	if err := s.Store.RevealApproval(r.Context(), a.ID, n2); err != nil {
		if errors.Is(err, store.ErrApprovalState) {
			s.stateError(w, a)
			return
		}
		s.internal(w, err)
		return
	}
	a, _ = s.Store.Approval(r.Context(), a.ID)
	if a.ResponderDeviceID.Valid {
		responder := &store.Device{ID: a.ResponderDeviceID.String}
		s.Hub.ToDevice(a.UserID, responder.ID, event("approval.revealed", map[string]any{"approval": s.approvalView(a, responder, reqDev)}))
	}
	writeJSON(w, http.StatusOK, s.approvalView(a, device(r), reqDev))
}

func (s *Server) approveApproval(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Box      string `json:"box"`
		BoxNonce string `json:"boxNonce"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	box, ok := decodeField(w, "box", req.Box, 4096, false)
	if !ok {
		return
	}
	boxNonce, ok := decodeField(w, "boxNonce", req.BoxNonce, 24, true)
	if !ok {
		return
	}
	a, reqDev, ok := s.loadApproval(w, r)
	if !ok {
		return
	}
	me := device(r)
	if !a.ResponderDeviceID.Valid || a.ResponderDeviceID.String != me.ID {
		writeError(w, http.StatusForbidden, "forbidden", "only the device that answered the request can approve it")
		return
	}
	if err := s.Store.ApproveApproval(r.Context(), a, box, boxNonce); err != nil {
		if errors.Is(err, store.ErrApprovalState) {
			s.stateError(w, a)
			return
		}
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, http.StatusConflict, "conflict", "the requesting device is no longer waiting")
			return
		}
		s.internal(w, err)
		return
	}
	a, _ = s.Store.Approval(r.Context(), a.ID)
	s.Hub.Activate(a.UserID, a.DeviceID)
	s.Hub.ToDevice(a.UserID, a.DeviceID, event("approval.approved", map[string]any{"approval": s.approvalView(a, reqDev, reqDev)}))
	s.Hub.ToActive(a.UserID, a.DeviceID, event("devices.changed", nil))
	s.Log.Info("device approved", "device", a.DeviceID, "by", me.ID)
	if u, err := s.Store.User(r.Context(), a.UserID); err == nil && reqDev != nil {
		s.sendAsync(mail.NewDeviceMessage(u.Email, r.Header.Get("Accept-Language"), reqDev.Name, reqDev.Platform, "approval"))
	}
	writeJSON(w, http.StatusOK, s.approvalView(a, me, reqDev))
}

func (s *Server) rejectApproval(w http.ResponseWriter, r *http.Request) {
	a, _, ok := s.loadApproval(w, r)
	if !ok {
		return
	}
	me := device(r)
	if a.ResponderDeviceID.Valid && a.ResponderDeviceID.String != me.ID {
		writeError(w, http.StatusForbidden, "forbidden", "another device is handling this request")
		return
	}
	if err := s.Store.CloseApproval(r.Context(), a.ID, store.ApprovalRejected); err != nil {
		if errors.Is(err, store.ErrApprovalState) {
			s.stateError(w, a)
			return
		}
		s.internal(w, err)
		return
	}
	closed := event("approval.closed", map[string]any{"approvalId": a.ID, "state": store.ApprovalRejected})
	s.Hub.ToDevice(a.UserID, a.DeviceID, closed)
	s.Hub.ToActive(a.UserID, me.ID, closed)
	if n, err := s.Store.RejectionsSince(r.Context(), a.UserID, nowMs()-time.Hour.Milliseconds()); err == nil && n >= 3 {
		_ = s.Store.SetApprovalsPausedUntil(r.Context(), a.UserID, nowMs()+time.Hour.Milliseconds())
		s.Log.Warn("approval requests paused after repeated rejections", "user", a.UserID)
	}
	s.Log.Info("approval rejected", "approval", a.ID, "by", me.ID)
	writeJSON(w, http.StatusOK, map[string]any{})
}

// --- recovery ---

func (s *Server) getRecovery(w http.ResponseWriter, r *http.Request) {
	u, err := s.Store.User(r.Context(), device(r).UserID)
	if err != nil {
		s.internal(w, err)
		return
	}
	if !u.VaultInitialized || u.RecoveryWrap == nil {
		writeError(w, http.StatusNotFound, "not_found", "no emergency kit")
		return
	}
	writeJSON(w, http.StatusOK, recoveryJSON{Salt: b64(u.RecoverySalt), OpsLimit: u.RecoveryOps, MemLimit: u.RecoveryMem, Wrap: b64(u.RecoveryWrap)})
}

func (s *Server) activateRecovery(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RecoveryAuth string `json:"recoveryAuth"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	auth, ok := decodeField(w, "recoveryAuth", req.RecoveryAuth, 32, true)
	if !ok {
		return
	}
	me := device(r)
	ctx := r.Context()
	if n, err := s.Store.RecoveryAttemptsSince(ctx, me.UserID, nowMs()-time.Hour.Milliseconds()); err != nil {
		s.internal(w, err)
		return
	} else if n >= 5 {
		tooMany(w, time.Hour)
		return
	}
	u, err := s.Store.User(ctx, me.UserID)
	if err != nil {
		s.internal(w, err)
		return
	}
	h := sha256.Sum256(auth)
	if u.RecoveryAuthHash == nil || subtle.ConstantTimeCompare(h[:], u.RecoveryAuthHash) != 1 {
		_ = s.Store.AddRecoveryAttempt(ctx, me.UserID)
		s.Log.Warn("wrong emergency code", "device", me.ID)
		writeError(w, http.StatusUnprocessableEntity, "recovery_invalid", "wrong emergency code")
		return
	}
	if err := s.Store.ActivateDevice(ctx, me.ID); err != nil {
		s.internal(w, err)
		return
	}
	s.closeApprovalsOf(r, me)
	s.Hub.Activate(me.UserID, me.ID)
	s.Hub.ToActive(me.UserID, me.ID, event("devices.changed", nil))
	s.Log.Info("device activated with emergency code", "device", me.ID)
	s.sendAsync(mail.NewDeviceMessage(u.Email, r.Header.Get("Accept-Language"), me.Name, me.Platform, "recovery"))
	writeJSON(w, http.StatusOK, map[string]any{"status": store.StatusActive})
}

func (s *Server) putRecovery(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Recovery     recoveryJSON `json:"recovery"`
		RecoveryAuth string       `json:"recoveryAuth"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	rec, ok := parseRecovery(w, req.Recovery, req.RecoveryAuth)
	if !ok {
		return
	}
	if err := s.Store.SetRecovery(r.Context(), device(r).UserID, rec); err != nil {
		s.internal(w, err)
		return
	}
	s.Log.Info("emergency kit replaced", "device", device(r).ID)
	writeJSON(w, http.StatusOK, map[string]any{})
}
