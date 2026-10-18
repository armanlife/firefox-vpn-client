# Builds the Android app with its core into dist\Firefox-VPN-<version>-android\:
# one APK per ABI (arm64-v8a, armeabi-v7a, x86_64). It first binds the Go
# core into app\android\app\libs\core.aar with gomobile, then builds the
# Flutter app. The version is "major.minor.patch" from app\pubspec.yaml, passed
# to the app (APP_VERSION) and to the core (version.Current).
#
# Needs Go, Flutter, the Android SDK with the NDK named in
# app\android\app\build.gradle.kts, a JDK (JAVA_HOME, else Android
# Studio's), and gomobile and gobind at the x/mobile commit given in
# core\doc\DEVELOPMENT.md.
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$match = Select-String -Path "$root\app\pubspec.yaml" -Pattern '^version:\s*(\d+\.\d+\.\d+)'
if (-not $match) { throw 'No version in app\pubspec.yaml' }
$version = $match.Matches[0].Groups[1].Value
$out = "$root\dist\Firefox-VPN-$version-android"

if (-not $env:ANDROID_HOME) { $env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk" }
$ndk = (Select-String -Path "$root\app\android\app\build.gradle.kts" -Pattern 'ndkVersion\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
if (-not $env:ANDROID_NDK_HOME) { $env:ANDROID_NDK_HOME = "$env:ANDROID_HOME\ndk\$ndk" }
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = "$env:ProgramFiles\Android\Android Studio\jbr" }
$env:PATH = "$(go env GOPATH)\bin;$env:JAVA_HOME\bin;$env:PATH"

Push-Location "$root\core"
try {
    gomobile bind -target=android -androidapi 24 -trimpath `
        -ldflags "-s -w -X github.com/armanlife/firefox-vpn-client/core/internal/version.Current=$version" `
        -o ..\app\android\app\libs\core.aar ./mobile
    if ($LASTEXITCODE -ne 0) { throw 'gomobile bind failed' }
} finally { Pop-Location }

Push-Location "$root\app"
try {
    # The packages from the local cache when it has them; from pub.dev
    # otherwise (a new machine). pub.dev refuses some requests from some
    # countries (its security advisories), which an offline get avoids.
    flutter pub get --offline
    if ($LASTEXITCODE -ne 0) { flutter pub get }
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed' }
    flutter build apk --release --no-pub --split-per-abi --dart-define=APP_VERSION=$version
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
} finally { Pop-Location }

New-Item -ItemType Directory -Force $out | Out-Null
foreach ($apk in Get-ChildItem "$root\app\build\app\outputs\flutter-apk\app-*-release.apk") {
    $name = $apk.Name -replace '^app-', "Firefox-VPN-$version-" -replace '-release', ''
    Copy-Item $apk.FullName (Join-Path $out $name) -Force
}
Get-ChildItem $out | ForEach-Object { Write-Host ("Built {0} ({1:N1} MB)" -f $_.FullName, ($_.Length / 1MB)) }
