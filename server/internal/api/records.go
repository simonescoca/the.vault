package api

import (
	"errors"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/simonescoca/the.vault/server/internal/blobs"
	"github.com/simonescoca/the.vault/server/internal/store"
)

func recordJSON(r *store.Record) map[string]any {
	blobsOut := r.Blobs
	if blobsOut == nil {
		blobsOut = []string{}
	}
	return map[string]any{"id": r.ID, "rev": r.Rev, "data": b64OrNil(r.Data), "blobs": blobsOut, "deleted": r.Deleted,
		"updatedAt": r.UpdatedAt, "updatedBy": r.UpdatedBy}
}

func (s *Server) listRecords(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	since, err := strconv.ParseInt(q.Get("since"), 10, 64)
	if q.Get("since") == "" {
		since, err = 0, nil
	}
	if err != nil || since < 0 {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid since")
		return
	}
	limit := 500
	if l := q.Get("limit"); l != "" {
		limit, err = strconv.Atoi(l)
		if err != nil || limit < 1 {
			writeError(w, http.StatusBadRequest, "bad_request", "invalid limit")
			return
		}
		if limit > 1000 {
			limit = 1000
		}
	}
	recs, more, latest, err := s.Store.RecordsSince(r.Context(), device(r).UserID, since, limit)
	if err != nil {
		s.internal(w, err)
		return
	}
	out := make([]map[string]any, 0, len(recs))
	for _, rec := range recs {
		out = append(out, recordJSON(rec))
	}
	writeJSON(w, http.StatusOK, map[string]any{"records": out, "latest": latest, "more": more})
}

func (s *Server) putRecord(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !blobs.ValidID(id) {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid record id")
		return
	}
	var req struct {
		BaseRev *int64   `json:"baseRev"`
		Data    string   `json:"data"`
		Blobs   []string `json:"blobs"`
	}
	if !decodeJSON(w, r, maxRecordBody, &req) {
		return
	}
	if req.BaseRev == nil || *req.BaseRev < 0 {
		writeError(w, http.StatusBadRequest, "invalid_field", "missing baseRev")
		return
	}
	data, ok := decodeField(w, "data", req.Data, maxRecordData, false)
	if !ok {
		return
	}
	seen := map[string]bool{}
	var refs []string
	for _, b := range req.Blobs {
		if !blobs.ValidID(b) {
			writeError(w, http.StatusBadRequest, "invalid_field", "invalid blob id")
			return
		}
		if !seen[b] {
			seen[b] = true
			refs = append(refs, b)
		}
	}
	if len(refs) > 1000 {
		writeError(w, http.StatusBadRequest, "invalid_field", "too many blobs")
		return
	}
	me := device(r)
	rev, at, err := s.Store.PutRecord(r.Context(), me.UserID, me.ID, id, *req.BaseRev, data, refs)
	if s.recordWriteError(w, err) {
		return
	}
	s.Hub.ToActive(me.UserID, me.ID, event("records.changed", map[string]any{"latest": rev, "by": me.ID}))
	writeJSON(w, http.StatusOK, map[string]any{"rev": rev, "updatedAt": at})
}

func (s *Server) deleteRecord(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !blobs.ValidID(id) {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid record id")
		return
	}
	baseRev, err := strconv.ParseInt(r.URL.Query().Get("baseRev"), 10, 64)
	if err != nil || baseRev < 1 {
		writeError(w, http.StatusBadRequest, "invalid_field", "missing baseRev")
		return
	}
	me := device(r)
	rev, at, err := s.Store.DeleteRecord(r.Context(), me.UserID, me.ID, id, baseRev)
	if s.recordWriteError(w, err) {
		return
	}
	s.Hub.ToActive(me.UserID, me.ID, event("records.changed", map[string]any{"latest": rev, "by": me.ID}))
	writeJSON(w, http.StatusOK, map[string]any{"rev": rev, "updatedAt": at})
}

func (s *Server) recordWriteError(w http.ResponseWriter, err error) bool {
	if err == nil {
		return false
	}
	var ce *store.ConflictError
	var mb *store.MissingBlobError
	switch {
	case errors.As(err, &ce):
		writeError(w, http.StatusConflict, "conflict", "the record changed in the meantime",
			map[string]any{"current": recordJSON(ce.Current)})
	case errors.As(err, &mb):
		writeError(w, http.StatusUnprocessableEntity, "missing_blob", "some attachments are not uploaded yet",
			map[string]any{"blobs": mb.IDs})
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found", "no such record")
	default:
		s.internal(w, err)
	}
	return true
}

// --- blobs ---

func partsCount(size, partSize int64) int { return int((size + partSize - 1) / partSize) }

func (s *Server) startBlob(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !blobs.ValidID(id) {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid blob id")
		return
	}
	var req struct {
		Size int64 `json:"size"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	if req.Size < 1 {
		writeError(w, http.StatusBadRequest, "invalid_field", "invalid size")
		return
	}
	if req.Size > s.Cfg.MaxBlobBytes {
		writeError(w, http.StatusRequestEntityTooLarge, "too_large", "attachment too large")
		return
	}
	me := device(r)
	b, err := s.Store.Blob(r.Context(), me.UserID, id)
	if err == nil {
		if b.Size != req.Size {
			writeError(w, http.StatusConflict, "conflict", "a different upload exists with this id")
			return
		}
		if b.State == store.BlobComplete {
			writeJSON(w, http.StatusOK, map[string]any{"partSize": b.PartSize, "complete": true, "receivedParts": []int{}})
			return
		}
		parts, err := s.Store.BlobParts(r.Context(), me.UserID, id)
		if err != nil {
			s.internal(w, err)
			return
		}
		got := []int{}
		for n := range parts {
			got = append(got, n)
		}
		writeJSON(w, http.StatusOK, map[string]any{"partSize": b.PartSize, "complete": false, "receivedParts": got})
		return
	}
	if !errors.Is(err, store.ErrNotFound) {
		s.internal(w, err)
		return
	}
	if err := s.Store.CreateBlob(r.Context(), &store.Blob{UserID: me.UserID, ID: id, Size: req.Size, PartSize: s.PartSize}); err != nil {
		s.internal(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"partSize": s.PartSize, "complete": false, "receivedParts": []int{}})
}

func (s *Server) uploadingBlob(w http.ResponseWriter, r *http.Request) (*store.Blob, bool) {
	id := r.PathValue("id")
	if !blobs.ValidID(id) {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid blob id")
		return nil, false
	}
	b, err := s.Store.Blob(r.Context(), device(r).UserID, id)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "not_found", "no such upload")
		return nil, false
	}
	if err != nil {
		s.internal(w, err)
		return nil, false
	}
	if b.State != store.BlobUploading {
		writeError(w, http.StatusConflict, "conflict", "upload already completed")
		return nil, false
	}
	return b, true
}

func (s *Server) putBlobPart(w http.ResponseWriter, r *http.Request) {
	b, ok := s.uploadingBlob(w, r)
	if !ok {
		return
	}
	n, err := strconv.Atoi(r.PathValue("n"))
	total := partsCount(b.Size, b.PartSize)
	if err != nil || n < 0 || n >= total {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid part number")
		return
	}
	want := b.PartSize
	if n == total-1 {
		want = b.Size - int64(n)*b.PartSize
	}
	if r.ContentLength >= 0 && r.ContentLength != want {
		writeError(w, http.StatusBadRequest, "bad_request", "wrong part length")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, want+1)
	if err := s.Files.WritePart(b.UserID, b.ID, int64(n)*b.PartSize, want, r.Body); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "could not store the part: "+err.Error())
		return
	}
	if err := s.Store.PutBlobPart(r.Context(), b.UserID, b.ID, n, want); err != nil {
		s.internal(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) completeBlob(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Parts  int    `json:"parts"`
		SHA256 string `json:"sha256"`
	}
	if !decodeJSON(w, r, maxJSONBody, &req) {
		return
	}
	b, ok := s.uploadingBlob(w, r)
	if !ok {
		return
	}
	parts, err := s.Store.BlobParts(r.Context(), b.UserID, b.ID)
	if err != nil {
		s.internal(w, err)
		return
	}
	total := partsCount(b.Size, b.PartSize)
	if req.Parts != total || len(parts) != total {
		writeError(w, http.StatusUnprocessableEntity, "incomplete", "some parts are missing",
			map[string]any{"expected": total, "received": len(parts)})
		return
	}
	sum, err := s.Files.Finalize(b.UserID, b.ID, b.Size)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "incomplete", "upload is not complete: "+err.Error())
		return
	}
	if req.SHA256 != "" && req.SHA256 != sum {
		_ = s.Files.Delete(b.UserID, b.ID)
		_ = s.Store.DeleteBlob(r.Context(), b.UserID, b.ID)
		writeError(w, http.StatusUnprocessableEntity, "checksum_mismatch", "the uploaded data is corrupted, upload again")
		return
	}
	if err := s.Store.CompleteBlob(r.Context(), b.UserID, b.ID, sum); err != nil {
		s.internal(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"sha256": sum})
}

func (s *Server) getBlob(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !blobs.ValidID(id) {
		writeError(w, http.StatusBadRequest, "bad_request", "invalid blob id")
		return
	}
	me := device(r)
	b, err := s.Store.Blob(r.Context(), me.UserID, id)
	if errors.Is(err, store.ErrNotFound) || (err == nil && b.State != store.BlobComplete) {
		writeError(w, http.StatusNotFound, "not_found", "no such blob")
		return
	}
	if err != nil {
		s.internal(w, err)
		return
	}
	f, err := os.Open(s.Files.BlobPath(me.UserID, id))
	if err != nil {
		s.internal(w, err)
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", "application/octet-stream")
	if b.SHA256.Valid {
		w.Header().Set("ETag", `"`+b.SHA256.String+`"`)
	}
	http.ServeContent(w, r, "", time.UnixMilli(b.CreatedAt), f)
}
