package service

import (
	"errors"
	"fmt"
	"net"
)

// Listeners named in an AddressInUseError.
const (
	ListenerProxy     = "proxy"
	ListenerDashboard = "dashboard"
)

// CodeProxyPortInUse is the engine state code (state.code in /api/status)
// while the proxy cannot start because its listen address is taken.
const CodeProxyPortInUse = "proxy_port_in_use"

// AddressInUseError means a listener could not start because another
// program (or another copy of this one) already holds its address.
type AddressInUseError struct {
	// Listener is ListenerProxy or ListenerDashboard.
	Listener string
	// Address is the configured listen address.
	Address string
	Err     error
}

func (e *AddressInUseError) Error() string {
	return fmt.Sprintf("the %s address %s is already in use by another program", e.Listener, e.Address)
}

func (e *AddressInUseError) Unwrap() error { return e.Err }

// IsAddressInUse reports whether err is the system's "address already in
// use" error (EADDRINUSE, or WSAEADDRINUSE on Windows).
func IsAddressInUse(err error) bool {
	return errors.Is(err, errAddressInUse)
}

// listenTCP listens on addr for listener. A taken address is returned as
// an *AddressInUseError; other failures are wrapped with the address.
func listenTCP(listener, addr string) (net.Listener, error) {
	ln, err := net.Listen("tcp", addr)
	if err == nil {
		return ln, nil
	}
	if IsAddressInUse(err) {
		return nil, &AddressInUseError{Listener: listener, Address: addr, Err: err}
	}
	return nil, fmt.Errorf("listening on %s: %w", addr, err)
}

// probeListen checks that addr can be listened on now, without keeping it.
func probeListen(listener, addr string) error {
	ln, err := listenTCP(listener, addr)
	if err != nil {
		return err
	}
	return ln.Close()
}
