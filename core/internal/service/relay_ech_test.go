package service

import (
	"context"
	"crypto/ecdh"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/config"
	"github.com/armanlife/firefox-vpn-client/core/internal/resolver"
)

const (
	testRelayName  = "relay.test"
	testPublicName = "public.test"
)

// echKey makes an ECH key for testPublicName: the server's half, and the
// ECHConfigList a client gets from DNS.
func echKey(t *testing.T, id byte) (tls.EncryptedClientHelloKey, []byte) {
	t.Helper()
	priv, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	u16 := func(b []byte, v int) []byte { return binary.BigEndian.AppendUint16(b, uint16(v)) }
	var contents []byte
	contents = append(contents, id)
	contents = u16(contents, 0x0020) // DHKEM(X25519, HKDF-SHA256)
	pub := priv.PublicKey().Bytes()
	contents = u16(contents, len(pub))
	contents = append(contents, pub...)
	contents = u16(contents, 4)
	contents = u16(contents, 0x0001) // HKDF-SHA256
	contents = u16(contents, 0x0001) // AES-128-GCM
	contents = append(contents, 0)   // maximum_name_length
	contents = append(contents, byte(len(testPublicName)))
	contents = append(contents, testPublicName...)
	contents = u16(contents, 0) // no extensions
	config := u16(u16(nil, 0xfe0d), len(contents))
	config = append(config, contents...)
	list := append(u16(nil, len(config)), config...)
	return tls.EncryptedClientHelloKey{Config: config, PrivateKey: priv.Bytes(), SendAsRetry: true}, list
}

// handshakeSeen is what the test server saw of a client's handshake.
type handshakeSeen struct {
	serverName string
	ech        bool
}

// startECHServer runs a TLS 1.3 server for testRelayName and
// testPublicName with the given ECH keys (none: it does not take ECH). It
// returns the dialer's base configuration (trusting the server), its
// address, and what it saw of each handshake.
func startECHServer(t *testing.T, keys ...tls.EncryptedClientHelloKey) (*tls.Config, string, chan handshakeSeen) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	tmpl := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: testRelayName},
		DNSNames:              []string{testRelayName, testPublicName},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		IsCA:                  true,
		BasicConstraintsValid: true,
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	cert, _ := x509.ParseCertificate(der)
	ln, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{
		Certificates:             []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}},
		EncryptedClientHelloKeys: keys,
		MinVersion:               tls.VersionTLS12,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { ln.Close() })
	seen := make(chan handshakeSeen, 16)
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func(conn *tls.Conn) {
				defer conn.Close()
				if conn.Handshake() != nil {
					return
				}
				st := conn.ConnectionState()
				seen <- handshakeSeen{st.ServerName, st.ECHAccepted}
				_, _ = conn.Write([]byte("ok"))
			}(conn.(*tls.Conn))
		}
	}()
	roots := x509.NewCertPool()
	roots.AddCert(cert)
	return &tls.Config{RootCAs: roots}, ln.Addr().String(), seen
}

// testECHDialer reaches addr whatever address it is given, and gets its
// key from lookup.
func testECHDialer(t *testing.T, mode string, base *tls.Config, addr string, lookup func(context.Context, string) ([]byte, time.Duration, error)) *echDialer {
	t.Helper()
	e, err := newECHDialer(testRelayName, config.Network{APIRelayECH: mode}, func(ctx context.Context, network, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, addr)
	})
	if err != nil {
		t.Fatal(err)
	}
	e.base, e.lookup = base, lookup
	return e
}

func fixedLookup(key []byte, calls *atomic.Int32) func(context.Context, string) ([]byte, time.Duration, error) {
	return func(_ context.Context, name string) ([]byte, time.Duration, error) {
		calls.Add(1)
		if name != testRelayName {
			return nil, 0, errors.New("looked up " + name)
		}
		return key, 5 * time.Minute, nil
	}
}

// dialAndRead dials through e and returns the client's view of the
// handshake and the server's.
func dialAndRead(t *testing.T, e *echDialer, seen chan handshakeSeen) (tls.ConnectionState, handshakeSeen, error) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	conn, err := e.DialTLSContext(ctx, "tcp", testRelayName+":443")
	if err != nil {
		return tls.ConnectionState{}, handshakeSeen{}, err
	}
	defer conn.Close()
	if b, _ := io.ReadAll(conn); string(b) != "ok" {
		t.Fatalf("read %q", b)
	}
	var last handshakeSeen
	for drained := false; !drained; {
		select {
		case s := <-seen:
			last = s
		default:
			drained = true
		}
	}
	return conn.(*tls.Conn).ConnectionState(), last, nil
}

// With the key from DNS the relay's name travels encrypted, and the key
// is looked up once while it is fresh.
func TestRelayECHHidesTheRelaysName(t *testing.T) {
	key, list := echKey(t, 1)
	base, addr, seen := startECHServer(t, key)
	var calls atomic.Int32
	e := testECHDialer(t, config.RelayECHRequire, base, addr, fixedLookup(list, &calls))
	for range 2 {
		st, server, err := dialAndRead(t, e, seen)
		if err != nil {
			t.Fatal(err)
		}
		if !st.ECHAccepted || !server.ech || server.serverName != testRelayName {
			t.Fatalf("client ECH=%v, server saw %+v", st.ECHAccepted, server)
		}
	}
	if calls.Load() != 1 {
		t.Fatalf("looked the key up %d times", calls.Load())
	}
}

// A stale key is refused with the server's current one, which is used at
// once and kept.
func TestRelayECHTakesTheServersNewKey(t *testing.T) {
	_, stale := echKey(t, 1)
	current, currentList := echKey(t, 2)
	base, addr, seen := startECHServer(t, current)
	var calls atomic.Int32
	e := testECHDialer(t, config.RelayECHRequire, base, addr, fixedLookup(stale, &calls))
	st, server, err := dialAndRead(t, e, seen)
	if err != nil {
		t.Fatal(err)
	}
	if !st.ECHAccepted || !server.ech {
		t.Fatalf("client ECH=%v, server saw %+v", st.ECHAccepted, server)
	}
	if got, _ := e.currentKey(context.Background()); string(got) != string(currentList) {
		t.Fatal("the server's key is kept")
	}
}

// A relay that does not take ECH is reached without it in "on" mode and
// not at all in "require" mode; so is one whose key cannot be found.
func TestRelayECHFallsBackOnlyWhenAllowed(t *testing.T) {
	_, list := echKey(t, 1)
	base, addr, seen := startECHServer(t) // no ECH
	var calls atomic.Int32
	noKey := func(context.Context, string) ([]byte, time.Duration, error) {
		calls.Add(1)
		return nil, 0, fmt.Errorf("ECH key of relay.test: %w", resolver.ErrNoECH)
	}
	for _, c := range []struct {
		name   string
		lookup func(context.Context, string) ([]byte, time.Duration, error)
	}{
		{"server without ECH", fixedLookup(list, &atomic.Int32{})},
		{"no key in DNS", noKey},
	} {
		st, server, err := dialAndRead(t, testECHDialer(t, config.RelayECHOn, base, addr, c.lookup), seen)
		if err != nil {
			t.Fatalf("%s, on: %v", c.name, err)
		}
		if st.ECHAccepted || server.serverName != testRelayName {
			t.Fatalf("%s, on: client ECH=%v, server saw %+v", c.name, st.ECHAccepted, server)
		}
		_, _, err = dialAndRead(t, testECHDialer(t, config.RelayECHRequire, base, addr, c.lookup), seen)
		if err == nil || !strings.Contains(err.Error(), "require") {
			t.Fatalf("%s, require: %v", c.name, err)
		}
	}
	// "No key" stands an hour, a lookup that got no answer a minute: the
	// next request does not wait for DNS again meanwhile.
	calls.Store(0)
	e := testECHDialer(t, config.RelayECHOn, base, addr, noKey)
	for range 2 {
		if _, _, err := dialAndRead(t, e, seen); err != nil {
			t.Fatal(err)
		}
	}
	if calls.Load() != 1 || time.Until(e.expires) < 50*time.Minute {
		t.Fatalf("looked the key up %d times, kept %v", calls.Load(), time.Until(e.expires))
	}
	failed := testECHDialer(t, config.RelayECHOn, base, addr, func(context.Context, string) ([]byte, time.Duration, error) {
		return nil, 0, errors.New("every DNS server failed")
	})
	if _, _, err := dialAndRead(t, failed, seen); err != nil {
		t.Fatal(err)
	}
	if time.Until(failed.expires) > 2*time.Minute {
		t.Fatalf("an unanswered lookup is kept %v", time.Until(failed.expires))
	}
}

// A key in the settings is used as it is, without DNS; a name there is
// looked up instead of the relay's.
func TestRelayECHKeyFromTheSettings(t *testing.T) {
	key, list := echKey(t, 1)
	base, addr, seen := startECHServer(t, key)
	e, err := newECHDialer(testRelayName, config.Network{
		APIRelayECH:       config.RelayECHRequire,
		APIRelayECHConfig: base64Std(list),
	}, func(ctx context.Context, network, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, network, addr)
	})
	if err != nil {
		t.Fatal(err)
	}
	e.base = base
	e.lookup = func(context.Context, string) ([]byte, time.Duration, error) {
		t.Fatal("no lookup with a key in the settings")
		return nil, 0, nil
	}
	if st, _, err := dialAndRead(t, e, seen); err != nil || !st.ECHAccepted {
		t.Fatalf("ECH=%v err=%v", st.ECHAccepted, err)
	}

	named, err := newECHDialer(testRelayName, config.Network{APIRelayECH: config.RelayECHOn, APIRelayECHConfig: "Cloudflare-ECH.com."}, nil)
	if err != nil || named.keyName != "cloudflare-ech.com" {
		t.Fatalf("key name %q, err %v", named.keyName, err)
	}
}

func TestParseECHSource(t *testing.T) {
	_, list := echKey(t, 1)
	for raw, want := range map[string]string{
		"":                         "",
		"cloudflare-ech.com":       "name",
		" crypto.cloudflare.com. ": "name",
		base64Std(list):            "key",
		"bad name.com":             "error",
		"AAAA":                     "error", // base64, but not an ECHConfigList
		"localhost":                "error",
	} {
		name, key, err := config.ParseECHSource(raw)
		got := ""
		switch {
		case err != nil:
			got = "error"
		case name != "":
			got = "name"
		case key != nil:
			got = "key"
		}
		if got != want {
			t.Errorf("%q: got %s (%v), want %s", raw, got, err, want)
		}
	}
	for mode, ok := range map[string]bool{"": true, "off": true, "on": true, "require": true, "yes": false} {
		cfg := config.Default()
		cfg.Network.APIRelayECH = mode
		if err := cfg.Validate(); (err == nil) != ok {
			t.Errorf("api_relay_ech %q: %v", mode, err)
		}
	}
}

func base64Std(b []byte) string { return base64.StdEncoding.EncodeToString(b) }
