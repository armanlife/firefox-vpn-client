package desktop

import (
	"bytes"
	"embed"
	"image"
	"image/png"
	"runtime"

	xdraw "golang.org/x/image/draw"
)

// appIconPNG is the program's icon, the fox shield (256 px, transparent),
// made by app/tool/app_icons.py from the same art as the app's icons.
//
//go:embed appicon.png
var appIconPNG []byte

// AppIconICO is the same icon in the sizes Windows uses, the small ones
// sharpened (made by app/tool/app_icons.py): the executable's resources
// (tools/winres).
//
//go:embed appicon.ico
var AppIconICO []byte

// AppIcon is the program's icon at size pixels, for its notifications.
func AppIcon(size int) image.Image {
	dst := image.NewNRGBA(image.Rect(0, 0, size, size))
	src, err := png.Decode(bytes.NewReader(appIconPNG))
	if err != nil {
		return dst // not possible with the embedded file
	}
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), src, src.Bounds(), xdraw.Src, nil)
	return dst
}

// trayFiles are the tray icons by state, made by app/tool/app_icons.py
// together with the app's tray icons: a disk in the state's color with the
// logo's shield in white. Windows takes the .ico files (several sizes), the
// other systems the 32 px .png files.
//
//go:embed tray
var trayFiles embed.FS

// Tray icon names.
const (
	iconRunning       = "running"
	iconRunningAsleep = "running-asleep" // running without a connection to Mozilla
	iconSet           = "set"            // running while Windows uses the proxy
	iconSetAsleep     = "set-asleep"
	iconWaiting       = "waiting"
	iconError         = "error"
	iconOff           = "off"
)

// trayIcon is the named tray icon in this system's format.
func trayIcon(name string) []byte {
	ext := ".png"
	if runtime.GOOS == "windows" {
		ext = ".ico"
	}
	data, _ := trayFiles.ReadFile("tray/" + name + ext)
	return data
}
