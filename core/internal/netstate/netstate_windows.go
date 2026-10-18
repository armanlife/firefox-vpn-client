//go:build windows

package netstate

import (
	"errors"
	"unsafe"

	"golang.org/x/sys/windows"
)

// connected looks for an adapter that is up and has a default gateway.
// Adapters without one, such as Hyper-V's vEthernet for WSL and Docker,
// stay up while Wi-Fi and Ethernet are disconnected and do not count.
func connected() bool {
	list, err := adapters()
	if err != nil {
		return true
	}
	for _, a := range list {
		if a.up && a.gateway && !a.loopback {
			return true
		}
	}
	return false
}

type adapter struct {
	name                  string
	up, gateway, loopback bool
}

func adapters() ([]adapter, error) {
	const flags = windows.GAA_FLAG_INCLUDE_GATEWAYS | windows.GAA_FLAG_SKIP_ANYCAST | windows.GAA_FLAG_SKIP_MULTICAST | windows.GAA_FLAG_SKIP_DNS_SERVER
	size := uint32(16 << 10)
	for range 3 {
		buf := make([]byte, size)
		first := (*windows.IpAdapterAddresses)(unsafe.Pointer(&buf[0]))
		err := windows.GetAdaptersAddresses(windows.AF_UNSPEC, flags, 0, first, &size)
		if errors.Is(err, windows.ERROR_BUFFER_OVERFLOW) {
			continue
		}
		if err != nil {
			return nil, err
		}
		var list []adapter
		for a := first; a != nil; a = a.Next {
			list = append(list, adapter{
				name:     windows.UTF16PtrToString(a.FriendlyName),
				up:       a.OperStatus == windows.IfOperStatusUp,
				gateway:  a.FirstGatewayAddress != nil,
				loopback: a.IfType == windows.IF_TYPE_SOFTWARE_LOOPBACK,
			})
		}
		return list, nil
	}
	return nil, windows.ERROR_BUFFER_OVERFLOW
}
