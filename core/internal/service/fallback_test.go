package service

import (
	"testing"

	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
	"github.com/armanlife/firefox-vpn-client/core/internal/serverlist"
)

func oneServerCountry(code, host string) serverlist.Country {
	return serverlist.Country{Name: code, Code: code, Cities: []serverlist.City{
		{Name: code + " city", Code: "c", Servers: []serverlist.Server{{Hostname: host, Port: 2499}}},
	}}
}

// The recommended location's stand-ins: the exit's country first, then
// the fastest measured locations, then the nearby defaults; three
// locations at most, never the recommended one itself.
func TestRecommendedFallbackOrder(t *testing.T) {
	d := &Daemon{countries: []serverlist.Country{
		oneServerCountry("ZA", "za.example"),
		oneServerCountry("DE", "de.example"),
		oneServerCountry("SE", "se.example"),
		oneServerCountry("NL", "nl.example"),
		oneServerCountry("FR", "fr.example"),
		oneServerCountry(serverlist.RecommendedCountryCode, "rec.example"),
	}}
	hosts := func() []string {
		var out []string
		for _, c := range d.recommendedFallback() {
			out = append(out, c.Addr)
		}
		return out
	}
	same := func(got []string, want ...string) bool {
		if len(got) != len(want) {
			return false
		}
		for i := range got {
			if got[i] != want[i] {
				return false
			}
		}
		return true
	}

	if got := hosts(); !same(got, "nl.example:2499", "de.example:2499", "fr.example:2499") {
		t.Fatalf("without measurements: %v", got)
	}
	d.exit = &proxy.ExitProbeResult{CountryCode: "se"}
	d.pings = []proxy.LocationPing{
		{Code: serverlist.RecommendedCountryCode, Recommended: true, PingMS: 50},
		{Code: "ZA", PingMS: 80},
		{Code: "DE", Error: "timeout"},
		{Code: "FR", PingMS: 90},
	}
	if got := hosts(); !same(got, "se.example:2499", "za.example:2499", "fr.example:2499") {
		t.Fatalf("with the exit and measurements: %v", got)
	}
}
