package service

import (
	"net/http"
	"strings"
	"testing"

	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
)

// Without a running proxy a measurement needs an account for its pass.
func TestLocationPingNeedsAnAccount(t *testing.T) {
	d := newTestDaemon(t)
	rec := newDashboardClient(t, d).do(http.MethodPost, "/api/locations/ping", map[string]any{})
	if rec.Code != http.StatusConflict || !strings.Contains(rec.Body.String(), "no enabled accounts") {
		t.Fatalf("got %d %s", rec.Code, rec.Body.String())
	}
}

func TestSetLocationEndpoint(t *testing.T) {
	d := newTestDaemon(t)
	client := newDashboardClient(t, d)
	if rec := client.do(http.MethodPost, "/api/location", map[string]string{"country": "fastest"}); rec.Code != http.StatusOK {
		t.Fatalf("got %d %s", rec.Code, rec.Body.String())
	}
	if got := d.config().Proxy.Country; got != proxy.FastestCountry {
		t.Fatalf("country = %q", got)
	}
}
