package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
	"github.com/armanlife/firefox-vpn-client/core/internal/serverlist"
)

// Client calls a running service's dashboard API with the local token
// from the data folder. The tray uses it whether the service runs in its own
// process or as a Windows service.
type Client struct {
	paths DataPaths
	http  *http.Client
}

func NewClient(paths DataPaths) *Client {
	return &Client{paths: paths, http: &http.Client{
		Timeout:   60 * time.Second,
		Transport: &http.Transport{Proxy: nil, DisableKeepAlives: true},
	}}
}

// TrayStatus is the part of GET /api/status the tray shows.
type TrayStatus struct {
	State struct {
		Phase   string `json:"phase"`
		Message string `json:"message"`
	} `json:"state"`
	Proxy         *TrayProxy     `json:"proxy"`
	ActiveAccount *AccountView   `json:"active_account"`
	Accounts      map[string]int `json:"accounts"`
	Version       string         `json:"version"`
	// Exit is where the public IP check found the traffic leaving, which
	// names the place even for the recommended (anycast) location.
	Exit *struct {
		CountryCode string `json:"country_code"`
		CountryName string `json:"country_name"`
		City        string `json:"city"`
	} `json:"exit"`
	// SystemProxy is the system_proxy.mode setting.
	SystemProxy string `json:"system_proxy"`
	// OpenFolderRequest rises when the dashboard asks to open the data
	// folder.
	OpenFolderRequest uint64 `json:"open_folder_request"`
}

// SetSystemProxy sets the system_proxy.mode setting.
func (c *Client) SetSystemProxy(ctx context.Context, mode string) error {
	return c.Do(ctx, http.MethodPost, "/api/system-proxy", map[string]string{"mode": mode}, nil)
}

// DashboardURL returns the loopback URL of the dashboard configured in the
// data folder.
func (c *Client) DashboardURL() (string, error) {
	cfg, _, err := config.Load(c.paths.Config)
	if err != nil {
		return "", err
	}
	if !cfg.Dashboard.Enabled {
		return "", errors.New("the dashboard is disabled in config.json")
	}
	return "http://" + loopbackAddr(cfg.Dashboard.Listen), nil
}

// loopbackAddr turns a listen address into one this machine can dial.
func loopbackAddr(listen string) string {
	host, port, err := net.SplitHostPort(listen)
	if err != nil {
		return listen
	}
	ip := net.ParseIP(host)
	switch {
	case host == "" || (ip != nil && ip.IsUnspecified()):
		host = "127.0.0.1"
	case ip == nil && !strings.EqualFold(host, "localhost"):
		host = "127.0.0.1"
	}
	return net.JoinHostPort(host, port)
}

// Do calls the API; body is sent as JSON ("{}" when nil) for every method
// but GET, and the response is decoded into out when it is not nil.
func (c *Client) Do(ctx context.Context, method, path string, body, out any) error {
	base, err := c.DashboardURL()
	if err != nil {
		return err
	}
	token, err := readLocalToken(c.paths.LocalToken)
	if err != nil {
		return fmt.Errorf("the service is not running (no local API token): %w", err)
	}
	var reader io.Reader
	if method != http.MethodGet {
		payload := []byte("{}")
		if body != nil {
			if payload, err = json.Marshal(body); err != nil {
				return err
			}
		}
		reader = bytes.NewReader(payload)
	}
	req, err := http.NewRequestWithContext(ctx, method, base+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set(localTokenHeader, token)
	if reader != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode/100 != 2 {
		var apiErr struct {
			Error string `json:"error"`
		}
		if json.Unmarshal(data, &apiErr) == nil && apiErr.Error != "" {
			return fmt.Errorf("%s (HTTP %d)", apiErr.Error, resp.StatusCode)
		}
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(data, out)
}

func (c *Client) Status(ctx context.Context) (TrayStatus, error) {
	var st TrayStatus
	err := c.Do(ctx, http.MethodGet, "/api/status", nil, &st)
	return st, err
}

func (c *Client) ConnectionTest(ctx context.Context) (proxy.ConnectionTestResult, error) {
	var result proxy.ConnectionTestResult
	err := c.Do(ctx, http.MethodPost, "/api/test", nil, &result)
	return result, err
}

// ExitApp asks the process hosting the service (the tray) to stop.
func (c *Client) ExitApp(ctx context.Context) error {
	return c.Do(ctx, http.MethodPost, "/api/app/exit", nil, nil)
}

func (c *Client) RestartProxy(ctx context.Context) error {
	return c.Do(ctx, http.MethodPost, "/api/proxy/restart", nil, nil)
}

// TrayProxy is the running proxy in TrayStatus.
type TrayProxy struct {
	Listen      string `json:"listen"`
	CountryCode string `json:"country_code"`
	CountryName string `json:"country_name"`
	CityName    string `json:"city_name"`
	// SleepingSince is set while the proxy sleeps (proxy.idle_sleep).
	SleepingSince time.Time `json:"sleeping_since"`
}

// Summary is the tray icon's hover text: the connection state and, when
// connected, the country.
func (st TrayStatus) Summary() string {
	status, ok := map[string]string{"running": "Connected", "starting": "Starting…", "waiting": "Waiting", "error": "Error"}[st.State.Phase]
	if !ok {
		status = "Unknown state"
	}
	if st.State.Phase == "running" && st.Proxy != nil && !st.Proxy.SleepingSince.IsZero() {
		status = "Sleeping (wakes on the next connection)"
	}
	if st.State.Phase == "running" {
		if place := st.place(); place != "" {
			status += " · " + place
		}
	}
	return status
}

// place is where the traffic leaves: the city and country of the public
// IP when known, else the selected location unless it is Mozilla's
// recommended one, which names no place ("Recommended location").
func (st TrayStatus) place() string {
	if e := st.Exit; e != nil {
		country := e.CountryName
		if country == "" {
			country = e.CountryCode
		}
		switch {
		case e.City != "" && country != "":
			return e.City + ", " + country
		case country != "":
			return country
		}
	}
	if st.Proxy != nil && !strings.EqualFold(st.Proxy.CountryCode, serverlist.RecommendedCountryCode) {
		return st.Proxy.CountryName
	}
	return ""
}
