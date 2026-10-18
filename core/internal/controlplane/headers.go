package controlplane

import "net/http"

const mozillaVPNUserAgent = "MozillaVPN/2.35.0 (sys:linux; iap:true)"

// ApplyMozillaVPNHeaders sets the User-Agent and Accept headers sent with
// every control plane API request.
func ApplyMozillaVPNHeaders(req *http.Request) {
	req.Header.Set("User-Agent", mozillaVPNUserAgent)
	req.Header.Set("Accept", "application/json")
}
