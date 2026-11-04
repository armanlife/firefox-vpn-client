# Prints the public half of the key that updates are signed with
# (core\internal\signing): the release's SHA256SUMS.txt, which the Windows
# app checks before it installs a new version, and arman-vpn-tun.exe,
# which the installed TUN service checks before it replaces itself. The
# private key comes from ARMAN_VPN_SIGNING_KEY (base64, CI's secret) or
# the file named by ARMAN_VPN_SIGNING_KEY_FILE (a developer key); without
# one it prints nothing and warns: such a build takes no updates. The build
# scripts pass the result to the core and the TUN service
# (-X ...internal/signing.Key=...).
#Requires -Version 7
$ErrorActionPreference = 'Stop'

if (-not ($env:ARMAN_VPN_SIGNING_KEY -or $env:ARMAN_VPN_SIGNING_KEY_FILE)) {
    Write-Warning 'No signing key (ARMAN_VPN_SIGNING_KEY or ARMAN_VPN_SIGNING_KEY_FILE): this build takes no updates'
    return ''
}
Push-Location (Join-Path (Split-Path -Parent $PSScriptRoot) 'core')
try {
    $public = (go run ./tools/sign -public).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $public) { throw 'reading the signing key failed' }
    $public
} finally { Pop-Location }
