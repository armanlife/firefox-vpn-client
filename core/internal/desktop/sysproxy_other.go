//go:build !windows

package desktop

const systemProxySupported = false

func setSystemProxy(string) error { return nil }

func restoreSystemProxy(string) error { return nil }

func clearSystemProxy() error { return nil }
