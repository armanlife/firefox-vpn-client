import 'package:flutter/services.dart';

import 'android_core.dart' show VpnNotAllowed;
import 'core_api.dart';

/// The core on iOS: while the VPN is off, it runs in this app's process
/// with the proxy off, so the settings and the accounts work. Turned on,
/// the system's packet tunnel extension runs its own core, and the app
/// talks to it through the same HTTP API on loopback — both cores use the
/// same data folder in the App Group's container (AppDelegate.swift). The
/// VPN itself is the extension's: iOS has no proxy-only mode for other
/// apps, and no per-app routing to choose.
class IosCore {
  static const _channel = MethodChannel('app/ios');

  /// The core's data folder in the app group's container.
  static Future<String> dataDir() async =>
      await _channel.invokeMethod<String>('dataDir') ?? '';

  IosCore(this._dataDir);

  final String _dataDir;

  /// Opens a client of the core, starting the core (off) when it does not
  /// run; it throws [CoreUnavailable] until the core answers. With the VPN
  /// on, the extension owns the core: isRunning says so, and the API is
  /// found in the same data folder.
  Future<CoreApi> connect() async {
    if (await _channel.invokeMethod<bool>('isRunning') != true) {
      await _channel.invokeMethod<void>('startCore');
      throw const CoreUnavailable(CoreProblem.starting);
    }
    try {
      final api = CoreApi(await CoreLocator.locate(_dataDir));
      try {
        await api.status();
        return api;
      } on Exception {
        api.close();
        rethrow;
      }
    } on CoreUnavailable {
      // The core's API is still coming up.
      throw const CoreUnavailable(CoreProblem.starting);
    }
  }

  /// Turns the VPN on or off (the system asks the first time). It throws
  /// [VpnNotAllowed] when the user refuses.
  static Future<void> setOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('setOn', {'on': on});
    } on PlatformException catch (e) {
      if (e.code == 'vpn_denied') throw const VpnNotAllowed();
      throw CoreApiException(0, e.message ?? e.code);
    }
  }

  /// Opens [url] in the app that handles it (a browser, a tg:// link).
  static Future<bool> openUrl(String url) async =>
      await _channel.invokeMethod<bool>('openUrl', {'url': url}) ?? false;
}
