//go:build windows

package winsvc

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
	"unsafe"

	"github.com/armanlife/firefox-vpn-client/core/internal/logx"
	"github.com/armanlife/firefox-vpn-client/core/internal/service"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

const Supported = true

const (
	serviceName        = "FirefoxVPN"
	serviceDisplayName = "Firefox VPN proxy"
	serviceDescription = "Local SOCKS5 proxy through Mozilla's VPN servers, with a web dashboard."

	// The service runs as LocalService, which has no administrator rights;
	// installation grants it access to the data folder and the executable.
	serviceAccount   = `NT AUTHORITY\LocalService`
	localServiceSID  = "*S-1-5-19"
	serviceWaitLimit = 30 * time.Second

	// serviceResultName receives the outcome of an elevated service command,
	// because the elevated copy runs without a visible console.
	serviceResultName = "service-command.txt"
)

// windowsService runs the daemon under the Service Control Manager.
type windowsService struct {
	paths   service.DataPaths
	verbose bool
}

func (s *windowsService) Execute(_ []string, requests <-chan svc.ChangeRequest, changes chan<- svc.Status) (bool, uint32) {
	changes <- svc.Status{State: svc.StartPending}
	d, err := service.NewDaemon(s.paths, s.verbose)
	if err != nil {
		logx.Error("service start failed err=%s", logx.Err(err))
		return false, uint32(windows.ERROR_SERVICE_SPECIFIC_ERROR)
	}
	done := make(chan error, 1)
	go func() { done <- d.Run() }()
	changes <- svc.Status{State: svc.Running, Accepts: svc.AcceptStop | svc.AcceptShutdown}
	for {
		select {
		case err := <-done:
			if err != nil {
				// A non-zero exit lets the recovery actions restart the
				// service, for example after a port was busy.
				logx.Error("service failed err=%s", logx.Err(err))
				return false, uint32(windows.ERROR_SERVICE_SPECIFIC_ERROR)
			}
			return false, 0
		case req := <-requests:
			switch req.Cmd {
			case svc.Interrogate:
				changes <- req.CurrentStatus
			case svc.Stop, svc.Shutdown:
				changes <- svc.Status{State: svc.StopPending, WaitHint: 20000}
				d.Shutdown()
				return false, 0
			}
		}
	}
}

// RunningAsService reports whether the Service Control Manager started this
// process.
func RunningAsService() bool {
	ok, err := svc.IsWindowsService()
	return err == nil && ok
}

// Run runs the daemon as the FirefoxVPN Windows service.
func Run(paths service.DataPaths, verbose bool) error {
	if !RunningAsService() {
		return errors.New("-service is used by the installed Windows service; install it with -install-service")
	}
	logx.EnableFile(paths.LogDir, false)
	return svc.Run(serviceName, &windowsService{paths: paths, verbose: verbose})
}

// State describes the installed service as seen by any user.
type State struct {
	Installed bool
	State     svc.State
	// ExePath and DataDir come from the service command line, when it can
	// be read.
	ExePath string
	DataDir string
	// OtherDataDir is set (with Installed false) when the computer's one
	// FirefoxVPN service serves another data folder.
	OtherDataDir string
}

// RunsThisExecutable reports whether the service runs this very file.
func (s State) RunsThisExecutable() bool {
	exe, err := os.Executable()
	if err != nil || s.ExePath == "" {
		return false
	}
	return strings.EqualFold(filepath.Clean(exe), filepath.Clean(s.ExePath))
}

func (s State) Running() bool {
	return s.Installed && (s.State == svc.Running || s.State == svc.StartPending)
}

func (s State) String() string {
	if !s.Installed {
		return "not installed"
	}
	switch s.State {
	case svc.Running:
		return "running"
	case svc.StartPending:
		return "starting"
	case svc.StopPending:
		return "stopping"
	case svc.Stopped:
		return "stopped"
	}
	return fmt.Sprintf("state %d", s.State)
}

// Query reads the service state with query-only rights, so it works
// without administrator rights.
func Query() (State, error) {
	scm, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return State{}, err
	}
	defer windows.CloseServiceHandle(scm)
	name, _ := windows.UTF16PtrFromString(serviceName)
	h, err := windows.OpenService(scm, name, windows.SERVICE_QUERY_STATUS|windows.SERVICE_QUERY_CONFIG)
	if errors.Is(err, windows.ERROR_ACCESS_DENIED) {
		h, err = windows.OpenService(scm, name, windows.SERVICE_QUERY_STATUS)
	}
	if errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST) {
		return State{}, nil
	}
	if err != nil {
		return State{}, err
	}
	defer windows.CloseServiceHandle(h)
	var status windows.SERVICE_STATUS
	if err := windows.QueryServiceStatus(h, &status); err != nil {
		return State{}, err
	}
	st := State{Installed: true, State: svc.State(status.CurrentState)}
	if cfg, err := (&mgr.Service{Name: serviceName, Handle: h}).Config(); err == nil {
		st.ExePath, st.DataDir = ParseCommandLine(cfg.BinaryPathName)
	}
	return st, nil
}

// QueryFor returns the service state when the service serves the
// data folder of paths, and "not installed" when it serves another folder:
// there is one FirefoxVPN service per computer.
func QueryFor(paths service.DataPaths) (State, error) {
	st, err := Query()
	if err != nil || !st.Installed || st.DataDir == "" {
		return st, err
	}
	if !strings.EqualFold(filepath.Clean(st.DataDir), filepath.Clean(paths.Dir)) {
		return State{OtherDataDir: st.DataDir}, nil
	}
	return st, nil
}

// ParseCommandLine returns the executable and the -data-dir value
// of a service command line.
func ParseCommandLine(cmd string) (exe, dataDir string) {
	args, err := windows.DecomposeCommandLine(strings.TrimSpace(cmd))
	if err != nil || len(args) == 0 {
		return "", ""
	}
	for i := 1; i < len(args)-1; i++ {
		if args[i] == "-data-dir" || args[i] == "--data-dir" {
			dataDir = args[i+1]
		}
	}
	return args[0], dataDir
}

func IsElevated() bool {
	return windows.GetCurrentProcessToken().IsElevated()
}

// Install installs (or updates) and starts the FirefoxVPN service.
// Without administrator rights it asks for them through UAC and runs the
// installation in an elevated copy of this executable.
func Install(paths service.DataPaths) error {
	if !IsElevated() {
		return runServiceCommandElevated(paths, "-install-service")
	}
	return recordServiceResult(paths, doInstallService(paths))
}

// Uninstall stops and removes the FirefoxVPN service.
func Uninstall(paths service.DataPaths) error {
	if !IsElevated() {
		return runServiceCommandElevated(paths, "-uninstall-service")
	}
	return recordServiceResult(paths, doUninstallService(paths))
}

func doInstallService(paths service.DataPaths) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	if err := grantServiceAccess(paths.Dir, exe); err != nil {
		return err
	}
	m, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("opening the service manager: %w", err)
	}
	defer m.Disconnect()

	args := []string{"-service", "-data-dir", paths.Dir}
	cfg := mgr.Config{
		ServiceType:      windows.SERVICE_WIN32_OWN_PROCESS,
		StartType:        mgr.StartAutomatic,
		ErrorControl:     mgr.ErrorNormal,
		DisplayName:      serviceDisplayName,
		Description:      serviceDescription,
		ServiceStartName: serviceAccount,
	}
	s, err := m.OpenService(serviceName)
	if err == nil {
		// Reinstalling updates the executable path and data folder.
		if err := stopService(s); err != nil {
			s.Close()
			return err
		}
		cfg.BinaryPathName = CommandLine(exe, args)
		if err := s.UpdateConfig(cfg); err != nil {
			s.Close()
			return fmt.Errorf("updating the service: %w", err)
		}
	} else {
		s, err = m.CreateService(serviceName, exe, cfg, args...)
		if err != nil {
			return fmt.Errorf("creating the service: %w", err)
		}
	}
	defer s.Close()

	restart := mgr.RecoveryAction{Type: mgr.ServiceRestart, Delay: 10 * time.Second}
	if err := s.SetRecoveryActions([]mgr.RecoveryAction{restart, restart, restart}, uint32((24 * time.Hour).Seconds())); err != nil {
		return fmt.Errorf("setting the restart policy: %w", err)
	}
	if err := s.SetRecoveryActionsOnNonCrashFailures(true); err != nil {
		return fmt.Errorf("setting the restart policy: %w", err)
	}
	if err := s.Start(); err != nil {
		return fmt.Errorf("starting the service: %w", err)
	}
	if err := waitServiceState(s, svc.Running); err != nil {
		return err
	}
	// The daemon reports Running before it opens its ports; a busy port
	// stops it within moments.
	time.Sleep(3 * time.Second)
	status, err := s.Query()
	if err == nil && status.State != svc.Running {
		return fmt.Errorf("the service stopped right after starting (is another copy using the proxy or dashboard port?); see the log in %s", paths.LogDir)
	}
	return nil
}

func doUninstallService(paths service.DataPaths) error {
	m, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("opening the service manager: %w", err)
	}
	defer m.Disconnect()
	s, err := m.OpenService(serviceName)
	if err != nil {
		return errors.New("the service is not installed")
	}
	defer s.Close()
	if err := stopService(s); err != nil {
		return err
	}
	if err := s.Delete(); err != nil {
		return fmt.Errorf("removing the service: %w", err)
	}
	revokeServiceAccess(paths.Dir)
	return nil
}

func stopService(s *mgr.Service) error {
	status, err := s.Query()
	if err != nil {
		return err
	}
	if status.State == svc.Stopped {
		return nil
	}
	if status.State != svc.StopPending {
		if _, err := s.Control(svc.Stop); err != nil {
			return fmt.Errorf("stopping the service: %w", err)
		}
	}
	return waitServiceState(s, svc.Stopped)
}

func waitServiceState(s *mgr.Service, want svc.State) error {
	deadline := time.Now().Add(serviceWaitLimit)
	for {
		status, err := s.Query()
		if err != nil {
			return err
		}
		if status.State == want {
			return nil
		}
		if want == svc.Running && status.State == svc.Stopped {
			return errors.New("the service stopped while starting; see the log file in the data folder")
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("the service did not reach the expected state (now %d)", status.State)
		}
		time.Sleep(300 * time.Millisecond)
	}
}

// grantServiceAccess lets LocalService modify the data folder and run the
// executable. Folders under a user profile deny other accounts by default.
func grantServiceAccess(dataDir, exe string) error {
	if out, err := exec.Command("icacls", dataDir, "/grant", localServiceSID+":(OI)(CI)M", "/Q").CombinedOutput(); err != nil {
		return fmt.Errorf("granting the service access to %s: %v: %s", dataDir, err, strings.TrimSpace(string(out)))
	}
	if out, err := exec.Command("icacls", exe, "/grant", localServiceSID+":RX", "/Q").CombinedOutput(); err != nil {
		return fmt.Errorf("granting the service access to %s: %v: %s", exe, err, strings.TrimSpace(string(out)))
	}
	return nil
}

func revokeServiceAccess(dataDir string) {
	_ = exec.Command("icacls", dataDir, "/remove:g", localServiceSID, "/Q").Run()
	if exe, err := os.Executable(); err == nil {
		_ = exec.Command("icacls", exe, "/remove:g", localServiceSID, "/Q").Run()
	}
}

// CommandLine builds a Run-key or service command line; the executable
// path is always quoted, as Windows recommends for both.
func CommandLine(exe string, args []string) string {
	return `"` + exe + `" ` + joinArgs(args)
}

func joinArgs(args []string) string {
	parts := make([]string, len(args))
	for i, arg := range args {
		parts[i] = windows.EscapeArg(arg)
	}
	return strings.Join(parts, " ")
}

// recordServiceResult stores the outcome of an elevated command for the
// non-elevated copy that started it.
func recordServiceResult(paths service.DataPaths, err error) error {
	message := "ok"
	if err != nil {
		message = err.Error()
	}
	_ = os.WriteFile(filepath.Join(paths.LogDir, serviceResultName), []byte(message), 0o600)
	return err
}

// runServiceCommandElevated reruns this executable with flag through UAC
// and waits for it.
func runServiceCommandElevated(paths service.DataPaths, flag string) error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	resultPath := filepath.Join(paths.LogDir, serviceResultName)
	if err := os.MkdirAll(filepath.Dir(resultPath), 0o700); err != nil {
		return err
	}
	_ = os.Remove(resultPath)
	code, err := shellExecuteRunAs(exe, joinArgs([]string{flag, "-data-dir", paths.Dir}))
	if err != nil {
		if errors.Is(err, windows.ERROR_CANCELLED) {
			return errors.New("administrator rights were not granted")
		}
		return err
	}
	result, readErr := os.ReadFile(resultPath)
	_ = os.Remove(resultPath)
	message := strings.TrimSpace(string(result))
	switch {
	case readErr == nil && message == "ok":
		return nil
	case readErr == nil && message != "":
		return errors.New(message)
	case code != 0:
		return fmt.Errorf("the elevated command failed with exit code %d; see the log in %s", code, paths.LogDir)
	}
	return nil
}

// shellExecuteInfo mirrors SHELLEXECUTEINFOW.
type shellExecuteInfo struct {
	cbSize       uint32
	fMask        uint32
	hwnd         windows.Handle
	lpVerb       *uint16
	lpFile       *uint16
	lpParameters *uint16
	lpDirectory  *uint16
	nShow        int32
	hInstApp     windows.Handle
	lpIDList     uintptr
	lpClass      *uint16
	hkeyClass    windows.Handle
	dwHotKey     uint32
	hIcon        windows.Handle
	hProcess     windows.Handle
}

const (
	seeMaskNoCloseProcess = 0x00000040
	seeMaskNoAsync        = 0x00000100
)

var procShellExecuteExW = windows.NewLazySystemDLL("shell32.dll").NewProc("ShellExecuteExW")

// shellExecuteRunAs starts exe elevated with a hidden window and returns
// its exit code.
func shellExecuteRunAs(exe, params string) (uint32, error) {
	verb, _ := windows.UTF16PtrFromString("runas")
	file, err := windows.UTF16PtrFromString(exe)
	if err != nil {
		return 0, err
	}
	args, err := windows.UTF16PtrFromString(params)
	if err != nil {
		return 0, err
	}
	info := shellExecuteInfo{
		fMask:        seeMaskNoCloseProcess | seeMaskNoAsync,
		lpVerb:       verb,
		lpFile:       file,
		lpParameters: args,
		nShow:        windows.SW_HIDE,
	}
	info.cbSize = uint32(unsafe.Sizeof(info))
	if ok, _, callErr := procShellExecuteExW.Call(uintptr(unsafe.Pointer(&info))); ok == 0 {
		return 0, callErr
	}
	if info.hProcess == 0 {
		return 0, errors.New("the elevated process did not start")
	}
	defer windows.CloseHandle(info.hProcess)
	if _, err := windows.WaitForSingleObject(info.hProcess, windows.INFINITE); err != nil {
		return 0, err
	}
	var code uint32
	if err := windows.GetExitCodeProcess(info.hProcess, &code); err != nil {
		return 0, err
	}
	return code, nil
}
