package netcheck

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
)

// An address of Fastly's network, by number or name, is a VPN's exit; an
// ordinary provider is not, nor is an answer that cannot be read.
func TestInsideVPN(t *testing.T) {
	old := detailsURL
	t.Cleanup(func() { detailsURL = old })
	for body, want := range map[string]bool{
		`{"ip":"151.101.1.1","asn":54113,"isp":"Fastly","organization":"Fastly","asn_organization":"FASTLY"}`: true,
		`{"ip":"151.101.1.1","isp":"Fastly, Inc."}`:                                                           true,
		`{"ip":"5.200.200.200","asn":58224,"isp":"Iran Telecommunication Company PJS"}`:                       false,
		`not json`: false,
	} {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			_, _ = io.WriteString(w, body)
		}))
		detailsURL = srv.URL
		if got := InsideVPN(context.Background()); got != want {
			t.Errorf("%s: got %v, want %v", body, got, want)
		}
		srv.Close()
	}
}
