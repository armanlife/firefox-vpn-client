// Package securefile writes files that hold secrets or personal data.
package securefile

import (
	"errors"
	"os"
	"path/filepath"
)

// WritePrivate replaces path with data through a temporary file in the same
// directory, readable and writable only by the owner (0600 on POSIX; Windows
// keeps the default ACL of the user's profile directory). If the rename
// fails because the target is locked, the old file is removed and the rename
// retried, so that fallback is not atomic.
func WritePrivate(path string, data []byte) error {
	dir := filepath.Dir(path)
	tmp, err := os.CreateTemp(dir, filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)

	if err := tmp.Chmod(0600); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}

	if err := os.Rename(tmpPath, path); err != nil {
		if removeErr := os.Remove(path); removeErr != nil && !errors.Is(removeErr, os.ErrNotExist) {
			return err
		}
		if retryErr := os.Rename(tmpPath, path); retryErr != nil {
			return retryErr
		}
	}
	return os.Chmod(path, 0600)
}

// EnsurePrivateDir creates dir and its parents with owner-only permissions.
func EnsurePrivateDir(dir string) error {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	return os.Chmod(dir, 0o700)
}
