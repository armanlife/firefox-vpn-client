package tunstack

import (
	"errors"
	"testing"
)

func TestAMissingDriverIsRecognized(t *testing.T) {
	for text, want := range map[string]bool{
		"open tun: open /dev/net/tun: no such device":            true,
		"open tun: open /dev/net/tun: no such file or directory": true,
		"open tun: open /dev/net/tun: permission denied":         false,
		"set ipv6 address: no such device":                       false,
		"configure tun interface: operation not permitted":       false,
	} {
		if got := missingDriver(errors.New(text)); got != want {
			t.Errorf("%q: got %v", text, got)
		}
	}
	if missingDriver(nil) {
		t.Error("no error is no missing driver")
	}
}
