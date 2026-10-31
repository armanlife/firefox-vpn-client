package tunservice

import (
	"context"
	"errors"
	"net"
	"net/netip"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/armanlife/firefox-vpn-client/core/internal/proxy"
	"github.com/armanlife/firefox-vpn-client/core/internal/tun"
	"github.com/armanlife/firefox-vpn-client/core/internal/tunapi"
)

// testUDPPorts is the shape of the core's list, without QUIC.
var testUDPPorts = []tunapi.PortRange{{From: 3478, To: 3478}, {From: 49152, To: 65534}}

// A packet goes through the VPN when Mozilla carries its port and it is for
// the internet; a program that skips the VPN keeps its way; others are refused,
// and a call told to the core.
func TestUDPRoutes(t *testing.T) {
	fakeOwners(t, map[uint16]string{
		1000: `C:\Games\Game.exe`,
		1001: "/opt/telegram/Telegram.exe",
		1002: systemPath(),
		1003: `C:\Apps\Discord.exe`,
	})
	s, core := coreSession(t, tunapi.Program{Name: "game.exe"}, tunapi.Program{Name: "telegram.exe", UDPOnly: true})
	s.udpPorts = testUDPPorts
	for _, c := range []struct {
		name string
		port uint16
		dst  string
		want udpVerdict
	}{
		{"a program that skips the VPN, carried port", 1000, "1.2.3.4:3478", udpDirect},
		{"a program that skips the VPN, other port", 1000, "1.2.3.4:19302", udpDirect},
		{"a program that skips the VPN, QUIC", 1000, "1.2.3.4:443", udpDirect},
		{"UDP only, a call", 1001, "1.2.3.4:19302", udpDirect},
		{"UDP only, QUIC stays refused", 1001, "1.2.3.4:443", udpRefused},
		{"another program, carried", 1003, "1.2.3.4:3478", udpThroughVPN},
		{"another program, high port", 1003, "1.2.3.4:50000", udpThroughVPN},
		{"another program, a fake address", 1003, "198.18.0.9:3478", udpThroughVPN},
		{"another program, IPv6", 1003, "[2001:4860:4860::1]:3478", udpThroughVPN},
		{"no program found, carried", 1004, "1.2.3.4:3478", udpThroughVPN},
		{"the system's, carried", 1002, "1.2.3.4:3478", udpThroughVPN},
		{"QUIC, not on the list", 1003, "1.2.3.4:443", udpRefused},
		{"the local network", 1003, "192.168.1.5:3478", udpRefused},
		{"a filtering DNS's address", 1003, "10.10.34.35:3478", udpRefused},
		{"discovery", 1003, "239.255.255.250:1900", udpRefused},
		{"the system's, other port", 1002, "1.2.3.4:19302", udpRefused},
	} {
		if got := s.udpRoute(port(c.port), netip.MustParseAddrPort(c.dst)); got != c.want {
			t.Errorf("%s: %v, want %v", c.name, got, c.want)
		}
	}
	if got := told(t, core); got != "" {
		t.Fatalf("the core was told of %q", got)
	}
	// A call on a port Mozilla does not carry is what the app offers to send
	// directly.
	if s.udpRoute(port(1003), netip.MustParseAddrPort("1.2.3.4:19302")) != udpRefused {
		t.Fatal("it was not refused")
	}
	if got := told(t, core); got != "Discord.exe" {
		t.Fatalf("told %q", got)
	}
}

// Without programs a carried packet needs no lookup, on the packet path.
func TestCarriedUDPNeedsNoLookup(t *testing.T) {
	lookups := fakeOwners(t, nil)
	s, _ := coreSession(t)
	s.udpPorts = testUDPPorts
	if !s.takeUDP(port(1000), netip.MustParseAddrPort("1.2.3.4:3478")) {
		t.Fatal("not taken")
	}
	if lookups.Load() != 0 {
		t.Fatal("a program was looked up")
	}
	if s.takeUDP(port(1000), netip.MustParseAddrPort("1.2.3.4:443")) || lookups.Load() != 0 {
		t.Fatal("QUIC was looked up or taken")
	}
}

// A core that names no ports (an older one) gets no UDP.
func TestAnOlderCoreGetsNoUDP(t *testing.T) {
	fakeOwners(t, nil)
	s, _ := coreSession(t)
	if s.takeUDP(port(1000), netip.MustParseAddrPort("1.2.3.4:3478")) {
		t.Fatal("taken")
	}
}

// coreUDP is the core's end: a real SOCKS5 server with fake tunnels that
// echo, each named by its target.
type coreUDP struct {
	mu      sync.Mutex
	targets []string
	count   atomic.Int32
	fail    atomic.Bool
}

func (c *coreUDP) OpenTunnel(string) (net.Conn, error) { return nil, errors.New("no TCP here") }

func (c *coreUDP) OpenUDP(authority, _ string) (proxy.UDPTunnel, error) {
	if c.fail.Load() {
		return nil, errors.New("refused")
	}
	c.count.Add(1)
	c.mu.Lock()
	c.targets = append(c.targets, authority)
	c.mu.Unlock()
	return &echoTunnel{target: authority, in: make(chan []byte, 16), done: make(chan struct{})}, nil
}

type echoTunnel struct {
	target string
	in     chan []byte
	done   chan struct{}
	once   sync.Once
}

func (t *echoTunnel) ReadPacket(p []byte) (int, error) {
	select {
	case b := <-t.in:
		return copy(p, b), nil
	case <-t.done:
		return 0, net.ErrClosed
	}
}

func (t *echoTunnel) WritePacket(p []byte) error {
	t.in <- append([]byte("echo:"), p...)
	return nil
}

func (t *echoTunnel) Close() error {
	t.once.Do(func() { close(t.done) })
	return nil
}

// vpnSession is a session whose UDP goes to a test core.
func vpnSession(t *testing.T) (*session, *coreUDP) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	core := &coreUDP{}
	server := proxy.NewSOCKSServer(core, 5*time.Second, time.Minute, 16)
	server.Auth = proxy.SOCKSCredentials("u", "p")
	go proxy.ServeSOCKS(ln, server)
	t.Cleanup(func() { _ = ln.Close() })
	s, _ := coreSession(t)
	s.udpPorts = testUDPPorts
	addr := ln.Addr().String()
	s.associate = func(ctx context.Context) (*tun.UDPAssociation, error) {
		return tun.SOCKS5Associate(ctx, addr, "u", "p")
	}
	return s, core
}

// UDP goes to the core with the name a fake address stands for; a real address
// as it is; the replies come from the address the app sent to; one association
// serves the flow's destinations.
func TestUDPThroughTheVPNGoesOutAndComesBack(t *testing.T) {
	fakeOwners(t, nil)
	s, core := vpnSession(t)
	reply, _ := s.dns.Answer(dnsQuery(t, "stun.example."))
	fake := netip.AddrPortFrom(lastA(t, reply), 3478)
	real := netip.MustParseAddrPort("1.2.3.4:50000")
	f := newFakePacketFlow()
	ended := make(chan struct{})
	go func() { s.relay(port(1000), f); close(ended) }()
	for _, c := range []struct {
		send packet
		want packet
	}{
		{packet{"by name", fake}, packet{"echo:by name", fake}},
		{packet{"by address", real}, packet{"echo:by address", real}},
		{packet{"again", fake}, packet{"echo:again", fake}},
	} {
		f.in <- c.send
		select {
		case got := <-f.out:
			if got != c.want {
				t.Errorf("sent %+v, got %+v, want %+v", c.send, got, c.want)
			}
		case <-time.After(5 * time.Second):
			t.Fatalf("no reply to %+v", c.send)
		}
	}
	if !f.accepted.Load() {
		t.Error("the flow was not accepted")
	}
	core.mu.Lock()
	targets := append([]string(nil), core.targets...)
	core.mu.Unlock()
	if len(targets) != 2 || targets[0] != "stun.example:3478" || targets[1] != "1.2.3.4:50000" {
		t.Fatalf("the core got %v", targets)
	}
	// A forgotten fake address leads nowhere.
	f.in <- packet{"nowhere", netip.MustParseAddrPort("198.19.200.1:3478")}
	// A port Mozilla does not carry, later in the same flow: refused.
	f.in <- packet{"no", netip.MustParseAddrPort("1.2.3.4:19302")}
	select {
	case got := <-f.out:
		t.Fatalf("answered: %+v", got)
	case <-time.After(200 * time.Millisecond):
	}
	if got := core.count.Load(); got != 2 {
		t.Fatalf("%d tunnels", got)
	}
	close(f.done)
	select {
	case <-ended:
	case <-time.After(5 * time.Second):
		t.Fatal("the relay did not end with its flow")
	}
}

// Within a flow that started on a carried port, a call on a port Mozilla does
// not carry is told to the core, so the app can offer to send it directly.
func TestAMidFlowCallIsTold(t *testing.T) {
	fakeOwners(t, map[uint16]string{1003: `C:\Apps\Discord.exe`})
	a, b := net.Pipe()
	t.Cleanup(func() { a.Close(); b.Close() })
	s, _ := vpnSession(t)
	s.owner = tunapi.NewConn(b)
	core := tunapi.NewConn(a)
	f := newFakePacketFlow()
	go s.relay(port(1003), f)
	t.Cleanup(func() { close(f.done) })
	f.in <- packet{"media", netip.MustParseAddrPort("1.2.3.4:19302")}
	if got := told(t, core); got != "Discord.exe" {
		t.Fatalf("told %q", got)
	}
}

// The association follows the core: when it ends, the flow does not die, and
// the next packet asks for a new one.
func TestUDPSurvivesTheCoreGoing(t *testing.T) {
	fakeOwners(t, nil)
	s, _ := vpnSession(t)
	var mu sync.Mutex
	var last *tun.UDPAssociation
	var asked int
	associate := s.associate
	s.associate = func(ctx context.Context) (*tun.UDPAssociation, error) {
		a, err := associate(ctx)
		mu.Lock()
		last = a
		asked++
		mu.Unlock()
		return a, err
	}
	dst := netip.MustParseAddrPort("1.2.3.4:3478")
	f := newFakePacketFlow()
	go s.relay(port(1000), f)
	t.Cleanup(func() { close(f.done) })
	f.in <- packet{"one", dst}
	select {
	case got := <-f.out:
		if got.data != "echo:one" {
			t.Fatalf("got %+v", got)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("no reply")
	}
	mu.Lock()
	last.Close()
	mu.Unlock()
	deadline := time.Now().Add(5 * time.Second)
	for {
		f.in <- packet{"two", dst}
		select {
		case got := <-f.out:
			if got.data != "echo:two" {
				t.Fatalf("got %+v", got)
			}
			mu.Lock()
			defer mu.Unlock()
			if asked != 2 {
				t.Fatalf("asked %d times", asked)
			}
			return
		case <-time.After(50 * time.Millisecond):
		}
		if time.Now().After(deadline) {
			t.Fatal("the flow did not come back")
		}
	}
}

// A core refusing the association drops packets without ending the flow, and
// does not ask for each packet.
func TestAFailedAssociationWaits(t *testing.T) {
	fakeOwners(t, nil)
	s, _ := coreSession(t)
	s.udpPorts = testUDPPorts
	var asked atomic.Int32
	s.associate = func(context.Context) (*tun.UDPAssociation, error) {
		asked.Add(1)
		return nil, errors.New("no core")
	}
	f := newFakePacketFlow()
	ended := make(chan struct{})
	go func() { s.relay(port(1000), f); close(ended) }()
	dst := netip.MustParseAddrPort("1.2.3.4:3478")
	for range 5 {
		f.in <- packet{"x", dst}
	}
	time.Sleep(50 * time.Millisecond)
	if got := asked.Load(); got != 1 {
		t.Fatalf("asked %d times", got)
	}
	close(f.done)
	select {
	case <-ended:
	case <-time.After(5 * time.Second):
		t.Fatal("the relay did not end")
	}
}
