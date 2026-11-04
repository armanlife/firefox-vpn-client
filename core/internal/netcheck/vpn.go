package netcheck

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strings"

	"github.com/armanlife/arman-vpn-client/core/internal/egress"
)

// fastlyASN is Fastly's network, where Firefox VPN's exits are.
const fastlyASN = 54113

// detailsURL names this device's public address and its network, as the
// exit probe asks through the tunnel (ip.sb); tests replace it.
var detailsURL = "https://api-ipv4.ip.sb/geoip"

// InsideVPN reports whether this device's own traffic, outside the tunnel,
// already leaves the internet through Fastly, the network of Firefox VPN's
// exits (and of iCloud Private Relay's): the internet itself goes through
// such a VPN, on this device or another (a TV that uses a computer's
// proxy). Mozilla's proxies let only web ports through, so this program's
// own connection to Mozilla is cut there. False when it cannot tell; tests
// replace it.
var InsideVPN = insideVPN

func insideVPN(ctx context.Context) bool {
	ctx, cancel := context.WithTimeout(ctx, Timeout)
	defer cancel()
	client := &http.Client{Transport: &http.Transport{
		Proxy: nil,
		// Outside the TUN adapter while the TUN mode runs, as the check.
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			return egress.Dialer(Timeout).DialContext(ctx, network, address)
		},
		DisableKeepAlives: true,
	}}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, detailsURL, nil)
	if err != nil {
		return false
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false
	}
	var details struct {
		ASN             int    `json:"asn"`
		ISP             string `json:"isp"`
		Organization    string `json:"organization"`
		ASNOrganization string `json:"asn_organization"`
	}
	if json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(&details) != nil {
		return false
	}
	if details.ASN == fastlyASN {
		return true
	}
	for _, name := range []string{details.ISP, details.Organization, details.ASNOrganization} {
		if strings.Contains(strings.ToLower(name), "fastly") {
			return true
		}
	}
	return false
}
