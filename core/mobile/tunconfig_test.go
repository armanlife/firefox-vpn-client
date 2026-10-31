package mobile

import (
	"strings"
	"testing"
)

func TestTun2SocksConfig(t *testing.T) {
	config, err := tun2socksConfig(1500, "127.0.0.1:40123", "tun", "se-cr_et")
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"mtu: 1500",
		"address: '127.0.0.1'",
		"port: 40123",
		"username: 'tun'",
		"password: 'se-cr_et'",
		"pipeline: true",
		// The range of tun.IsFake, and the VPN's DNS server in CoreService.kt.
		"network: 198.18.0.0",
		"netmask: 255.254.0.0",
		"address: 172.19.0.2",
		"tcp-read-write-timeout: 86400000",
		"max-session-count: 3000",
	} {
		if !strings.Contains(config, want) {
			t.Errorf("no %q in:\n%s", want, config)
		}
	}
	if _, err := tun2socksConfig(1500, "no port", "tun", "x"); err == nil {
		t.Error("a bad listener address gave a configuration")
	}
}
