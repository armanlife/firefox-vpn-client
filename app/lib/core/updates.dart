import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../app_settings.dart';
import 'core_api.dart';
import 'core_controller.dart';
import 'models.dart';

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
/// notification while the window is in the tray.
abstract final class Updates {
  /// How long a successful look holds.
  static const every = Duration(days: 5);

  /// The newer release, once one was found.
  static final available = ValueNotifier<Release?>(null);

  static Timer? _timer;
  static CoreController? _core;
  static AppSettings? _settings;

  static void start(CoreController core, AppSettings settings) {
    if (githubRepo.isEmpty || _timer != null) return;
    _core = core;
    _settings = settings;
    // A version found earlier, unless this app is already that one.
    if (newerVersion(settings.updateVersion, appVersion)) {
      available.value = Release(settings.updateVersion, settings.updateUrl);
    }
    Timer(const Duration(minutes: 1), _due);
    _timer = Timer.periodic(const Duration(hours: 1), (_) => _due());
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
  }
}
