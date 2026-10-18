import 'dart:io';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_settings.dart';
import '../core/android_core.dart';
import '../core/core_controller.dart';
import '../core/updates.dart';
import '../core/models.dart';
import '../core/ports.dart';
import '../l10n/app_localizations.dart';
import '../platform.dart';
import 'format.dart';
import 'port_dialog.dart';
import 'signin_dialog.dart';
import 'widgets.dart';

/// The home page: the switch, the state, where the traffic goes, and the
/// data used; the phone's (_PhoneHome) and the computer's (_DesktopHome)
/// share the look, not the logic. Developer mode adds the details.
class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.core,
    required this.settings,
    this.onOpenServers,
    this.onOpenAccounts,
    this.phone = false,
  });

  final CoreController core;
  final AppSettings settings;

  /// The phone layout: a colored hero and the data left (_PhoneHome).
  final bool phone;

  /// Opens the server list and the accounts from the home page's cards (a
  /// page on the phone, a tab on the computer).
  final VoidCallback? onOpenServers;
  final VoidCallback? onOpenAccounts;

  @override
  Widget build(BuildContext context) {
    final status = core.status!;
    final showIp = settings.showPublicIp;
    if (phone) {
      return _PhoneHome(
        core: core,
        status: status,
        showIp: showIp,
        settings: settings,
        onOpenServers: onOpenServers,
        onOpenAccounts: onOpenAccounts,
      );
    }
    return _DesktopHome(
      core: core,
      status: status,
      showIp: showIp,
      settings: settings,
      onOpenServers: onOpenServers,
      onOpenAccounts: onOpenAccounts,
    );
  }
}

/// The phone home's colors, light or dark with the app's theme.
/// The computer's home: the phone's look with the computer's logic. The
/// button turns the proxy on or off (off closes its port and gives Windows
/// its own proxy setting back); the mode chooses who uses it: Proxy, apps
/// set up by hand, or System proxy, Windows too. Switching modes never
/// disconnects. "Connecting" in orange until a test confirms the
/// connection. Where the traffic goes and the data used are in cards; the
/// email is on the accounts page.
class _DesktopHome extends StatelessWidget {
  const _DesktopHome({
    required this.core,
    required this.status,
    required this.showIp,
    required this.settings,
    this.onOpenServers,
    this.onOpenAccounts,
  });

  final CoreController core;
  final CoreStatus status;

  /// Settings, Show the public IP.
  final bool showIp;
  final AppSettings settings;
  final VoidCallback? onOpenServers;
  final VoidCallback? onOpenAccounts;

  /// Changes the mode ("set": System proxy, "clear": Proxy); the proxy
  /// keeps running and stays connected.
  Future<void> _setMode(String mode) => core.setSystemProxy(mode);

  /// The button: off, or on with a test that confirms the connection.
  Future<void> _power(bool on) async {
    await core.setOn(on);
    if (on) unawaited(core.runTest().catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final p = base.brightness == Brightness.dark
        ? _HomePalette.night
        : _HomePalette.day;
    final page = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [p.top, p.bottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -120,
            child: _Glow(
              color: _accent(p),
              size: 420,
              alpha: p.dark ? 0.20 : 0.18,
            ),
          ),
          Positioned(
            top: 120,
            right: -160,
            child: _Glow(
              color: p.second,
              size: 360,
              alpha: p.dark ? 0.12 : 0.15,
            ),
          ),
          Positioned(
            bottom: -120,
            left: 40,
            child: _Glow(
              color: p.third,
              size: 320,
              alpha: p.dark ? 0.10 : 0.10,
            ),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _content(context, p),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return p.dark ? Theme(data: midnightTheme(base), child: page) : page;
  }

  bool get _running => status.state.phase == Phase.running;

  /// The proxy runs but no test since it started passed.
  bool get _confirming => _running && !status.confirmedBy(core.lastTest);

  Color _accent(_HomePalette p) => switch (status.state.phase) {
    Phase.error => p.error,
    Phase.running when _confirming => p.busy,
    Phase.running => p.connected,
    Phase.starting => p.busy,
    _ => p.idle,
  };

  Widget _content(BuildContext context, _HomePalette p) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final look = PhaseLook.of(l, status);
    final proxy = status.proxy;
    final on = status.state.phase != Phase.off;
    final confirming = _confirming;
    final failing =
        confirming &&
        ((proxy?.wakeError.isNotEmpty ?? false) || core.lastTest?.ok == false);
    final connected = _running && !confirming;
    final systemProxy = status.systemProxySet;
    final accent = _accent(p);
    final ip = !showIp
        ? ''
        : status.exit?.ipv4.isNotEmpty == true
        ? status.exit!.ipv4
        : status.exit?.ipv6 ?? '';
    final place = homeLocation(l, status, connected: connected);
    final cards = [
      _PlaceCard(
        palette: p,
        compact: true,
        place: place,
        accent: accent,
        onTap: onOpenServers,
      ),
      _HomeData(
        status: status,
        palette: p,
        onTap: onOpenAccounts,
        compact: true,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: _PowerOrb(
            palette: p,
            on: on,
            accent: accent,
            busy: core.switchingProxy,
            tooltip: on ? l.tapToDisconnect : l.tapToConnect,
            onPressed: () => status.totalAccounts == 0
                ? showSignInDialog(context, core)
                : runShowingErrors(context, () => _power(!on)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          confirming
              ? l.stateConnecting
              : connected
              ? l.stateConnected
              : look.label,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: on ? accent : p.text,
          ),
        ),
        const SizedBox(height: 8),
        if (connected)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _HomeDelay(core: core, palette: p),
              if (ip.isNotEmpty)
                _HomePill(
                  palette: p,
                  child: Text(
                    '${l.publicIp} ${ltr(ip)}',
                    style: theme.textTheme.labelLarge?.copyWith(color: p.muted),
                  ),
                ),
            ],
          )
        else
          Text(
            status.noNetwork && on
                ? l.noNetwork
                : failing
                ? l.connectRetrying
                : !on
                ? l.tapToConnect
                : look.hint,
            textAlign: TextAlign.center,
            // Not connecting stands out from the ordinary hints.
            style: theme.textTheme.bodyMedium?.copyWith(
              color: failing || (status.noNetwork && on) ? p.error : p.muted,
              fontWeight: failing || (status.noNetwork && on)
                  ? FontWeight.w600
                  : null,
            ),
          ),
        if (status.state.proxyPortInUse) ...[
          const SizedBox(height: 12),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: () async {
                final port = await showPortDialog(
                  context,
                  taken: status.state.address,
                );
                if (port != null && context.mounted) {
                  await runShowingErrors(
                    context,
                    () => core.setProxyPort(port),
                  );
                }
              },
              icon: const Icon(Icons.settings_ethernet_rounded),
              label: Text(l.changePort),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            // The same choice as the button and the tray, by name.
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: p.card,
                selectedBackgroundColor: accent.withValues(alpha: 0.18),
                selectedForegroundColor: p.text,
                foregroundColor: p.text,
                side: BorderSide(color: p.cardBorder),
              ),
              segments: [
                ButtonSegment(
                  value: 'clear',
                  icon: const Icon(Icons.settings_ethernet_rounded, size: 18),
                  label: Text(l.modeProxy),
                  // Where apps set up by hand find the proxy, which always
                  // runs.
                  tooltip: _running && proxy != null
                      ? '${l.proxyServiceActive} · ${proxy.listen}'
                      : null,
                ),
                ButtonSegment(
                  value: 'set',
                  icon: const Icon(Icons.computer_rounded, size: 18),
                  label: Text(l.systemProxy),
                ),
              ],
              selected: {systemProxy ? 'set' : 'clear'},
              onSelectionChanged: core.switchingProxy
                  ? null
                  : (v) => runShowingErrors(context, () => _setMode(v.first)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          systemProxy ? l.modeSystemProxyHint : l.modeProxyHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
        ),
        const SizedBox(height: 24),
        _UpdateNotice(settings: settings, palette: p),
        _Notices(notices: homeNotices(status.notices)),
        _LowQuotaNotice(
          core: core,
          status: status,
          settings: settings,
          connected: connected,
          palette: p,
        ),
        // Side by side when there is room.
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 560
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [cards[0], const SizedBox(height: 12), cards[1]],
                ),
        ),
      ],
    );
  }
}

/// A small frosted pill on the home background.
class _HomePill extends StatelessWidget {
  const _HomePill({required this.palette, required this.child});

  final _HomePalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: ShapeDecoration(
      color: palette.card,
      shape: StadiumBorder(side: BorderSide(color: palette.cardBorder)),
    ),
    child: child,
  );
}

/// Where the traffic goes: the flag and the country, under how the
/// location is chosen (a sparkle for the app's choice); a tap opens the
/// server list.
class _PlaceCard extends StatelessWidget {
  const _PlaceCard({
    required this.palette,
    required this.place,
    required this.accent,
    this.onTap,
    this.compact = false,
  });

  final _HomePalette palette;
  final HomePlace place;
  final Color accent;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = palette;
    return _HomeCard(
      palette: p,
      onTap: onTap,
      compact: compact,
      // As tall as the data card's ring, so the two cards match.
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _homeCardContent(compact)),
        child: Row(
          children: [
            CountryFlag(code: place.flag, width: compact ? 34 : 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (place.auto) ...[
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 14,
                          color: accent,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          place.caption,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: place.auto ? accent : p.muted,
                            fontWeight: place.auto ? FontWeight.w600 : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    place.name,
                    style:
                        (compact
                                ? theme.textTheme.titleSmall
                                : theme.textTheme.titleMedium)
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: p.text,
                            ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: p.muted),
          ],
        ),
      ),
    );
  }
}

class _HomePalette {
  const _HomePalette({
    required this.dark,
    required this.top,
    required this.bottom,
    required this.text,
    required this.muted,
    required this.card,
    required this.cardBorder,
    required this.idle,
    required this.connected,
    required this.busy,
    required this.error,
    required this.second,
    required this.third,
    required this.discOff,
    required this.discOffEdge,
  });

  final bool dark;
  final Color top;
  final Color bottom;
  final Color text;
  final Color muted;
  final Color card;
  final Color cardBorder;
  final Color idle;
  final Color connected;
  final Color busy;
  final Color error;

  /// Colors of the background's soft lights, with the state's.
  final Color second;
  final Color third;
  final List<Color> discOff;
  final Color discOffEdge;

  static const night = _HomePalette(
    dark: true,
    top: Midnight.top,
    bottom: Midnight.bottom,
    text: Colors.white,
    muted: Midnight.muted,
    card: Color(0x10FFFFFF),
    cardBorder: Color(0x14FFFFFF),
    idle: Midnight.idle,
    connected: Midnight.connected,
    busy: Midnight.busy,
    error: Midnight.error,
    second: Color(0xFF2EA8FF),
    third: Color(0xFFB45CFF),
    discOff: [Color(0xFF262E5A), Color(0xFF161C3C)],
    discOffEdge: Color(0x1FFFFFFF),
  );

  static const day = _HomePalette(
    dark: false,
    top: Color(0xFFE9EEFF),
    bottom: Color(0xFFF9FAFF),
    text: Color(0xFF151A35),
    muted: Color(0xFF646C92),
    card: Color(0xD9FFFFFF),
    cardBorder: Color(0x12202A66),
    idle: Color(0xFF6A5CF0),
    connected: Color(0xFF0DB37C),
    busy: Color(0xFFF08C00),
    error: Color(0xFFE5484D),
    second: Color(0xFF38B6FF),
    third: Color(0xFFFF7EB6),
    discOff: [Colors.white, Color(0xFFF0F2FF)],
    discOffEdge: Color(0x336A5CF0),
  );
}

/// The phone's home: the switch in the middle over soft lights and wavy
/// contour lines in the state's color, the state under it, then where the
/// traffic goes and the data used. Light or dark with the app's theme; the
/// email is on the accounts page.
class _PhoneHome extends StatelessWidget {
  const _PhoneHome({
    required this.core,
    required this.status,
    required this.showIp,
    required this.settings,
    this.onOpenServers,
    this.onOpenAccounts,
  });

  final CoreController core;
  final CoreStatus status;

  /// Settings, Show the public IP.
  final bool showIp;
  final AppSettings settings;
  final VoidCallback? onOpenServers;
  final VoidCallback? onOpenAccounts;

  Future<void> _toggle(bool on) async {
    if (status.systemProxySupported) {
      await core.setSystemProxy(on ? 'clear' : 'set');
    } else {
      await core.setOn(!on);
    }
    if (!on) unawaited(core.runTest().catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final p = base.brightness == Brightness.dark
        ? _HomePalette.night
        : _HomePalette.day;
    final page = AnnotatedRegion<SystemUiOverlayStyle>(
      value: (p.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [p.top, p.bottom],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(child: _content(context, p)),
            ),
          ),
        ),
      ),
    );
    return p.dark ? Theme(data: midnightTheme(base), child: page) : page;
  }

  Widget _content(BuildContext context, _HomePalette p) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final look = PhaseLook.of(l, status);
    final running = status.state.phase == Phase.running;
    final canSwitch = status.systemProxySupported;
    final on = canSwitch
        ? status.systemProxySet
        : status.state.phase != Phase.off;
    final proxy = status.proxy;
    // The phone's VPN is "Connecting", in orange, until a test confirms it
    // works (the controller tests again meanwhile): with no internet it
    // does not claim to be connected.
    final confirming =
        on && running && !canSwitch && !status.confirmedBy(core.lastTest);
    final failing =
        confirming &&
        ((proxy?.wakeError.isNotEmpty ?? false) || core.lastTest?.ok == false);
    final connected =
        running && (status.systemProxySet || !canSwitch) && !confirming;
    final ip = !showIp
        ? ''
        : status.exit?.ipv4.isNotEmpty == true
        ? status.exit!.ipv4
        : status.exit?.ipv6 ?? '';
    final proxyOnly = Platform.isAndroid && AndroidCore.mode.value == 'proxy';
    final accent = !on
        ? p.idle
        : confirming
        ? p.busy
        : switch (status.state.phase) {
            Phase.running => p.connected,
            Phase.error => p.error,
            _ => p.busy,
          };
    final label = confirming ? l.stateConnecting : look.label;
    final place = homeLocation(l, status, connected: connected);
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        // Soft lights in the state's color and two others.
        Positioned(
          top: -120,
          left: -100,
          child: _Glow(color: accent, size: 360, alpha: p.dark ? 0.22 : 0.20),
        ),
        Positioned(
          top: 160,
          right: -140,
          child: _Glow(color: p.second, size: 320, alpha: p.dark ? 0.12 : 0.16),
        ),
        Positioned(
          bottom: -80,
          left: -60,
          child: _Glow(color: p.third, size: 300, alpha: p.dark ? 0.10 : 0.12),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, top + 14, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_rounded, color: accent, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    l.appTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: p.text,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              const SizedBox(height: 16),
              Center(
                child: _PowerOrb(
                  palette: p,
                  on: on,
                  accent: accent,
                  busy: core.switchingProxy,
                  tooltip: on ? l.tapToDisconnectPhone : l.tapToConnectPhone,
                  // No account yet: connecting starts with adding one.
                  onPressed: () => status.totalAccounts == 0
                      ? showSignInDialog(context, core)
                      : runShowingErrors(context, () => _toggle(on)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: on ? accent : p.text,
                ),
              ),
              const SizedBox(height: 8),
              if (connected)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HomeDelay(core: core, palette: p),
                    if (ip.isNotEmpty)
                      _HomePill(
                        palette: p,
                        child: Text(
                          '${l.publicIp} ${ltr(ip)}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: p.muted,
                          ),
                        ),
                      ),
                    if (proxyOnly && proxy != null)
                      _HomePill(
                        palette: p,
                        child: Text(
                          '${l.modeProxyOnly} ${ltr('127.0.0.1:${portOf(proxy.listen) ?? 10810}')}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: p.muted,
                          ),
                        ),
                      ),
                  ],
                )
              else
                Text(
                  status.noNetwork && on
                      ? l.noNetwork
                      : failing
                      ? l.connectRetrying
                      : look.hint.isNotEmpty
                      ? look.hint
                      : on
                      ? l.tapToDisconnectPhone
                      : l.tapToConnectPhone,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: failing || (status.noNetwork && on)
                        ? p.error
                        : p.muted,
                    fontWeight: failing || (status.noNetwork && on)
                        ? FontWeight.w600
                        : null,
                  ),
                ),
              if (status.state.proxyPortInUse) ...[
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.tonalIcon(
                    onPressed: () async {
                      final port = await showPortDialog(
                        context,
                        taken: status.state.address,
                      );
                      if (port != null && context.mounted) {
                        await runShowingErrors(
                          context,
                          () => core.setProxyPort(port),
                        );
                      }
                    },
                    icon: const Icon(Icons.settings_ethernet_rounded),
                    label: Text(l.changePort),
                  ),
                ),
              ],
              if (running &&
                  proxy != null &&
                  !canSwitch &&
                  sharedWithLan(proxy.listen)) ...[
                const SizedBox(height: 10),
                Center(child: _LanChip(port: portOf(proxy.listen) ?? 10810)),
              ],
              const Spacer(),
              const SizedBox(height: 20),
              _UpdateNotice(settings: settings, palette: p),
              _Notices(notices: homeNotices(status.notices)),
              _LowQuotaNotice(
                core: core,
                status: status,
                settings: settings,
                connected: connected,
                palette: p,
              ),
              _PlaceCard(
                palette: p,
                place: place,
                accent: accent,
                onTap: onOpenServers,
              ),
              const SizedBox(height: 12),
              _HomeData(status: status, palette: p, onTap: onOpenAccounts),
            ],
          ),
        ),
      ],
    );
  }
}

/// A soft round light for the background.
class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size, required this.alpha});

  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    ),
  );
}

/// A frosted card on the home background.
/// The height of the home cards' content: the data card's ring; smaller
/// on the computer, whose controls above the cards are small.
double _homeCardContent(bool compact) => compact ? 46 : 62;

class _HomeCard extends StatelessWidget {
  const _HomeCard({
    required this.palette,
    required this.child,
    this.onTap,
    this.compact = false,
  });

  final _HomePalette palette;
  final Widget child;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      boxShadow: palette.dark
          ? null
          : [
              BoxShadow(
                color: const Color(0xFF2A3375).withValues(alpha: 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
    ),
    child: Material(
      color: palette.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: palette.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: compact
              ? const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10)
              : const EdgeInsetsDirectional.fromSTEB(16, 14, 10, 14),
          child: child,
        ),
      ),
    ),
  );
}

/// The real delay under the state; a tap tests again.
class _HomeDelay extends StatelessWidget {
  const _HomeDelay({required this.core, required this.palette});

  final CoreController core;
  final _HomePalette palette;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final test = core.lastTest;
    final (text, color) = switch (test) {
      null => (l.testConnection, palette.muted),
      final t when !t.ok => (l.testFailed, palette.error),
      final t => (l.milliseconds(t.responseMs), delayColor(t.responseMs)),
    };
    return Tooltip(
      message: '${l.realDelay} · ${l.testConnection}',
      child: Material(
        color: palette.card,
        shape: StadiumBorder(side: BorderSide(color: palette.cardBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: core.testing
              ? null
              : () => runShowingErrors(context, core.runTest),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (core.testing)
                  const SizedBox.square(
                    dimension: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else
                  Icon(Icons.bolt_rounded, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  text,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The switch: an orb in the state's color with a glow and a thin ring,
/// over wavy contour lines that drift while connected.
class _PowerOrb extends StatefulWidget {
  const _PowerOrb({
    required this.palette,
    required this.on,
    required this.accent,
    required this.busy,
    required this.tooltip,
    required this.onPressed,
  });

  final _HomePalette palette;
  final bool on;
  final Color accent;
  final bool busy;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  State<_PowerOrb> createState() => _PowerOrbState();
}

class _PowerOrbState extends State<_PowerOrb> with TickerProviderStateMixin {
  late final _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  );
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(_PowerOrb old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final move = widget.on && !_still;
    if (move && !_breath.isAnimating) {
      _breath.repeat(reverse: true);
      _drift.repeat();
    } else if (!move && _breath.isAnimating) {
      _breath.stop();
      _drift.stop();
      _breath.value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final on = widget.on;
    final accent = widget.accent;
    const area = 250.0;
    const ring = 186.0;
    const disc = 148.0;
    return Tooltip(
      message: widget.tooltip,
      child: SizedBox.square(
        dimension: area,
        child: AnimatedBuilder(
          animation: Listenable.merge([_breath, _drift]),
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_breath.value);
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // Contour lines reaching past the button's area.
                Positioned(
                  left: -70,
                  top: -70,
                  right: -70,
                  bottom: -70,
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _Contours(
                        color: accent,
                        alpha: p.dark ? 0.16 : 0.22,
                        phase: _drift.value * 2 * math.pi,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: area,
                  height: area,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withValues(alpha: on ? 0.30 + 0.10 * t : 0.10),
                        accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: ring + 6 * t,
                  height: ring + 6 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: on ? 0.55 : 0.28),
                      width: 1.5,
                    ),
                  ),
                ),
                if (widget.busy)
                  SizedBox.square(
                    dimension: ring,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  ),
                child!,
              ],
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: disc,
            height: disc,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: on
                    ? [Color.lerp(accent, Colors.white, 0.28)!, accent]
                    : p.discOff,
              ),
              border: Border.all(
                color: on ? Colors.white.withValues(alpha: 0.4) : p.discOffEdge,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: on
                      ? accent.withValues(alpha: 0.5)
                      : (p.dark ? Colors.black : const Color(0xFF2A3375))
                            .withValues(alpha: p.dark ? 0.45 : 0.14),
                  blurRadius: on ? 36 : 26,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: widget.busy ? null : widget.onPressed,
                child: Icon(
                  Icons.power_settings_new_rounded,
                  size: 58,
                  color: on ? Colors.white : (p.dark ? p.muted : p.idle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wavy closed lines around the center, like the contours of a map; they
/// fade outwards and drift with [phase].
class _Contours extends CustomPainter {
  _Contours({required this.color, required this.alpha, required this.phase});

  final Color color;
  final double alpha;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    const lines = 7;
    for (var i = 0; i < lines; i++) {
      final base = 112.0 + i * 22;
      final amp = 3.0 + i * 1.6;
      final path = Path();
      for (var k = 0; k <= 120; k++) {
        final a = k / 120 * 2 * math.pi;
        final r =
            base +
            amp * math.sin(3 * a + i * 0.8 + phase) +
            amp * 0.5 * math.sin(5 * a - i * 0.5 - phase * 0.6);
        final point = center + Offset(math.cos(a) * r, math.sin(a) * r);
        k == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      path.close();
      paint.color = color.withValues(alpha: alpha * (1 - i / lines));
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Contours old) =>
      old.color != color || old.alpha != alpha || old.phase != phase;
}

/// The data used of the active account: a ring that fills as it is used,
/// in the quota's color, and the amount in large type.
class _HomeData extends StatelessWidget {
  const _HomeData({
    required this.status,
    required this.palette,
    this.onTap,
    this.compact = false,
  });

  final CoreStatus status;
  final _HomePalette palette;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = palette;
    final muted = theme.textTheme.bodySmall?.copyWith(color: p.muted);
    final a = status.activeAccount;
    final usage = a?.usage;
    Widget body;
    if (a == null || usage == null || usage.unlimited) {
      body = Row(
        children: [
          Icon(
            a == null
                ? Icons.person_add_alt_rounded
                : Icons.all_inclusive_rounded,
            color: p.muted,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              a == null
                  ? l.noActiveAccount
                  : usage == null
                  ? l.quotaNotRead
                  : l.unlimited,
              style: theme.textTheme.titleMedium?.copyWith(color: p.text),
            ),
          ),
        ],
      );
    } else {
      final used = usage.usedBytes.clamp(0, usage.limitBytes);
      final fraction = usage.limitBytes == 0 ? 0.0 : used / usage.limitBytes;
      final color = quotaColor(usage.limitBytes - used);
      body = Row(
        children: [
          SizedBox.square(
            dimension: _homeCardContent(compact),
            child: CustomPaint(
              painter: _QuotaRing(
                value: fraction,
                color: color,
                track: p.text.withValues(alpha: 0.08),
              ),
              child: Center(
                child: Text(
                  ltr('${(fraction * 100).round()}%'),
                  style:
                      (compact
                              ? theme.textTheme.labelMedium
                              : theme.textTheme.titleSmall)
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: p.text,
                          ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.dataUsedTitle, style: muted),
                Text(
                  formatBytes(used),
                  style:
                      (compact
                              ? theme.textTheme.titleLarge
                              : theme.textTheme.headlineSmall)
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: p.text,
                          ),
                ),
                Text(
                  [
                    l.dataLeftOf(formatBytes(usage.limitBytes)),
                    if (usage.resetAt != null)
                      l.resets(formatDate(l, usage.resetAt!)),
                  ].join(' · '),
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return _HomeCard(
      palette: p,
      onTap: onTap,
      compact: compact,
      child: Row(
        children: [
          Expanded(child: body),
          Icon(Icons.chevron_right_rounded, color: p.muted),
        ],
      ),
    );
  }
}

class _QuotaRing extends CustomPainter {
  _QuotaRing({required this.value, required this.color, required this.track});

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value.clamp(0.0, 1.0),
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_QuotaRing old) =>
      old.value != value || old.color != color || old.track != track;
}

/// The proxy's address on the local network, for other devices; a tap
/// copies it.
class _LanChip extends StatefulWidget {
  const _LanChip({required this.port});

  final int port;

  @override
  State<_LanChip> createState() => _LanChipState();
}

class _LanChipState extends State<_LanChip> {
  String? _ip;

  @override
  void initState() {
    super.initState();
    lanAddress().then((ip) {
      if (mounted) setState(() => _ip = ip);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ip = _ip;
    if (ip == null) return const SizedBox.shrink();
    final address = '$ip:${widget.port}';
    return ActionChip(
      avatar: const Icon(Icons.lan_outlined, size: 18),
      label: Text(l.lanAddress(ltr(address))),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: address));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l.copied(address)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}

/// Refusals dismissed in this session, by [Notice.key]; a newer refusal of
/// the same kind shows again.
final _dismissedNotices = <String>{};

/// Notes on requests the proxy refused in the last minutes: a port
/// Mozilla's proxy does not connect to, or UDP.
class _Notices extends StatefulWidget {
  const _Notices({required this.notices});

  final List<Notice> notices;

  @override
  State<_Notices> createState() => _NoticesState();
}

class _NoticesState extends State<_Notices> {
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final shown = [
      for (final n in widget.notices)
        if (!_dismissedNotices.contains(n.key) &&
            (n.kind == 'port' || n.kind == 'command'))
          n,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final n in shown)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: StatusColors.busy.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: StatusColors.busy.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.info_outline_rounded,
                      color: StatusColors.busy,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          n.kind == 'port'
                              ? l.noticePort(n.detail)
                              : l.noticeCommand,
                          style: theme.textTheme.bodySmall,
                        ),
                        if (n.last != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            [
                              l.noticeTimes(n.count, formatAgo(l, n.last!)),
                              if (n.hosts.isNotEmpty) n.hosts.join(', '),
                            ].join(' · '),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: l.dismiss,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () =>
                        setState(() => _dismissedNotices.add(n.key)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A newer version on GitHub: its number and a button to its page; closed,
/// it stays away until a later version.
class _UpdateNotice extends StatelessWidget {
  const _UpdateNotice({required this.settings, required this.palette});

  final AppSettings settings;
  final _HomePalette palette;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: Updates.available,
    builder: (context, release, _) {
      if (release == null || release.version == settings.dismissedUpdate) {
        return const SizedBox.shrink();
      }
      final l = AppLocalizations.of(context);
      final theme = Theme.of(context);
      final p = palette;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: p.connected.withValues(alpha: p.dark ? 0.16 : 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: p.connected.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
            child: Row(
              children: [
                Icon(Icons.system_update_rounded, color: p.connected),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.updateAvailable(release.version),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: p.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (release.url.isNotEmpty)
                  TextButton(
                    onPressed: () => openUrl(release.url),
                    child: Text(l.download),
                  ),
                IconButton(
                  tooltip: l.dismiss,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
                  onPressed: () =>
                      settings.update(dismissedUpdate: release.version),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// When the user connects and the active account is nearly used up with
/// no other account to take over: adding an account gives another month's
/// data. Shown once per connection, for a minute; closed, it stays away for
/// a day.
class _LowQuotaNotice extends StatefulWidget {
  const _LowQuotaNotice({
    required this.core,
    required this.status,
    required this.settings,
    required this.connected,
    required this.palette,
  });

  final CoreController core;
  final CoreStatus status;
  final AppSettings settings;
  final bool connected;
  final _HomePalette palette;

  @override
  State<_LowQuotaNotice> createState() => _LowQuotaNoticeState();
}

class _LowQuotaNoticeState extends State<_LowQuotaNotice> {
  /// Below this much left, the account is running out.
  static const _left = 5 << 30;
  static const _showFor = Duration(seconds: 60);
  static const _quiet = Duration(hours: 24);

  /// The connection it was shown for (the proxy's start), and whether its
  /// minute is over: once per connection, also when the home page is
  /// built again meanwhile.
  static DateTime? _shownFor;
  static bool _started = false;
  static bool _over = false;
  static Timer? _minute;
  static final _changed = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _changed.addListener(_rebuild);
  }

  @override
  void dispose() {
    _changed.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _due {
    final active = widget.status.activeAccount;
    final usage = active?.usage;
    if (!widget.connected || active == null || usage == null) return false;
    if (usage.unlimited || usage.limitBytes == 0) return false;
    if (usage.remainingBytes >= _left) return false;
    // Another account that can take over: the app moves to it by itself.
    final others = widget.core.accounts?.accounts ?? const <Account>[];
    final spare = others.any(
      (a) =>
          a.id != active.id &&
          a.enabled &&
          a.status == AccountStatus.ready &&
          (a.usage?.unlimited == true ||
              (a.usage?.remainingBytes ?? 0) >= _left),
    );
    if (spare) return false;
    final closed = widget.settings.lowQuotaDismissedAt;
    return closed == null || DateTime.now().difference(closed) >= _quiet;
  }

  /// Whether to show it now; the minute starts at the first look of a
  /// connection.
  bool _visible() {
    if (!_due) return false;
    final connection = widget.status.proxy?.startedAt;
    if (!_started || _shownFor != connection) {
      _started = true;
      _shownFor = connection;
      _over = false;
      _minute?.cancel();
      _minute = Timer(_showFor, () {
        _over = true;
        _changed.value++;
      });
    }
    return !_over;
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible()) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final p = widget.palette;
    final usage = widget.status.activeAccount!.usage!;
    String rounded(int bytes) => formatBytes(bytes).replaceAll('.0 ', ' ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: StatusColors.busy.withValues(alpha: p.dark ? 0.16 : 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: StatusColors.busy.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.data_usage_rounded,
                      color: StatusColors.busy,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l.lowQuotaNotice(
                        rounded(usage.remainingBytes),
                        rounded(usage.limitBytes),
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: p.text,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.close,
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
                    onPressed: () {
                      widget.settings.update(
                        lowQuotaDismissedAt: DateTime.now(),
                      );
                      setState(() {});
                    },
                  ),
                ],
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: () => showSignInDialog(context, widget.core),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(l.addAccount),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
