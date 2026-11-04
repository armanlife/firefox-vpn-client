package proxy

import (
	"bytes"
	"context"
	"errors"
	"net"
	"net/netip"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/armanlife/arman-vpn-client/core/internal/routing"
	"github.com/armanlife/arman-vpn-client/core/internal/tun"
)

// fakeUDPTunnel echoes its packets, with its target in front.
type fakeUDPTunnel struct {
	target string
	in     chan []byte
	done   chan struct{}
	once   sync.Once
	route  string
}

func newFakeUDPTunnel(target string) *fakeUDPTunnel {
	return &fakeUDPTunnel{target: target, in: make(chan []byte, 64), done: make(chan struct{})}
}

func (t *fakeUDPTunnel) ReadPacket(p []byte) (int, error) {
	select {
	case packet := <-t.in:
		return copy(p, packet), nil
	case <-t.done:
		return 0, net.ErrClosed
	}
}

func (t *fakeUDPTunnel) WritePacket(p []byte) error {
	select {
	case <-t.done:
		return net.ErrClosed
	default:
	}
	t.in <- append([]byte(t.target+"|"), p...)
	return nil
}

func (t *fakeUDPTunnel) Close() error {
	t.once.Do(func() { close(t.done) })
	return nil
}

func (t *fakeUDPTunnel) Route() string { return t.route }

// fakeUDPOpener opens fake tunnels, slowly when told.
type fakeUDPOpener struct {
	mu      sync.Mutex
	opened  map[string]*fakeUDPTunnel
	count   atomic.Int32
	delay   time.Duration
	refused map[string]error
}

func (o *fakeUDPOpener) OpenTunnel(string) (net.Conn, error) {
	return nil, errors.New("this test has no TCP")
}

func (o *fakeUDPOpener) OpenUDP(authority, _ string) (UDPTunnel, error) {
	o.count.Add(1)
	time.Sleep(o.delay)
	o.mu.Lock()
	defer o.mu.Unlock()
	if err := o.refused[authority]; err != nil {
		return nil, err
	}
	if o.opened == nil {
		o.opened = map[string]*fakeUDPTunnel{}
	}
	tunnel := newFakeUDPTunnel(authority)
	o.opened[authority] = tunnel
	return tunnel, nil
}

func (o *fakeUDPOpener) tunnel(authority string) *fakeUDPTunnel {
	o.mu.Lock()
	defer o.mu.Unlock()
	return o.opened[authority]
}

// socksUDPServer serves SOCKS5 with upstream, as the TUN listener does, with
// a login.
func socksUDPServer(t *testing.T, upstream tunnelOpener) (*SOCKSServer, string) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	s := NewSOCKSServer(upstream, 5*time.Second, time.Minute, 16)
	s.Auth = SOCKSCredentials("u", "p")
	s.Conns = &Connections{}
	go ServeSOCKS(ln, s)
	return s, ln.Addr().String()
}

func associate(t *testing.T, addr string) *tun.UDPAssociation {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	a, err := tun.SOCKS5Associate(ctx, addr, "u", "p")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(a.Close)
	return a
}

type received struct {
	from, data string
}

// recvAll passes an association's replies to a channel.
func recvAll(a *tun.UDPAssociation) chan received {
	out := make(chan received, 64)
	go func() {
		b := make([]byte, 70000)
		for {
			n, from, err := a.Recv(b)
			if err != nil {
				close(out)
				return
			}
			out <- received{from, string(b[:n])}
		}
	}()
	return out
}

func expectReply(t *testing.T, replies chan received, want received) {
	t.Helper()
	select {
	case got, ok := <-replies:
		if !ok {
			t.Fatal("the association ended")
		}
		if got != want {
			t.Fatalf("got %+v, want %+v", got, want)
		}
	case <-time.After(5 * time.Second):
		t.Fatalf("no reply; want %+v", want)
	}
}

// Each destination gets a tunnel of its own, names keep their name, and each
// reply says who it comes from.
func TestSOCKSUDPCarriesPacketsToEachDestination(t *testing.T) {
	opener := &fakeUDPOpener{}
	_, addr := socksUDPServer(t, opener)
	a := associate(t, addr)
	replies := recvAll(a)
	for _, target := range []string{"stun.example:3478", "1.2.3.4:50000", "[2001:db8::1]:443"} {
		if err := a.Send(target, []byte("ping")); err != nil {
			t.Fatal(err)
		}
		expectReply(t, replies, received{target, target + "|ping"})
	}
	if got := opener.count.Load(); got != 3 {
		t.Fatalf("%d tunnels", got)
	}
	// The second packet to a destination uses its tunnel.
	if err := a.Send("stun.example:3478", []byte("again")); err != nil {
		t.Fatal(err)
	}
	expectReply(t, replies, received{"stun.example:3478", "stun.example:3478|again"})
	if got := opener.count.Load(); got != 3 {
		t.Fatalf("a second tunnel to one destination: %d", got)
	}
}

// The packets sent while the tunnel opens are not lost, up to a limit.
func TestSOCKSUDPKeepsPacketsWhileTheTunnelOpens(t *testing.T) {
	opener := &fakeUDPOpener{delay: 200 * time.Millisecond}
	_, addr := socksUDPServer(t, opener)
	a := associate(t, addr)
	replies := recvAll(a)
	for _, p := range []string{"1", "2", "3"} {
		if err := a.Send("peer.example:443", []byte(p)); err != nil {
			t.Fatal(err)
		}
	}
	for _, p := range []string{"1", "2", "3"} {
		expectReply(t, replies, received{"peer.example:443", "peer.example:443|" + p})
	}
	if got := opener.count.Load(); got != 1 {
		t.Fatalf("%d tunnels for one destination", got)
	}
}

// A refused destination is not asked again for each packet; others go on.
func TestSOCKSUDPRemembersARefusal(t *testing.T) {
	opener := &fakeUDPOpener{refused: map[string]error{"1.1.1.1:53": ErrUDPPort}}
	server, addr := socksUDPServer(t, opener)
	a := associate(t, addr)
	replies := recvAll(a)
	for range 5 {
		if err := a.Send("1.1.1.1:53", []byte("q")); err != nil {
			t.Fatal(err)
		}
		time.Sleep(10 * time.Millisecond)
	}
	if err := a.Send("peer.example:443", []byte("ok")); err != nil {
		t.Fatal(err)
	}
	expectReply(t, replies, received{"peer.example:443", "peer.example:443|ok"})
	if got := opener.count.Load(); got != 2 {
		t.Fatalf("%d opens; a refusal should stop the next ones", got)
	}
	var routes []string
	for _, c := range server.Conns.List() {
		if c.Network != "udp" {
			t.Errorf("connection %+v is not udp", c)
		}
		routes = append(routes, c.Target+" "+c.Route)
	}
	if !strings.Contains(strings.Join(routes, ","), "1.1.1.1:53 port") {
		t.Errorf("the list says %v", routes)
	}
}

// The VPN's rule: a destination it rejects gets no tunnel, and the others go on.
func TestSOCKSUDPKeepsToTheRule(t *testing.T) {
	opener := &fakeUDPOpener{}
	server, addr := socksUDPServer(t, opener)
	server.AllowUDP = func(_, port string) bool { return port != "443" }
	a := associate(t, addr)
	replies := recvAll(a)
	if err := a.Send("quic.example:443", []byte("q")); err != nil {
		t.Fatal(err)
	}
	if err := a.Send("peer.example:3478", []byte("ok")); err != nil {
		t.Fatal(err)
	}
	expectReply(t, replies, received{"peer.example:3478", "peer.example:3478|ok"})
	if got := opener.count.Load(); got != 1 {
		t.Fatalf("%d opens; the rejected destination should get none", got)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		for _, c := range server.Conns.List() {
			if c.Target == "quic.example:443" {
				if c.Network != "udp" || c.Route != RoutePort {
					t.Fatalf("the list says %+v", c)
				}
				return
			}
		}
		if time.Now().After(deadline) {
			t.Fatal("the refusal is not in the list")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// A tunnel that ended is opened again by a later packet.
func TestSOCKSUDPReopensAnEndedTunnel(t *testing.T) {
	opener := &fakeUDPOpener{}
	_, addr := socksUDPServer(t, opener)
	a := associate(t, addr)
	replies := recvAll(a)
	if err := a.Send("peer.example:443", []byte("1")); err != nil {
		t.Fatal(err)
	}
	expectReply(t, replies, received{"peer.example:443", "peer.example:443|1"})
	_ = opener.tunnel("peer.example:443").Close()
	deadline := time.Now().Add(udpRetryWait + 5*time.Second)
	for opener.count.Load() < 2 {
		if time.Now().After(deadline) {
			t.Fatal("the flow did not reopen")
		}
		_ = a.Send("peer.example:443", []byte("2"))
		time.Sleep(50 * time.Millisecond)
	}
}

// The association and its tunnels end with the TCP connection.
func TestSOCKSUDPEndsWithItsConnection(t *testing.T) {
	opener := &fakeUDPOpener{}
	server, addr := socksUDPServer(t, opener)
	a := associate(t, addr)
	replies := recvAll(a)
	if err := a.Send("peer.example:443", []byte("1")); err != nil {
		t.Fatal(err)
	}
	expectReply(t, replies, received{"peer.example:443", "peer.example:443|1"})
	a.Close()
	select {
	case <-opener.tunnel("peer.example:443").done:
	case <-time.After(5 * time.Second):
		t.Fatal("the tunnel outlived its association")
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		open := 0
		for _, c := range server.Conns.List() {
			if c.End.IsZero() {
				open++
			}
		}
		if open == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("%d connections still listed open", open)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// When the engine stops, its clients' associations end, so that they ask the
// next engine instead of the stopped one for as long as they send.
func TestSOCKSUDPEndsWhenTheEngineStops(t *testing.T) {
	routed := NewRoutedOpener(&fakeUDPUpstream{})
	_, addr := socksUDPServer(t, routed)
	a := associate(t, addr)
	replies := recvAll(a)
	if err := a.Send("peer.example:443", []byte("1")); err != nil {
		t.Fatal(err)
	}
	expectReply(t, replies, received{"peer.example:443", "peer.example:443|1"})
	routed.Close()
	// A new destination asks the stopped engine.
	if err := a.Send("other.example:443", []byte("2")); err != nil {
		t.Fatal(err)
	}
	select {
	case _, ok := <-replies:
		if ok {
			t.Fatal("a reply from a stopped engine")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the association goes on")
	}
}

// Only the client's address and port are served, and replies go only there.
func TestSOCKSUDPServesOnlyItsClient(t *testing.T) {
	opener := &fakeUDPOpener{}
	_, addr := socksUDPServer(t, opener)
	ctrl, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	defer ctrl.Close()
	// The handshake, by hand, to know the relay.
	mustWrite(t, ctrl, []byte{5, 1, 2})
	mustRead(t, ctrl, 2)
	mustWrite(t, ctrl, append(append([]byte{1, 1}, 'u', 1), 'p'))
	mustRead(t, ctrl, 2)
	mustWrite(t, ctrl, []byte{5, socksCmdUDP, 0, socksAtypIPv4, 0, 0, 0, 0, 0, 0})
	reply := mustRead(t, ctrl, 10)
	if reply[1] != socksReplySuccess {
		t.Fatalf("reply %v", reply)
	}
	relay := netip.AddrPortFrom(netip.AddrFrom4([4]byte(reply[4:8])), uint16(reply[8])<<8|uint16(reply[9]))

	datagram := append([]byte{0, 0, 0, socksAtypDomain, 4}, "a.ex"...)
	datagram = append(datagram, 0, 80)

	// Another address on this machine is not the client.
	other, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 2)})
	if err == nil {
		defer other.Close()
		_, _ = other.WriteToUDPAddrPort(append(datagram, "x"...), relay)
		time.Sleep(100 * time.Millisecond)
		if opener.count.Load() != 0 {
			t.Fatal("a packet from another address was served")
		}
	}
	// The first packet fixes the client's port.
	first, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer first.Close()
	if _, err := first.WriteToUDPAddrPort(append(datagram, "from first"...), relay); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 200)
	_ = first.SetReadDeadline(time.Now().Add(5 * time.Second))
	n, _, err := first.ReadFromUDPAddrPort(buf)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasSuffix(buf[:n], []byte("a.ex:80|from first")) || !bytes.HasPrefix(buf[:n], []byte{0, 0, 0, socksAtypDomain, 4, 'a'}) {
		t.Fatalf("reply %q", buf[:n])
	}
	second, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer second.Close()
	if _, err := second.WriteToUDPAddrPort(append(datagram, "from second"...), relay); err != nil {
		t.Fatal(err)
	}
	_ = second.SetReadDeadline(time.Now().Add(200 * time.Millisecond))
	if _, _, err := second.ReadFromUDPAddrPort(buf); err == nil {
		t.Fatal("a second port was served")
	}
}

func mustWrite(t *testing.T, c net.Conn, b []byte) {
	t.Helper()
	if _, err := c.Write(b); err != nil {
		t.Fatal(err)
	}
}

func mustRead(t *testing.T, c net.Conn, n int) []byte {
	t.Helper()
	b := make([]byte, n)
	_ = c.SetReadDeadline(time.Now().Add(5 * time.Second))
	for at := 0; at < n; {
		m, err := c.Read(b[at:])
		if err != nil {
			t.Fatal(err)
		}
		at += m
	}
	return b
}

func TestParseUDPRequest(t *testing.T) {
	for _, c := range []struct {
		name   string
		in     []byte
		target string
		data   string
		ok     bool
	}{
		{"ipv4", []byte{0, 0, 0, 1, 1, 2, 3, 4, 0, 53, 'q'}, "1.2.3.4:53", "q", true},
		{"ipv6", append(append([]byte{0, 0, 0, 4}, net.ParseIP("2001:db8::1")...), 1, 187, 'q'), "[2001:db8::1]:443", "q", true},
		{"name", []byte{0, 0, 0, 3, 1, 'a', 0, 80, 'q'}, "a:80", "q", true},
		{"empty packet", []byte{0, 0, 0, 1, 1, 2, 3, 4, 0, 53}, "1.2.3.4:53", "", true},
		{"a fragment", []byte{0, 0, 1, 1, 1, 2, 3, 4, 0, 53, 'q'}, "", "", false},
		{"reserved set", []byte{1, 0, 0, 1, 1, 2, 3, 4, 0, 53, 'q'}, "", "", false},
		{"short address", []byte{0, 0, 0, 1, 1, 2}, "", "", false},
		{"no port", []byte{0, 0, 0, 1, 1, 2, 3, 4, 0}, "", "", false},
		{"empty name", []byte{0, 0, 0, 3, 0, 0, 80}, "", "", false},
		{"unknown type", []byte{0, 0, 0, 9, 1, 2, 3, 4, 0, 53}, "", "", false},
		{"too short", []byte{0, 0}, "", "", false},
	} {
		target, data, ok := parseUDPRequest(c.in)
		if ok != c.ok || target != c.target || string(data) != c.data {
			t.Errorf("%s: %q %q %v", c.name, target, data, ok)
		}
	}
}

func TestUDPPortAllowed(t *testing.T) {
	for port, want := range map[string]bool{
		"80": true, "443": true, "3478": true, "8080": true, "8443": true, "49152": true, "65534": true,
		"53": false, "123": false, "3479": false, "8801": false, "19302": false, "49151": false, "65535": false, "0": false, "x": false, "70000": false,
	} {
		if got := UDPPortAllowed(port); got != want {
			t.Errorf("port %s: %v", port, got)
		}
	}
}

// fakeUDPUpstream is a tunnel opener with UDP; route says what got through.
type fakeUDPUpstream struct{ fakeUDPOpener }

// The routing applies to UDP as to TCP: directly, refused, or through Mozilla
// on its ports; DNS is answered without Mozilla carrying port 53.
func TestRoutedOpenerRoutesUDP(t *testing.T) {
	upstream := &fakeUDPUpstream{}
	o := NewRoutedOpener(upstream)
	t.Cleanup(o.Close)
	router, err := routing.New(routing.Config{Direct: []string{"domain:shop.ir"}, Block: []string{"full:ads.example"}})
	if err != nil {
		t.Fatal(err)
	}
	o.SetRouter(router)

	// Through Mozilla.
	tunnel, err := o.OpenUDP("stun.example:3478", "")
	if err != nil {
		t.Fatal(err)
	}
	defer tunnel.Close()
	if err := tunnel.WritePacket([]byte("x")); err != nil {
		t.Fatal(err)
	}
	b := make([]byte, 100)
	if _, err := tunnel.ReadPacket(b); err != nil {
		t.Fatal(err)
	}
	if tr := o.Traffic(); tr.Up == 0 || tr.Down == 0 {
		t.Errorf("not counted: %+v", tr)
	}
	if r, ok := tunnel.(interface{ Route() string }); !ok || r.Route() != RouteVPN {
		t.Error("the route is not VPN")
	}

	// A port Mozilla does not carry is refused without asking it.
	before := upstream.count.Load()
	if _, err := o.OpenUDP("stun.example:19302", ""); !errors.Is(err, ErrUDPPort) {
		t.Fatalf("err = %v", err)
	}
	if upstream.count.Load() != before {
		t.Fatal("Mozilla was asked")
	}
	// Refused by a rule.
	if _, err := o.OpenUDP("ads.example:443", ""); !errors.Is(err, ErrBlockedByRule) {
		t.Fatalf("err = %v", err)
	}

	// Directly by a rule, on any port.
	var dialed string
	echoServer, client := net.Pipe()
	defer echoServer.Close()
	o.dial = func(_ context.Context, network, address string) (net.Conn, error) {
		dialed = network + " " + address
		return client, nil
	}
	direct, err := o.OpenUDP("www.shop.ir:19302", "")
	if err != nil {
		t.Fatal(err)
	}
	defer direct.Close()
	if dialed != "udp www.shop.ir:19302" {
		t.Fatalf("dialed %q", dialed)
	}
	if r, ok := direct.(interface{ Route() string }); !ok || r.Route() != RouteDirect {
		t.Error("the route is not direct")
	}
	go func() {
		buf := make([]byte, 10)
		n, _ := echoServer.Read(buf)
		_, _ = echoServer.Write(buf[:n])
	}()
	if err := direct.WritePacket([]byte("hi")); err != nil {
		t.Fatal(err)
	}
	if n, err := direct.ReadPacket(b); err != nil || string(b[:n]) != "hi" {
		t.Fatalf("read %q, %v", b[:n], err)
	}

	// DNS.
	o.exchange = func(_ context.Context, query []byte) ([]byte, error) {
		return append([]byte("answer:"), query...), nil
	}
	dns, err := o.OpenUDP("1.1.1.1:53", "")
	if err != nil {
		t.Fatal(err)
	}
	defer dns.Close()
	if err := dns.WritePacket([]byte("query")); err != nil {
		t.Fatal(err)
	}
	if n, err := dns.ReadPacket(b); err != nil || string(b[:n]) != "answer:query" {
		t.Fatalf("read %q, %v", b[:n], err)
	}
}

// Without UDP upstream (no such opener) a client's UDP is refused.
func TestRoutedOpenerWithoutUDPUpstream(t *testing.T) {
	o := NewRoutedOpener(&fakeTunnelOpener{})
	t.Cleanup(o.Close)
	if _, err := o.OpenUDP("stun.example:3478", ""); !errors.Is(err, ErrUDPPort) {
		t.Fatalf("err = %v", err)
	}
}

// An upload delays the answer to a PING while nothing arrives: not a dead
// connection, for a while.
func TestWatchedConnKnowsAnUpload(t *testing.T) {
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()
	w := newWatchedConn(a)
	go func() {
		buf := make([]byte, 1<<20)
		for {
			if _, err := b.Read(buf); err != nil {
				return
			}
		}
	}()
	go func() { _, _ = b.Write([]byte("x")) }()
	if _, err := w.Read(make([]byte, 1)); err != nil {
		t.Fatal(err)
	}
	if w.uploading() {
		t.Fatal("nothing was sent")
	}
	if _, err := w.Write(make([]byte, upstreamBusyWrite)); err != nil {
		t.Fatal(err)
	}
	if !w.uploading() {
		t.Fatal("an upload was not seen")
	}
	// It stops counting once data arrives.
	go func() { _, _ = b.Write([]byte("x")) }()
	if _, err := w.Read(make([]byte, 1)); err != nil {
		t.Fatal(err)
	}
	if w.uploading() {
		t.Fatal("data arrived, yet it counts as uploading")
	}
	// And after the grace, however much was sent.
	if _, err := w.Write(make([]byte, upstreamBusyWrite)); err != nil {
		t.Fatal(err)
	}
	w.lastRead.Store(time.Now().Add(-2 * upstreamBusyGrace).UnixNano())
	if w.uploading() {
		t.Fatal("an upload excuses silence for ever")
	}
}
