package service

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/accounts"
	"github.com/armanlife/arman-vpn-client/core/internal/logx"
	"github.com/armanlife/arman-vpn-client/core/internal/version"
)

// A backup is the data folder as a zip file, in the same layout, so that it
// can also be unzipped into another device's data folder by hand (with the
// program stopped there). The logs, the routing lists, and downloaded
// updates are left out: they are large and come back by themselves. So is
// what only this run uses (the local token, the status file). backup.json at
// its root says what made it. The accounts' passwords travel too, with the
// key that decrypts them (accounts/secret.key).

const (
	backupInfoName = "backup.json"
	backupFormat   = 1
	// maxBackupSize bounds a backup taken in: accounts and settings are a
	// few kilobytes.
	maxBackupSize = 16 << 20
	// maxBackupFile bounds one account file read from a backup.
	maxBackupFile = 1 << 20
)

// backupSkipped names the data folder's entries a backup leaves out.
var backupSkipped = map[string]bool{
	"logs":         true,
	"routing":      true,
	"update":       true,
	statusFileName: true,
	localTokenName: true,
}

// backupAccountFile matches an account file in a backup, at its root or
// under one folder (a data folder zipped by hand), and captures its path
// below accounts/.
var backupAccountFile = regexp.MustCompile(`(?:^|/)accounts/(secret\.key|[A-Za-z0-9_-]{1,64}/(?:account|credentials)\.json)$`)

// backupInfo is backup.json.
type backupInfo struct {
	App      string    `json:"app"`
	Format   int       `json:"format"`
	Version  string    `json:"version"`
	Created  time.Time `json:"created"`
	System   string    `json:"system"`
	Accounts int       `json:"accounts"`
}

// backupAccount is an account found in a backup.
type backupAccount struct {
	Email       string `json:"email"`
	HasPassword bool   `json:"has_password"`
	// Exists says this device has the account already: taking the backup
	// in gives it the backup's sign-in.
	Exists bool `json:"exists"`
}

// backupContents is what a backup holds, for the app to show before it is
// taken in.
type backupContents struct {
	Info     *backupInfo     `json:"info,omitempty"`
	Accounts []backupAccount `json:"accounts"`
}

// backupFileName is the name a backup is saved under.
func backupFileName(now time.Time) string {
	return "Arman-VPN-backup-" + now.Format("2006-01-02") + ".zip"
}

// writeBackup writes the data folder to w as a zip file.
func (d *Daemon) writeBackup(w io.Writer) error {
	list, err := d.store.List()
	if err != nil {
		return err
	}
	zw := zip.NewWriter(w)
	info, _ := json.MarshalIndent(backupInfo{
		App:      "Arman VPN",
		Format:   backupFormat,
		Version:  version.Current,
		Created:  time.Now().UTC().Truncate(time.Second),
		System:   runtime.GOOS,
		Accounts: len(list),
	}, "", "  ")
	if err := writeZipEntry(zw, backupInfoName, time.Now(), bytes.NewReader(info)); err != nil {
		return err
	}
	root := d.paths.Dir
	err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			// A file that went away while the folder was read.
			if errors.Is(err, fs.ErrNotExist) {
				return nil
			}
			return err
		}
		if path == root {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		rel = filepath.ToSlash(rel)
		name := entry.Name()
		if (!strings.Contains(rel, "/") && backupSkipped[rel]) || strings.HasPrefix(name, ".") || strings.HasSuffix(name, ".tmp") {
			if entry.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if entry.IsDir() || !entry.Type().IsRegular() || rel == backupInfoName {
			return nil
		}
		stat, err := entry.Info()
		if err != nil {
			return nil
		}
		f, err := os.Open(path)
		if err != nil {
			if errors.Is(err, fs.ErrNotExist) {
				return nil
			}
			return err
		}
		defer f.Close()
		return writeZipEntry(zw, rel, stat.ModTime(), f)
	})
	if err != nil {
		zw.Close()
		return err
	}
	return zw.Close()
}

func writeZipEntry(zw *zip.Writer, name string, modified time.Time, r io.Reader) error {
	w, err := zw.CreateHeader(&zip.FileHeader{Name: name, Method: zip.Deflate, Modified: modified})
	if err != nil {
		return err
	}
	_, err = io.Copy(w, r)
	return err
}

// openBackup reads a backup's accounts into a temporary account store (with
// the key that decrypts their passwords) and its backup.json, if it has
// one. close removes the temporary store. The store goes in a hidden folder
// of dataDir, which a backup leaves out: on Android the system's temporary
// folder is not the app's to write.
func openBackup(dataDir string, data []byte) (store *accounts.Store, info *backupInfo, close func(), err error) {
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, nil, nil, errors.New("this is not a backup file (not a zip file)")
	}
	dir, err := os.MkdirTemp(dataDir, ".backup-import-")
	if err != nil {
		return nil, nil, nil, err
	}
	close = func() { os.RemoveAll(dir) }
	found := false
	for _, f := range zr.File {
		name := strings.TrimPrefix(f.Name, "./")
		if name == backupInfoName {
			var parsed backupInfo
			if err := readZipJSON(f, &parsed); err == nil {
				info = &parsed
			}
			continue
		}
		m := backupAccountFile.FindStringSubmatch(name)
		if m == nil || f.FileInfo().IsDir() {
			continue
		}
		if f.UncompressedSize64 > maxBackupFile {
			continue
		}
		target := filepath.Join(dir, "accounts", filepath.FromSlash(m[1]))
		if err := extractZipFile(f, target); err != nil {
			close()
			return nil, nil, nil, err
		}
		found = true
	}
	if !found {
		close()
		return nil, nil, nil, errors.New("there are no accounts in this file")
	}
	store, err = accounts.OpenStore(dir)
	if err != nil {
		close()
		return nil, nil, nil, err
	}
	return store, info, close, nil
}

func readZipJSON(f *zip.File, v any) error {
	r, err := f.Open()
	if err != nil {
		return err
	}
	defer r.Close()
	return json.NewDecoder(io.LimitReader(r, maxBackupFile)).Decode(v)
}

func extractZipFile(f *zip.File, target string) error {
	if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
		return err
	}
	r, err := f.Open()
	if err != nil {
		return fmt.Errorf("reading %s: %w", f.Name, err)
	}
	defer r.Close()
	out, err := os.OpenFile(target, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, io.LimitReader(r, maxBackupFile)); err != nil {
		out.Close()
		return fmt.Errorf("reading %s: %w", f.Name, err)
	}
	return out.Close()
}

// inspectBackup says which accounts a backup holds.
func (d *Daemon) inspectBackup(data []byte) (backupContents, error) {
	src, info, close, err := openBackup(d.paths.Dir, data)
	if err != nil {
		return backupContents{}, err
	}
	defer close()
	list, err := src.List()
	if err != nil {
		return backupContents{}, err
	}
	have, err := d.store.List()
	if err != nil {
		return backupContents{}, err
	}
	out := backupContents{Info: info, Accounts: []backupAccount{}}
	for _, acc := range list {
		if creds, err := src.Credentials(acc.ID); err != nil || creds.RefreshToken == "" {
			continue
		}
		exists := false
		for _, h := range have {
			exists = exists || (acc.Email != "" && strings.EqualFold(h.Email, acc.Email))
		}
		out.Accounts = append(out.Accounts, backupAccount{Email: acc.Email, HasPassword: src.HasPassword(acc.ID), Exists: exists})
	}
	if len(out.Accounts) == 0 {
		return backupContents{}, errors.New("there are no accounts in this file")
	}
	return out, nil
}

// importBackup adds a backup's accounts: new ones join the rotation at
// the end, and one this device has already (the same email) takes the
// backup's sign-in. Each keeps its password and its device record, so it
// shows once in the account's connected services. The settings in the
// backup are left as they are here.
func (d *Daemon) importBackup(data []byte) (added, updated int, err error) {
	src, _, close, err := openBackup(d.paths.Dir, data)
	if err != nil {
		return 0, 0, err
	}
	defer close()
	list, err := src.List()
	if err != nil {
		return 0, 0, err
	}
	now := time.Now()
	for _, from := range list {
		creds, err := src.Credentials(from.ID)
		if err != nil || creds.RefreshToken == "" {
			continue
		}
		acc, created, err := d.store.Add(from.Email, creds, now)
		if err != nil {
			return added, updated, err
		}
		d.pool.Forget(acc.ID)
		if password, err := src.Password(from.ID); err == nil {
			if err := d.store.SetPassword(acc.ID, password); err != nil {
				logx.Warn("saving the account password failed account=%s err=%s", logx.Email(acc.Name()), logx.Err(err))
			}
		}
		if from.DeviceID != "" {
			if err := d.store.SaveDevice(acc.ID, from.DeviceID, from.DeviceToken); err != nil {
				logx.Warn("saving the account's device failed account=%s err=%s", logx.Email(acc.Name()), logx.Err(err))
			}
		}
		if created {
			added++
			logx.Info("account added from a backup account=%s id=%s", logx.Email(acc.Name()), acc.ID)
		} else {
			updated++
			logx.Info("account signed in again from a backup account=%s id=%s", logx.Email(acc.Name()), acc.ID)
		}
	}
	if added+updated == 0 {
		return 0, 0, errors.New("there are no accounts in this file")
	}
	return added, updated, d.accountsChanged()
}

// handleBackupExport sends the data folder as a zip file (writeBackup).
func (s *dashboardServer) handleBackupExport(w http.ResponseWriter, r *http.Request) {
	var buf bytes.Buffer
	if err := s.d.writeBackup(&buf); err != nil {
		writeError(w, http.StatusInternalServerError, "making the backup: "+err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/zip")
	w.Header().Set("Content-Disposition", `attachment; filename="`+backupFileName(time.Now())+`"`)
	w.Header().Set("Cache-Control", "no-store")
	w.Write(buf.Bytes())
}

// readBackupRequest reads {"data": base64 of a backup's zip file}.
func readBackupRequest(w http.ResponseWriter, r *http.Request) ([]byte, bool) {
	r.Body = http.MaxBytesReader(w, r.Body, maxBackupSize/3*4+4096)
	var in struct {
		Data []byte `json:"data"`
	}
	if !readJSON(w, r, &in) {
		return nil, false
	}
	if len(in.Data) == 0 {
		writeError(w, http.StatusBadRequest, "no backup file was sent")
		return nil, false
	}
	return in.Data, true
}

// handleBackupInspect says which accounts a backup holds.
func (s *dashboardServer) handleBackupInspect(w http.ResponseWriter, r *http.Request) {
	data, ok := readBackupRequest(w, r)
	if !ok {
		return
	}
	contents, err := s.d.inspectBackup(data)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, contents)
}

// handleBackupImport adds a backup's accounts (importBackup).
func (s *dashboardServer) handleBackupImport(w http.ResponseWriter, r *http.Request) {
	data, ok := readBackupRequest(w, r)
	if !ok {
		return
	}
	added, updated, err := s.d.importBackup(data)
	if err != nil && added+updated == 0 {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"added": added, "updated": updated})
}
