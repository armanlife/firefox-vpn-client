package service

import (
	"archive/zip"
	"bytes"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/fxa"
)

// All credentials in this file are local fixtures.

func zipNames(t *testing.T, data []byte) []string {
	t.Helper()
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, f := range zr.File {
		names = append(names, f.Name)
	}
	sort.Strings(names)
	return names
}

func writeBackupTestFile(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o600); err != nil {
		t.Fatal(err)
	}
}

// A backup is the data folder's layout without the logs, the routing
// lists, downloaded updates, and this run's own files.
func TestBackupLeavesOutLargeAndRunFiles(t *testing.T) {
	d := newTestDaemon(t)
	id := addTestAccount(t, d, "one")
	if err := d.store.SetPassword(id, "password-fixture"); err != nil {
		t.Fatal(err)
	}
	dir := d.paths.Dir
	writeBackupTestFile(t, filepath.Join(dir, "config.json"), "{}")
	writeBackupTestFile(t, filepath.Join(dir, "app-settings.json"), "{}")
	writeBackupTestFile(t, filepath.Join(dir, "logs", "arman-vpn-2026-11-06.log"), "log")
	writeBackupTestFile(t, filepath.Join(dir, "routing", "geosite.dat"), "lists")
	writeBackupTestFile(t, filepath.Join(dir, "update", "Arman-VPN.zip"), "update")
	writeBackupTestFile(t, filepath.Join(dir, localTokenName), "token")
	writeBackupTestFile(t, filepath.Join(dir, statusFileName), "{}")

	var buf bytes.Buffer
	if err := d.writeBackup(&buf); err != nil {
		t.Fatal(err)
	}
	names := zipNames(t, buf.Bytes())
	joined := strings.Join(names, " ")
	for _, want := range []string{backupInfoName, "config.json", "app-settings.json", "accounts/secret.key", "accounts/" + id + "/account.json", "accounts/" + id + "/credentials.json"} {
		if !strings.Contains(" "+joined+" ", " "+want+" ") {
			t.Errorf("backup lacks %s: %v", want, names)
		}
	}
	for _, name := range names {
		if strings.HasPrefix(name, "logs/") || strings.HasPrefix(name, "routing/") || strings.HasPrefix(name, "update/") || name == localTokenName || name == statusFileName {
			t.Errorf("backup holds %s", name)
		}
	}
}

// Taking a backup in adds its new accounts and gives one this device has
// already the backup's sign-in, with the passwords and device records.
func TestBackupImportAddsAndUpdates(t *testing.T) {
	from := newTestDaemon(t)
	oneID := addTestAccount(t, from, "one")
	twoID := addTestAccount(t, from, "two")
	if err := from.store.SetPassword(oneID, "password-one"); err != nil {
		t.Fatal(err)
	}
	if err := from.store.SaveDevice(twoID, "device-two", "fingerprint-two"); err != nil {
		t.Fatal(err)
	}
	var buf bytes.Buffer
	if err := from.writeBackup(&buf); err != nil {
		t.Fatal(err)
	}

	to := newTestDaemon(t)
	// The same account, signed in earlier with another token.
	if _, _, err := to.store.Add("two@example.com", &fxa.SavedTokens{RefreshToken: "old-refresh", ObtainedAt: time.Now()}, time.Now()); err != nil {
		t.Fatal(err)
	}

	contents, err := to.inspectBackup(buf.Bytes())
	if err != nil {
		t.Fatal(err)
	}
	if contents.Info == nil || contents.Info.Accounts != 2 || len(contents.Accounts) != 2 {
		t.Fatalf("inspect = %+v", contents)
	}
	for _, a := range contents.Accounts {
		switch a.Email {
		case "one@example.com":
			if !a.HasPassword || a.Exists {
				t.Errorf("one: %+v", a)
			}
		case "two@example.com":
			if a.HasPassword || !a.Exists {
				t.Errorf("two: %+v", a)
			}
		default:
			t.Errorf("unexpected account %+v", a)
		}
	}

	added, updated, err := to.importBackup(buf.Bytes())
	if err != nil || added != 1 || updated != 1 {
		t.Fatalf("import = %d added, %d updated, %v", added, updated, err)
	}
	list, err := to.store.List()
	if err != nil || len(list) != 2 {
		t.Fatalf("accounts after import: %v %v", list, err)
	}
	for _, acc := range list {
		creds, err := to.store.Credentials(acc.ID)
		if err != nil {
			t.Fatal(err)
		}
		switch acc.Email {
		case "one@example.com":
			if creds.RefreshToken != "refresh-one" {
				t.Errorf("one's token = %q", creds.RefreshToken)
			}
			if password, err := to.store.Password(acc.ID); err != nil || password != "password-one" {
				t.Errorf("one's password = %q, %v", password, err)
			}
		case "two@example.com":
			if creds.RefreshToken != "refresh-two" {
				t.Errorf("two kept its old token %q", creds.RefreshToken)
			}
			if acc.DeviceID != "device-two" || acc.DeviceToken != "fingerprint-two" {
				t.Errorf("two's device = %q %q", acc.DeviceID, acc.DeviceToken)
			}
		}
	}
	if to.mgr.Len() != 2 {
		t.Fatalf("the rotation has %d accounts, want 2", to.mgr.Len())
	}
	// The temporary store lived in the data folder (Android's system
	// temporary folder is not the app's), and is gone.
	entries, err := os.ReadDir(to.paths.Dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if strings.HasPrefix(e.Name(), ".backup-import-") {
			t.Fatalf("left behind %s", e.Name())
		}
	}
}

// A data folder zipped by hand (under its own folder, without backup.json)
// is taken in too; anything else is refused.
func TestBackupImportZippedByHandAndRefusals(t *testing.T) {
	from := newTestDaemon(t)
	addTestAccount(t, from, "one")
	var buf bytes.Buffer
	if err := from.writeBackup(&buf); err != nil {
		t.Fatal(err)
	}
	zr, err := zip.NewReader(bytes.NewReader(buf.Bytes()), int64(buf.Len()))
	if err != nil {
		t.Fatal(err)
	}
	var byHand bytes.Buffer
	zw := zip.NewWriter(&byHand)
	for _, f := range zr.File {
		if f.Name == backupInfoName {
			continue
		}
		r, _ := f.Open()
		if err := writeZipEntry(zw, "user-data/"+f.Name, time.Now(), r); err != nil {
			t.Fatal(err)
		}
		r.Close()
	}
	zw.Close()

	to := newTestDaemon(t)
	contents, err := to.inspectBackup(byHand.Bytes())
	if err != nil || contents.Info != nil || len(contents.Accounts) != 1 {
		t.Fatalf("inspect = %+v, %v", contents, err)
	}
	if added, _, err := to.importBackup(byHand.Bytes()); err != nil || added != 1 {
		t.Fatalf("import = %d, %v", added, err)
	}

	var empty bytes.Buffer
	zw = zip.NewWriter(&empty)
	writeZipEntry(zw, "config.json", time.Now(), strings.NewReader("{}"))
	writeZipEntry(zw, "accounts/../../evil/account.json", time.Now(), strings.NewReader("{}"))
	zw.Close()
	for name, data := range map[string][]byte{"not a zip": []byte("hello"), "no accounts": empty.Bytes()} {
		if _, err := to.inspectBackup(data); err == nil {
			t.Errorf("%s: inspect accepted it", name)
		}
		if _, _, err := to.importBackup(data); err == nil {
			t.Errorf("%s: import accepted it", name)
		}
	}
}

func TestBackupAPI(t *testing.T) {
	from := newTestDaemon(t)
	addTestAccount(t, from, "one")
	c := newDashboardClient(t, from)
	rec := c.do(http.MethodGet, "/api/backup", nil)
	if rec.Code != http.StatusOK || rec.Header().Get("Content-Type") != "application/zip" ||
		!strings.Contains(rec.Header().Get("Content-Disposition"), "Arman-VPN-backup-") {
		t.Fatalf("export: %d %v", rec.Code, rec.Header())
	}
	data := rec.Body.Bytes()

	to := newTestDaemon(t)
	c = newDashboardClient(t, to)
	rec = c.do(http.MethodPost, "/api/backup/inspect", map[string][]byte{"data": data})
	if rec.Code != http.StatusOK {
		t.Fatalf("inspect: %d %s", rec.Code, rec.Body)
	}
	rec = c.do(http.MethodPost, "/api/backup/import", map[string][]byte{"data": data})
	if rec.Code != http.StatusOK {
		t.Fatalf("import: %d %s", rec.Code, rec.Body)
	}
	var result map[string]int
	if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil || result["added"] != 1 {
		t.Fatalf("import answered %s", rec.Body)
	}
	if rec := c.do(http.MethodPost, "/api/backup/import", map[string][]byte{"data": []byte("nope")}); rec.Code != http.StatusBadRequest {
		t.Fatalf("a bad file: %d %s", rec.Code, rec.Body)
	}

}
