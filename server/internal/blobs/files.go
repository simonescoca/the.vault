// Package blobs stores encrypted attachment files on disk.
//
// Layout (inside the data directory):
//
//	blobs/<userID>/<blobID>          complete blobs (immutable)
//	uploads/<userID>/<blobID>.part   uploads in progress, written part by part
package blobs

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
)

var idRe = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

// ValidID reports whether s is a lowercase UUID (safe to use as a file name).
func ValidID(s string) bool { return idRe.MatchString(s) }

type Files struct{ Dir string }

func (f *Files) BlobPath(userID, blobID string) string {
	return filepath.Join(f.Dir, "blobs", userID, blobID)
}

func (f *Files) UploadPath(userID, blobID string) string {
	return filepath.Join(f.Dir, "uploads", userID, blobID+".part")
}

// WritePart writes exactly n bytes from r at offset into the upload file.
func (f *Files) WritePart(userID, blobID string, offset, n int64, r io.Reader) error {
	if !ValidID(userID) || !ValidID(blobID) {
		return errors.New("invalid id")
	}
	p := f.UploadPath(userID, blobID)
	if err := os.MkdirAll(filepath.Dir(p), 0o700); err != nil {
		return err
	}
	fh, err := os.OpenFile(p, os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer fh.Close()
	w := io.NewOffsetWriter(fh, offset)
	written, err := io.Copy(w, io.LimitReader(r, n+1))
	if err != nil {
		return err
	}
	if written != n {
		return fmt.Errorf("part size mismatch: got %d, want %d", written, n)
	}
	return fh.Sync()
}

// Finalize checks the upload size, computes its SHA-256 and moves it into place.
func (f *Files) Finalize(userID, blobID string, size int64) (string, error) {
	p := f.UploadPath(userID, blobID)
	fh, err := os.Open(p)
	if err != nil {
		return "", err
	}
	st, err := fh.Stat()
	if err != nil {
		fh.Close()
		return "", err
	}
	if st.Size() != size {
		fh.Close()
		return "", fmt.Errorf("size mismatch: got %d, want %d", st.Size(), size)
	}
	h := sha256.New()
	if _, err := io.Copy(h, fh); err != nil {
		fh.Close()
		return "", err
	}
	fh.Close()
	dst := f.BlobPath(userID, blobID)
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return "", err
	}
	if err := os.Rename(p, dst); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

// Delete removes a blob and any upload in progress.
func (f *Files) Delete(userID, blobID string) error {
	err1 := os.Remove(f.BlobPath(userID, blobID))
	err2 := os.Remove(f.UploadPath(userID, blobID))
	if err1 != nil && !errors.Is(err1, os.ErrNotExist) {
		return err1
	}
	if err2 != nil && !errors.Is(err2, os.ErrNotExist) {
		return err2
	}
	return nil
}
