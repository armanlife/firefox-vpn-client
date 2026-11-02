import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/core_controller.dart';
import '../core/models.dart';
import '../core/tun_service.dart';
import '../l10n/app_localizations.dart';
import 'widgets.dart';

// The computer's connection mode (system_proxy.mode): proxy only, the
// system proxy, or TUN. TUN needs its service, which the app installs when
// the mode is first chosen (the system asks for administrator permission
// once); everything else is the core's.

/// Switches to [mode], installing the TUN service first when TUN is chosen
/// and the service is not installed. A declined prompt or a failed install
/// leaves the mode as it was, and says so.
Future<void> chooseConnectionMode(
  BuildContext context,
  CoreController core,
  String mode,
) async {
  if (mode == 'tun' && !(core.status?.tun?.installed ?? false)) {
    if (!await installTunService(context, core)) return;
    if (!context.mounted) return;
  }
  await runShowingErrors(context, () => core.setSystemProxy(mode));
}

/// The connection mode shown as chosen: "clear" (Proxy), "set" (System
/// proxy), or "tun"; one this computer does not have shows as Proxy.
String connectionModeShown(CoreStatus status) => switch (status.systemProxy) {
  'set' when status.systemProxySupported => 'set',
  'tun' when status.tunSupported => 'tun',
  _ => 'clear',
};

/// Installs the TUN service, with the system's administrator prompt;
/// false, after telling the user, when it was declined or failed.
Future<bool> installTunService(
  BuildContext context,
  CoreController core,
) async {
  final l = AppLocalizations.of(context);
  final result = await core.installTunService(prompt: l.tunInstallPrompt);
  if (!context.mounted) return result is TunServiceDone;
  switch (result) {
    case TunServiceDone():
      return true;
    case TunServiceCancelled():
      showError(context, l.tunInstallCancelled);
    case TunServiceFailed(:final error):
      showError(context, l.tunInstallFailed(error));
  }
  return false;
}

/// The hint under the mode choice: what the mode does, or that Windows'
/// prompt is waiting.
String connectionModeHint(
  AppLocalizations l,
  CoreStatus status, {
  required bool installing,
  required bool windows,
}) {
  if (installing) return l.tunInstallWaiting;
  if (status.tunMode) {
    return l.modeTunHint(switch (defaultTargetPlatform) {
      TargetPlatform.macOS => l.osMacos,
      TargetPlatform.linux => l.osLinux,
      _ => l.osWindows,
    });
  }
  return switch ((status.systemProxySet, windows)) {
    (true, true) => l.modeSystemProxyHint,
    (true, false) => l.modeSystemProxyHintOther,
    (false, _) => l.modeProxyHint,
  };
}

/// What the home page says while TUN mode is chosen but not on, and the
/// install button where installing helps; null when there is nothing to
/// say (TUN on, off, or another mode).
({String text, String detail, bool problem, bool install, bool again})? tunNote(
  AppLocalizations l,
  CoreStatus status,
) {
  final tun = status.tun;
  if (!status.tunMode || tun == null || status.state.phase == Phase.off) {
    return null;
  }
  if (tun.starting) {
    return (
      text: l.tunStarting,
      detail: '',
      problem: false,
      install: false,
      again: false,
    );
  }
  if (!tun.failed) return null;
  final (text, install, again) = switch (tun.code) {
    TunCode.missing => (l.tunMissing, true, false),
    TunCode.notRunning => (l.tunNotRunning, true, true),
    TunCode.outdated => (l.tunOutdated, true, true),
    TunCode.appOutdated => (l.tunAppOutdated, false, false),
    TunCode.busy => (l.tunBusy, false, false),
    TunCode.noDriver => (l.tunNoDriver, false, false),
    TunCode.lost => (l.tunLost, false, false),
    _ => (l.tunFailed, false, false),
  };
  return (
    text: text,
    detail: tun.message,
    problem: true,
    install: install,
    again: again,
  );
}

/// The TUN mode's note on the home page: a line while it starts, an amber
/// box (the core's reason on hover) when it does not run, with Install or
/// Install again where that helps.
class TunNote extends StatelessWidget {
  const TunNote({super.key, required this.core, required this.box});

  final CoreController core;

  /// Builds the amber box (the home page's own).
  final Widget Function(String text, String tooltip) box;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final status = core.status;
    final note = status == null ? null : tunNote(l, status);
    if (note == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    if (!note.problem) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          note.text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: StatusColors.busy,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    final busy = core.installingTun || core.removingTun;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          box(note.text, note.detail),
          if (note.install) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: busy ? null : () => installTunService(context, core),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(note.again ? l.tunInstallAgain : l.tunInstall),
            ),
          ],
        ],
      ),
    );
  }
}
