import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../app_settings.dart';
import 'android_core.dart';
import 'core_api.dart';
import 'core_controller.dart';
import 'models.dart';

/// The release's APKs, one per processor type (scripts/build-android.ps1,
/// .github/workflows/build.yml); others get the universal one.
const _apkAbis = {'arm64-v8a', 'armeabi-v7a', 'x86_64'};

/// Where the Download button goes: the release's file for this copy of the
/// app, which the browser downloads at once (no page to choose from): on a
/// phone the APK for its processor; on Windows the installer for an
/// installed copy (its uninstaller is beside it) and the zip for a portable
/// one; on macOS the disk image; on Linux the archive for the processor.
Future<String> downloadUrl(Release release) async {
  if (!release.url.contains('/releases/tag/')) return release.url;
  final String name;
  if (Platform.isAndroid) {
    final abi = await AndroidCore.abi().catchError((Object _) => '');
    name = apkName(abi);
  } else if (Platform.isWindows) {
    final dir = File(Platform.resolvedExecutable).parent.path;
    final installed = File('$dir${Platform.pathSeparator}unins000.exe');
    name = windowsName(installed: installed.existsSync());
  } else if (Platform.isMacOS) {
    name = 'macOS.dmg';
  } else if (Platform.isLinux) {
    name = linuxName(Platform.version);
  } else {
    return release.url;
  }
  return releaseFileUrl(release.url, name);
}

/// The APK's name part for processor [abi].
String apkName(String abi) =>
    'Android-${_apkAbis.contains(abi) ? abi : 'universal'}.apk';

/// The Windows file's name part: the installer, or the portable zip.
String windowsName({required bool installed}) =>
    installed ? 'Windows-Setup-x64.exe' : 'Windows-x64.zip';

/// The file `Firefox-VPN-<version>-[name]` in the release whose page is
/// [releaseUrl] (".../releases/tag/v1.2.3"): its versioned name, so the
/// downloaded file says which version it is.
String releaseFileUrl(String releaseUrl, String name) {
  final tag = releaseUrl.substring(releaseUrl.lastIndexOf('/') + 1);
  final version = tag.replaceFirst(RegExp('^[vV]'), '');
  return '${releaseUrl.replaceFirst('/releases/tag/', '/releases/download/')}'
      '/Firefox-VPN-$version-$name';
}

/// The APK for processor [abi] in the release whose page is [releaseUrl].
String apkUrl(String releaseUrl, String abi) =>
    releaseFileUrl(releaseUrl, apkName(abi));

/// The local proxy for GitHub requests, on networks that block GitHub: the
/// VPN's own while it runs without a proxy login; null otherwise.
String? updateProxy(CoreStatus? status) {
  final proxy = status?.proxy;
  if (status?.state.phase != Phase.running || proxy == null) return null;
  if (proxy.loginRequired) return null;
  return CoreLocator.listenUri(proxy.listen).authority;
}

/// Looks for a newer release on GitHub every 5 days: the app looks a minute
/// after it starts, and then every hour, whether 5 days have passed since
/// the last look that worked. What it finds is kept in the settings, so the
/// home page shows it after a restart too; the computer also shows a
/// notification while the window is in the tray. The About page looks at
/// once, whenever asked.
///
/// The desktop apps (Windows, Linux, macOS) install it themselves (their
/// core: core/internal/update): Update downloads it through the VPN while it
/// runs, and the app closes and opens again as the new version. With
/// automatic updates (on unless turned off), a version found downloads in
/// the background and installs the next time the app starts. When the core
/// cannot install it, and on Android, whose core does not update, the notice
/// opens the download.
abstract final class Updates {
  /// How long a successful look holds.
  static const every = Duration(days: 5);

  /// The newer release, once one was found.
  static final available = ValueNotifier<Release?>(null);

  /// The app installs a downloaded version at its start (automatic
  /// updates) and quits in a moment, so it does not connect first.
  static final installingAtStart = ValueNotifier<bool>(false);

  /// Why the app's last request to install failed, when the core could not
  /// say it in its status.
  static final failure = ValueNotifier<String?>(null);

  /// The notice of what the last update did was closed.
  static final resultSeen = ValueNotifier<bool>(false);

  /// Quits the app (the desktop's Quit), once an install has started.
  static Future<void> Function()? quitApp;

  /// Whether the window is in the tray: the new version starts there too.
  static bool Function() windowHidden = () => false;

  static Timer? _first;
  static Timer? _timer;
  static CoreController? _core;
  static AppSettings? _settings;

  /// The app's arguments that its next start keeps (core/internal/update
  /// AppArgs, and a copy's own --data-dir).
  static List<String> _startArgs = const [];

  /// The version the user asked to install: it installs once downloaded.
  static String? _wanted;

  /// Whether the first status since the start was looked at.
  static bool _started = false;

  /// The versions automatic updates asked to download in this run, so a
  /// failed one waits for the next start.
  static final _downloadsAsked = <String>{};

  /// Starts looking. [args] are the app's own (`--autostart`, `--hidden`,
  /// `--data-dir=`), which a new version installed at the start keeps; an
  /// install from the Update button keeps `--data-dir=`.
  static void start(
    CoreController core,
    AppSettings settings, {
    List<String> args = const [],
  }) {
    if (githubRepo.isEmpty || _timer != null) return;
    _core = core;
    _settings = settings;
    _startArgs = [
      for (final a in args)
        if (a == '--autostart' ||
            a == '--hidden' ||
            a.startsWith('--data-dir='))
          a,
    ];
    // A version found earlier, unless this app is already that one.
    if (newerVersion(settings.updateVersion, appVersion)) {
      available.value = Release(settings.updateVersion, settings.updateUrl);
    }
    core.addListener(_onStatus);
    _first = Timer(const Duration(minutes: 1), _due);
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _due());
  }

  /// Forgets everything, for the next test.
  @visibleForTesting
  static void reset() {
    _first?.cancel();
    _timer?.cancel();
    _core?.removeListener(_onStatus);
    _first = _timer = _core = _settings = _wanted = null;
    _started = false;
    _startArgs = const [];
    _downloadsAsked.clear();
    available.value = null;
    installingAtStart.value = false;
    failure.value = null;
    resultSeen.value = false;
    quitApp = null;
    windowHidden = () => false;
  }

  /// Follows the core's update: a version downloaded before installs at
  /// the start (automatic updates), the one the user asked for once it is
  /// downloaded, and a version found downloads by itself.
  static void _onStatus() {
    final core = _core, settings = _settings;
    final update = core?.status?.update;
    if (core == null || settings == null || update == null) return;
    if (!_started) {
      _started = true;
      // Not right after an update that failed (the old version started
      // again): the next start tries again, so a lasting failure is no loop.
      final justFailed = update.last != null && !update.last!.ok;
      if (update.ready &&
          !justFailed &&
          newerVersion(update.version, appVersion)) {
        installingAtStart.value = true;
        unawaited(
          _install(update.version, _startArgs).then((ok) {
            if (!ok) installingAtStart.value = false;
          }),
        );
        return;
      }
    }
    final wanted = _wanted;
    if (wanted != null && update.version == wanted) {
      if (update.ready) {
        _wanted = null;
        unawaited(_installReady(update));
        return;
      }
      if (update.failed) _wanted = null;
    }
    _downloadInBackground();
  }

  /// With automatic updates, downloads the version found (once per run).
  static void _downloadInBackground() {
    final core = _core, settings = _settings;
    final release = available.value;
    final update = core?.status?.update;
    if (core == null || settings == null || release == null || update == null) {
      return;
    }
    if (!newerVersion(release.version, appVersion)) {
      return;
    }
    if (update.downloading || update.installing) return;
    if (update.ready && update.version == release.version) return;
    if (!_downloadsAsked.add(release.version)) return;
    unawaited(
      core.downloadUpdate(release.version).catchError((Object _) {
        // The core's status says why.
      }),
    );
  }

  /// The Update button: downloads [release] when needed, then installs it;
  /// the app closes and opens again as the new version.
  static Future<void> update(Release release) async {
    final core = _core;
    if (core == null) return;
    failure.value = null;
    final current = core.status?.update;
    if (current != null &&
        current.ready &&
        current.version == release.version) {
      await _installReady(current);
      return;
    }
    _wanted = release.version;
    try {
      await core.downloadUpdate(release.version);
    } on Exception catch (e) {
      _wanted = null;
      failure.value = '$e';
    }
  }

  /// Installs the downloaded [update] by the core, the app closing and
  /// opening again.
  static Future<bool> _installReady(UpdateState update) =>
      _install(update.version, _restartArgs());

  /// The arguments of the next start after an install now: in the tray if
  /// the window is there, and with this copy's own data folder.
  static List<String> _restartArgs() => [
    if (windowHidden()) '--hidden',
    for (final a in _startArgs)
      if (a.startsWith('--data-dir=')) a,
  ];

  /// Asks the core to install [version], then quits the app; false when the
  /// core refused (the reason in [failure] or the core's status).
  static Future<bool> _install(String version, List<String> args) async {
    final core = _core;
    if (core == null) return false;
    try {
      await core.installUpdate(version, pid, args);
    } on Exception catch (e) {
      failure.value = '$e';
      return false;
    }
    await quitApp?.call();
    return true;
  }

  static Future<void> _due() async {
    final last = _settings?.updateCheckedAt;
    if (last != null && DateTime.now().difference(last) < every) return;
    try {
      found(await checkForUpdate(proxy: updateProxy(_core?.status)));
    } on Exception {
      // No network, or GitHub not reachable: the next hour tries again.
    }
  }

  /// The result of a look that worked, here or on the About page: a newer
  /// [release], or null when this version is the newest.
  static void found(Release? release) {
    available.value = release;
    _settings?.update(
      updateCheckedAt: DateTime.now(),
      updateVersion: release?.version ?? '',
      updateUrl: release?.url ?? '',
    );
    _downloadInBackground();
  }
}
