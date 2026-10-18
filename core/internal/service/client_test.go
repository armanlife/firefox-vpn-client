package service

import (
	"context"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
)

func TestLocalClientReadsStatusThroughToken(t *testing.T) {
	d := newTestDaemon(t)
	d.localToken = "client-token"
	server := httptest.NewServer(newDashboardServer(d).handler())
	defer server.Close()

	cfg := d.config()
	cfg.Dashboard.Listen = strings.TrimPrefix(server.URL, "http://")
	if err := config.Save(d.paths.Config, cfg); err != nil {
		t.Fatal(err)
	}
	client := NewClient(d.paths)
	ctx := context.Background()
	if _, err := client.Status(ctx); err == nil || !strings.Contains(err.Error(), "not running") {
		t.Fatalf("without a token file: got %v", err)
	}
	if err := os.WriteFile(d.paths.LocalToken, []byte(d.localToken), 0o600); err != nil {
		t.Fatal(err)
	}
	d.setState(PhaseWaiting, "Add an account", time.Time{})
	st, err := client.Status(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if got := st.Summary(); got != "Waiting" {
		t.Fatalf("summary = %q", got)
	}
	st.State.Phase = "running"
	st.Proxy = &TrayProxy{CountryName: "Belgium", CityName: "Brussels"}
	if got := st.Summary(); got != "Connected · Belgium" {
		t.Fatalf("summary = %q", got)
	}
	// The recommended location names no place; the public IP does.
	st.Proxy.CountryCode, st.Proxy.CountryName = "REC", "Recommended location"
	if got := st.Summary(); got != "Connected" {
		t.Fatalf("recommended without a public IP: %q", got)
	}
	st.Exit = &struct {
		CountryCode string `json:"country_code"`
		CountryName string `json:"country_name"`
		City        string `json:"city"`
	}{CountryCode: "NL", CountryName: "Netherlands", City: "Amsterdam"}
	if got := st.Summary(); got != "Connected · Amsterdam, Netherlands" {
		t.Fatalf("with the public IP: %q", got)
	}
	st.Proxy.SleepingSince = time.Now()
	if got := st.Summary(); got != "Sleeping (wakes on the next connection) · Amsterdam, Netherlands" {
		t.Fatalf("sleeping: %q", got)
	}
	if err := client.RestartProxy(ctx); err != nil {
		t.Fatalf("restart: %v", err)
	}
	if _, err := client.ConnectionTest(ctx); err == nil || !strings.Contains(err.Error(), "not running") {
		t.Fatalf("connection test without engine: got %v", err)
	}
}

func TestLoopbackAddr(t *testing.T) {
	for in, want := range map[string]string{
		"127.0.0.1:10820":  "127.0.0.1:10820",
		"0.0.0.0:10820":    "127.0.0.1:10820",
		"[::]:10820":       "127.0.0.1:10820",
		":10820":           "127.0.0.1:10820",
		"192.168.1.5:8080": "192.168.1.5:8080",
		"localhost:10820":  "localhost:10820",
		"[::1]:10820":      "[::1]:10820",
		"myhost.lan:10820": "127.0.0.1:10820",
	} {
		if got := loopbackAddr(in); got != want {
			t.Errorf("loopbackAddr(%q) = %q, want %q", in, got, want)
		}
	}
}
