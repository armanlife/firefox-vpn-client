package tun

import (
	"context"
	"io"
	"net"
	"testing"
	"time"
)

func TestParseSOCKS5UDP(t *testing.T) {
	for _, c := range []struct {
		name string
		in   []byte
		from string
		data string
		ok   bool
	}{
		{"ipv4", []byte{0, 0, 0, 1, 1, 2, 3, 4, 0, 80, 'x'}, "1.2.3.4:80", "x", true},
		{"ipv6", append(append([]byte{0, 0, 0, 4}, net.ParseIP("2001:db8::1")...), 1, 187, 'x'), "[2001:db8::1]:443", "x", true},
		{"name", []byte{0, 0, 0, 3, 1, 'a', 0, 80, 'x'}, "a:80", "x", true},
		{"fragment", []byte{0, 0, 1, 1, 1, 2, 3, 4, 0, 80, 'x'}, "", "", false},
		{"short", []byte{0, 0, 0}, "", "", false},
		{"cut address", []byte{0, 0, 0, 1, 1}, "", "", false},
		{"cut name", []byte{0, 0, 0, 3, 5, 'a'}, "", "", false},
		{"no port", []byte{0, 0, 0, 1, 1, 2, 3, 4}, "", "", false},
		{"type", []byte{0, 0, 0, 7, 1, 2, 3, 4, 0, 80}, "", "", false},
	} {
		from, data, ok := parseSOCKS5UDP(c.in)
		if from != c.from || string(data) != c.data || ok != c.ok {
			t.Errorf("%s: %q %q %v", c.name, from, data, ok)
		}
	}
}

// socksServer answers a client's handshake with reply, from a real listener.
func socksServer(t *testing.T, reply []byte) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = ln.Close() })
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		buf := make([]byte, 3)
		if _, err := io.ReadFull(conn, buf); err != nil {
			return
		}
		_, _ = conn.Write([]byte{5, 0})
		request := make([]byte, 10)
		if _, err := io.ReadFull(conn, request); err != nil {
			return
		}
		_, _ = conn.Write(reply)
		_, _ = io.Copy(io.Discard, conn)
	}()
	return ln.Addr().String()
}

// A proxy refusing UDP says so.
func TestAssociateRefused(t *testing.T) {
	addr := socksServer(t, []byte{5, 7, 0, 1, 0, 0, 0, 0, 0, 0})
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, err := SOCKS5Associate(ctx, addr, "", ""); err == nil {
		t.Fatal("no error")
	}
}

// A relay given as an unspecified address is at the proxy's own.
func TestAssociateWithAnUnspecifiedRelay(t *testing.T) {
	relay, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	defer relay.Close()
	port := relay.LocalAddr().(*net.UDPAddr).Port
	addr := socksServer(t, []byte{5, 0, 0, 1, 0, 0, 0, 0, byte(port >> 8), byte(port)})
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	a, err := SOCKS5Associate(ctx, addr, "", "")
	if err != nil {
		t.Fatal(err)
	}
	defer a.Close()
	if err := a.Send("peer.example:3478", []byte("hi")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 100)
	_ = relay.SetReadDeadline(time.Now().Add(5 * time.Second))
	n, from, err := relay.ReadFromUDP(buf)
	if err != nil {
		t.Fatal(err)
	}
	want := append([]byte{0, 0, 0, 3, 12}, "peer.example"...)
	want = append(want, 0x0d, 0x96, 'h', 'i')
	if string(buf[:n]) != string(want) {
		t.Fatalf("sent %q, want %q", buf[:n], want)
	}
	if _, err := relay.WriteToUDP([]byte{0, 0, 0, 1, 1, 2, 3, 4, 0, 80, 'o', 'k'}, from); err != nil {
		t.Fatal(err)
	}
	got, source, err := a.Recv(buf)
	if err != nil || string(buf[:got]) != "ok" || source != "1.2.3.4:80" {
		t.Fatalf("got %q from %q, %v", buf[:got], source, err)
	}
}

// The association ends with the proxy's connection.
func TestAssociationEndsWithItsConnection(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		buf := make([]byte, 3)
		_, _ = io.ReadFull(conn, buf)
		_, _ = conn.Write([]byte{5, 0})
		request := make([]byte, 10)
		_, _ = io.ReadFull(conn, request)
		_, _ = conn.Write([]byte{5, 0, 0, 1, 127, 0, 0, 1, 0, 9})
		_ = conn.Close()
	}()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	a, err := SOCKS5Associate(ctx, ln.Addr().String(), "", "")
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		_, _, err := a.Recv(make([]byte, 10))
		done <- err
	}()
	select {
	case err := <-done:
		if err == nil {
			t.Fatal("no error")
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Recv goes on after the proxy closed")
	}
}
