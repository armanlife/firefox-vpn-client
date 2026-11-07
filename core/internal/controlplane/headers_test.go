package controlplane

import (
	"net/http"
	"strings"
	"testing"
)

func TestFirefoxPlatform(t *testing.T) {
	for _, tc := range []struct{ goos, goarch, want string }{
		{"windows", "amd64", "Windows NT 10.0; Win64; x64"},
		{"darwin", "arm64", "Macintosh; Intel Mac OS X 10.15"},
		{"linux", "amd64", "X11; Linux x86_64"},
		{"linux", "arm64", "X11; Linux aarch64"},
		{"android", "arm64", "Windows NT 10.0; Win64; x64"},
	} {
		if got := firefoxPlatform(tc.goos, tc.goarch); got != tc.want {
			t.Errorf("%s/%s: got %q, want %q", tc.goos, tc.goarch, got, tc.want)
		}
	}
}

// The User-Agent names the Firefox release product details gave, and keeps
// the last good one when an answer is not a version.
func TestFirefoxUserAgentFollowsTheRelease(t *testing.T) {
	t.Cleanup(func() { firefoxMajor.Store(defaultFirefoxMajor) })
	SetFirefoxVersion("163.0.2")
	ua := FirefoxUserAgent()
	if !strings.HasPrefix(ua, "Mozilla/5.0 (") || !strings.HasSuffix(ua, "; rv:163.0) Gecko/20100101 Firefox/163.0") {
		t.Fatalf("user agent %q", ua)
	}
	SetFirefoxVersion("")
	SetFirefoxVersion("nightly")
	if !strings.HasSuffix(FirefoxUserAgent(), "Firefox/163.0") {
		t.Fatalf("a bad version replaced the release: %q", FirefoxUserAgent())
	}

	req, _ := http.NewRequest(http.MethodGet, "https://vpn.mozilla.org/api/v1/fpn/token", nil)
	ApplyFirefoxHeaders(req)
	if req.Header.Get("User-Agent") != ua || req.Header.Get("Accept") != "*/*" {
		t.Fatalf("headers %v", req.Header)
	}
	if got := req.Header.Get("Accept-Encoding"); got != "identity" {
		t.Fatalf("Accept-Encoding = %q, want identity", got)
	}
}

func TestFirefoxHeadersIncludeFetchMetadata(t *testing.T) {
	req, _ := http.NewRequest(http.MethodPost, "https://api.accounts.firefox.com/v1/oauth/token", nil)
	ApplyFirefoxHeaders(req)

	if got := req.Header.Get("Sec-Fetch-Dest"); got != "empty" {
		t.Errorf("Sec-Fetch-Dest = %q, want empty", got)
	}
	if got := req.Header.Get("Sec-Fetch-Mode"); got != "cors" {
		t.Errorf("Sec-Fetch-Mode = %q, want cors", got)
	}
	if got := req.Header.Get("Sec-Fetch-Site"); got != "same-site" {
		t.Errorf("Sec-Fetch-Site = %q, want same-site", got)
	}
	if got := req.Header.Get("Origin"); got != "https://accounts.firefox.com" {
		t.Errorf("Origin = %q, want https://accounts.firefox.com", got)
	}
	if got := req.Header.Get("Referer"); got != "https://accounts.firefox.com/" {
		t.Errorf("Referer = %q, want https://accounts.firefox.com/", got)
	}
}
