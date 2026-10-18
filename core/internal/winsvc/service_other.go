//go:build !windows

package winsvc

import (
	"errors"
	"os"

	"github.com/armanlife/firefox-vpn-client/core/internal/service"
)

const Supported = false

var errNoWindowsService = errors.New("the Windows service is only available on Windows; on Linux use scripts/install-systemd.sh")

func RunningAsService() bool { return false }

func IsElevated() bool { return os.Geteuid() == 0 }

func Run(service.DataPaths, bool) error { return errNoWindowsService }

func Install(service.DataPaths) error { return errNoWindowsService }

func Uninstall(service.DataPaths) error { return errNoWindowsService }

type State struct {
	Installed    bool
	ExePath      string
	OtherDataDir string
}

func (s State) Running() bool { return false }

func (s State) RunsThisExecutable() bool { return false }

func (s State) String() string { return "not available" }

func Query() (State, error) { return State{}, nil }

func QueryFor(service.DataPaths) (State, error) { return State{}, nil }
