# Builds the Windows app and its core and puts them over the installed copy
# (the Setup's per-user install, in the folder chosen at install time; by
# default %LOCALAPPDATA%\Programs\Arman VPN), to try a change
# without making and running an installer:
# - a running copy is closed first: the app by its process id, after which
#   its core restores the system proxy and exits, as when the app quits;
# - user-data in the install folder (accounts, settings, logs) is never
#   touched;
# - a copy that was running is started again, and connected again if it
#   was connected;
# - an installed TUN service is asked to replace itself with the new one,
#   which it does when the build is signed with its key (the developer key
#   in ARMAN_VPN_SIGNING_KEY_FILE; scripts\signing-key.ps1). The core gets
#   the same key: the app then installs only updates signed with it.
# The version is "major.minor.patch" from app\pubspec.yaml, or -AppVersion: an
# older one makes the app find the latest release as an update, to try the
# update notices. Nothing is written to dist\; scripts\build-windows.ps1
# makes the release files.
#Requires -Version 7
param([string]$AppVersion)
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$match = Select-String -Path "$root\app\pubspec.yaml" -Pattern '^version:\s*(\d+\.\d+\.\d+)'
if (-not $match) { throw 'No version in app\pubspec.yaml' }
$version = $match.Matches[0].Groups[1].Value
if ($AppVersion) { $version = $AppVersion }

# The install folder, from the Setup's uninstall entry (AppId in
# app\windows\installer\arman-vpn.iss).
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{6F3A2C1E-9B4D-4E7A-8C21-5D0F7B9E4A63}_is1'
$dir = (Get-ItemProperty $uninstallKey -ErrorAction SilentlyContinue).InstallLocation
if (-not $dir) { throw 'Arman VPN is not installed for this user; run the Setup once' }
$dir = $dir.TrimEnd('\')
$appExe = "$dir\arman-vpn.exe"
$dataDir = "$dir\user-data"

# The same build as scripts\build-windows.ps1, the core into app\build.
Push-Location "$root\app"
try {
    foreach ($stale in "build\flutter_assets", "build\windows\x64\runner\Release\data\flutter_assets") {
        if (Test-Path $stale) { Remove-Item -LiteralPath $stale -Recurse -Force }
    }
    flutter pub get --offline
    if ($LASTEXITCODE -ne 0) { flutter pub get }
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    flutter build windows --release --no-pub --dart-define=APP_VERSION=$version
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
} finally { Pop-Location }
$release = "$root\app\build\windows\x64\runner\Release"
$coreOut = "$root\app\build\installed-core"
$public = & "$PSScriptRoot\signing-key.ps1"
Push-Location "$root\core"
try {
    $env:APP_VERSION = $version
    go generate ./cmd/arman-vpn-core
    if ($LASTEXITCODE -ne 0) { throw 'go generate failed' }
    $ldflags = "-s -w -X github.com/armanlife/arman-vpn-client/core/internal/version.Current=$version"
    if ($public) { $ldflags += " -X github.com/armanlife/arman-vpn-client/core/internal/signing.Key=$public" }
    go build -trimpath -ldflags $ldflags -o "$coreOut\arman-vpn-core.exe" ./cmd/arman-vpn-core
    if ($LASTEXITCODE -ne 0) { throw 'go build failed' }
} finally {
    Remove-Item Env:APP_VERSION -ErrorAction SilentlyContinue
    Pop-Location
}
& "$PSScriptRoot\build-windows-tun.ps1" -Version $version -Out $coreOut -PublicKey $public

# The core's API, as the app reaches it: the address from config.json and
# the local token. The token is only sent, never shown.
function Invoke-Core([string]$Method, [string]$Path, [hashtable]$Body) {
    $listen = '127.0.0.1:10820'
    try {
        $config = Get-Content "$dataDir\config.json" -Raw | ConvertFrom-Json
        if ($config.dashboard.listen) { $listen = $config.dashboard.listen }
    } catch {}
    $port = $listen.Substring($listen.LastIndexOf(':') + 1)
    $token = (Get-Content "$dataDir\local-api.token" -Raw).Trim()
    $request = @{
        Method = $Method; Uri = "http://127.0.0.1:$port/api$Path"; TimeoutSec = 5
        Headers = @{ 'X-Local-Token' = $token }
    }
    if ($Body) { $request.Body = $Body | ConvertTo-Json; $request.ContentType = 'application/json' }
    Invoke-RestMethod @request
}

function Get-Installed {
    # Path is read once: it is looked up on each read, and a process that
    # exits in between has none.
    Get-Process | Where-Object { $path = $_.Path; $path -and $path.StartsWith("$dir\", [StringComparison]::OrdinalIgnoreCase) }
}

$running = @(Get-Installed)
# The app may still run under its name before 1.0.9.
$appExes = @($appExe, "$dir\firefox-vpn.exe")
$appWasRunning = [bool]($running | Where-Object { $_.Path -in $appExes })
$wasOn = $false
if ($running) {
    try { $wasOn = (Invoke-Core GET /status).state.phase -notin 'off', '' } catch {}
    # The app first: its core sees the end of its standard input, restores
    # the system proxy, and exits.
    $running | Where-Object { $_.Path -in $appExes } | ForEach-Object { Stop-Process -Id $_.Id -Force }
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Installed) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    $left = @(Get-Installed)
    if ($left) {
        Write-Warning "Still running after 10 s, stopped by id: $($left.Id -join ', ')"
        $left | ForEach-Object { Stop-Process -Id $_.Id -Force }
        Start-Sleep -Milliseconds 500
    }
}

# Files replaced; extra files and user-data stay. Robocopy retries a file
# that a scanner holds open for a moment.
robocopy $release $dir /E /XD user-data data /XF portable /R:10 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "copying the app failed (robocopy $LASTEXITCODE)" }
# The app's assets exactly as built: an asset removed from the build (an
# old icon, say) must not stay behind and be used.
robocopy "$release\data" "$dir\data" /MIR /R:10 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "copying the app's assets failed (robocopy $LASTEXITCODE)" }
robocopy $coreOut "$dir\core" arman-vpn-core.exe arman-vpn-tun.exe arman-vpn-tun.exe.sig /R:10 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "copying the core failed (robocopy $LASTEXITCODE)" }
if (-not (Test-Path "$coreOut\arman-vpn-tun.exe.sig")) {
    Remove-Item "$dir\core\arman-vpn-tun.exe.sig" -ErrorAction SilentlyContinue
}
Set-ItemProperty $uninstallKey -Name DisplayVersion -Value $version
Write-Host "Installed $version in $dir"

# The installed TUN service, if any, replaces itself with the new one: the
# app's core asks only when the service is older, and a test build keeps
# the version. It refuses a build its key did not sign (then install it
# again: core\arman-vpn-tun.exe install, with the administrator prompt).
if (Get-Service ArmanVPNTun -ErrorAction SilentlyContinue) {
    $p = Start-Process -FilePath "$dir\core\arman-vpn-tun.exe" -ArgumentList update -Wait -PassThru -NoNewWindow -RedirectStandardError "$coreOut\tun-update.txt"
    $why = (Get-Content "$coreOut\tun-update.txt" -Raw -ErrorAction SilentlyContinue)
    if ($p.ExitCode -eq 0) { Write-Host 'The TUN service updated itself' }
    elseif ($why -match 'already this build') { Write-Host 'The TUN service is already this build' }
    else { Write-Warning "The TUN service did not update itself: $why" }
}

if ($appWasRunning) {
    # Without the proxy variables a build may have needed: the app's core
    # would inherit them and send its own requests to Mozilla through them.
    # They come back afterwards, for the terminal this script runs in.
    $saved = @{}
    foreach ($name in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY') {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name)
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }
    try {
        Start-Process -FilePath $appExe -WorkingDirectory $dir
        Write-Host 'Started the app again'
        if ($wasOn) {
            # The app's core starts with the proxy off.
            $deadline = (Get-Date).AddSeconds(30)
            $done = $false
            while (-not $done -and (Get-Date) -lt $deadline) {
                Start-Sleep -Seconds 1
                try { Invoke-Core POST /power @{ on = $true } | Out-Null; $done = $true } catch {}
            }
            if ($done) { Write-Host 'Connected again' } else { Write-Warning 'The app did not answer; connect by hand' }
        }
    } finally {
        foreach ($name in $saved.Keys) {
            if ($null -ne $saved[$name]) { Set-Item "Env:$name" $saved[$name] }
        }
    }
}
# Not robocopy's code, where 1 means "files copied".
exit 0
