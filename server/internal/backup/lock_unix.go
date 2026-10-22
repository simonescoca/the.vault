//go:build unix

package backup

import (
	"os"
	"path/filepath"
	"syscall"
)

// lockDir waits until no other process is backing up into root, and returns the function that lets it go.
func lockDir(root string) (func(), error) {
	f, err := os.OpenFile(filepath.Join(root, ".lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		f.Close()
		return nil, err
	}
	return func() { f.Close() }, nil
}
