package service

import (
	"net/http"
	"strings"
	"testing"
)

func TestSignInAgainUsesStoredPassword(t *testing.T) {
	d := newTestDaemon(t)
	id := addTestAccount(t, d, "user")
	client := newDashboardClient(t, d)
	if rec := client.do(http.MethodPost, "/api/signin", map[string]string{"account_id": id}); rec.Code != http.StatusConflict {
		t.Fatalf("without a stored password: got %d", rec.Code)
	}
	if err := d.store.SetPassword(id, "secret"); err != nil {
		t.Fatal(err)
	}
	rec := client.do(http.MethodGet, "/api/accounts", nil)
	if !strings.Contains(rec.Body.String(), `"has_password":true`) || strings.Contains(rec.Body.String(), "secret") {
		t.Fatalf("accounts view: %s", rec.Body.String())
	}
}
