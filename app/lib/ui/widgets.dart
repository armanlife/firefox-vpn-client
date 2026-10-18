import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/android_core.dart';
import '../core/core_api.dart';
import '../core/models.dart';
import '../core/ports.dart';
import '../core/remote_flags.dart';
import '../l10n/app_localizations.dart';
import 'country_names.dart';

/// Status colors that read in both themes.
abstract final class StatusColors {
  static const good = Color(0xFF22A06B);
  static const busy = Color(0xFFE2A400);
  static const bad = Color(0xFFE5484D);
  static const idle = Color(0xFF8B8D98);
}

/// How the app presents the engine state.
class PhaseLook {
  const PhaseLook(this.label, this.color, this.hint);

  final String label;
  final Color color;

  /// The core's message for states that need one; empty otherwise.
  final String hint;

  static PhaseLook of(AppLocalizations l, CoreStatus s) {
    final message = s.state.message;
    return switch (s.state.phase) {
      // Connected in either mode on the computer (Proxy or System proxy).
      // Asleep (no traffic yet, or idle) still counts as connected: the
      // proxy wakes on the first connection.
      Phase.running => PhaseLook(l.stateConnected, StatusColors.good, ''),
      Phase.starting => PhaseLook(l.stateConnecting, StatusColors.busy, ''),
      // The core's own words name its web dashboard; the app has a page.
      Phase.waiting when s.totalAccounts == 0 => PhaseLook(
        l.stateWaiting,
        StatusColors.busy,
        l.waitingForAccount,
      ),
      Phase.waiting => PhaseLook(l.stateWaiting, StatusColors.busy, message),
      Phase.error when s.state.proxyPortInUse => PhaseLook(
        l.stateError,
        StatusColors.bad,
        l.proxyPortInUse('${portOf(s.state.address) ?? s.state.address}'),
      ),
      Phase.error => PhaseLook(l.stateError, StatusColors.bad, message),
      // Turned off on the phone.
      Phase.off => PhaseLook(l.stateOff, StatusColors.idle, ''),
      _ => PhaseLook(l.stateUnknown, StatusColors.idle, message),
    };
  }
}

/// Words a [CoreUnavailable] for people.
String describeProblem(AppLocalizations l, CoreUnavailable e) =>
    switch (e.problem) {
      CoreProblem.starting => l.startingCore,
      CoreProblem.notAnswering => l.errNotAnswering,
      CoreProblem.refused => l.errRefused,
      CoreProblem.portInUse => l.errPortInUse(
        '${portOf(e.detail) ?? e.detail}',
      ),
      CoreProblem.noCore => l.errNoCore(e.detail),
      CoreProblem.exited => l.errCoreExited(e.detail),
    };

/// The color of a real delay: green when quick, amber when slow, red when
/// very slow.
Color delayColor(int ms) => ms < 400
    ? StatusColors.good
    : ms < 1000
    ? StatusColors.busy
    : StatusColors.bad;

/// Mozilla lists its recommended location as a country of its own, code
/// REC (named "Recomended Location").
bool isRecommendedPlace(String code) => code.toUpperCase() == 'REC';

/// A location's name for people: the recommended location in the user's
/// language, otherwise Mozilla's name, or the code.
String locationName(AppLocalizations l, String code, String name) =>
    isRecommendedPlace(code)
    ? l.recommendedLocation
    : name.isEmpty
    ? code
    : name;

/// The phone home's colors: a deep navy night and the state's light.
abstract final class Midnight {
  static const top = Color(0xFF141B3D);
  static const bottom = Color(0xFF070A18);
  static const connected = Color(0xFF10D9A0);
  static const busy = Color(0xFFFFB547);
  static const error = Color(0xFFFF5C7A);
  static const idle = Color(0xFF7C83FF);
  static const muted = Color(0xFF9AA3C7);
}

/// A dark theme for the phone's home and its navigation bar, with the
/// app's fonts.
ThemeData midnightTheme(ThemeData base) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Midnight.idle,
        brightness: Brightness.dark,
      ).copyWith(
        surface: Midnight.bottom,
        surfaceContainer: Midnight.bottom,
        onSurface: Colors.white,
        onSurfaceVariant: Midnight.muted,
        secondaryContainer: Colors.white.withValues(alpha: 0.10),
        onSecondaryContainer: Colors.white,
      );
  return ThemeData(
    colorScheme: scheme,
    fontFamily: base.textTheme.bodyMedium?.fontFamily,
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: Midnight.bottom,
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// A country's name: the server list's, else the English name of its code.
String countryName(String code, [String name = '']) =>
    name.isNotEmpty ? name : countryNames[code.toUpperCase()] ?? code;

/// Where the phone's traffic goes, for its home page.
class HomePlace {
  const HomePlace(this.flag, this.name, this.caption, {this.auto = false});

  /// A country code for the flag ('REC' for the recommended location).
  final String flag;
  final String name;

  /// The line above the name: how the location is chosen, or what it is.
  final String caption;

  /// Chosen by the app (recommended or fastest): the caption says so.
  final bool auto;
}

/// The phone home's location. While connected: the country the traffic
/// leaves from (for the recommended location, the exit's country), under
/// how it was chosen; otherwise the chosen location.
HomePlace homeLocation(
  AppLocalizations l,
  CoreStatus status, {
  required bool connected,
}) {
  final proxy = status.proxy;
  final exit = status.exit;
  final selection = status.selection.toLowerCase();
  final auto = switch (selection) {
    '' => l.recommendedLocation,
    'fastest' => l.modeFastest,
    _ => null,
  };
  if (connected && proxy != null) {
    final (code, name) = !isRecommendedPlace(proxy.countryCode)
        ? (proxy.countryCode, proxy.countryName)
        : exit != null && exit.countryCode.length == 2
        ? (exit.countryCode, exit.countryName)
        : ('', '');
    if (code.isNotEmpty) {
      return HomePlace(
        code,
        countryName(code, name),
        auto ?? l.connectedTo,
        auto: auto != null,
      );
    }
  }
  if (auto != null) return HomePlace('REC', auto, l.homeLocation);
  return HomePlace(
    status.selection.toUpperCase(),
    countryName(status.selection, status.selectionName),
    l.homeLocation,
  );
}

/// The notes the home pages show: not the ports Mozilla refuses, which
/// apps (every app, in the phone's VPN) try before falling back to 443;
/// the logs keep those.
List<Notice> homeNotices(List<Notice> notices) => [
  for (final n in notices)
    if (n.kind != 'port') n,
];

/// A country's flag, 4:3 with rounded corners; a star for the recommended
/// location, and the code in a small box when there is no flag for it.
class CountryFlag extends StatelessWidget {
  const CountryFlag({super.key, required this.code, this.width = 28});

  final String code;
  final double width;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final height = width * 3 / 4;
    final fallback = Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      color: scheme.secondaryContainer,
      child: Text(
        code.toUpperCase(),
        style: TextStyle(
          fontSize: height * 0.45,
          fontWeight: FontWeight.w700,
          color: scheme.onSecondaryContainer,
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: isRecommendedPlace(code)
          ? Container(
              width: width,
              height: height,
              alignment: Alignment.center,
              color: scheme.primaryContainer,
              child: Icon(
                Icons.auto_awesome_rounded,
                size: height * 0.7,
                color: scheme.onPrimaryContainer,
              ),
            )
          : code.length != 2
          ? fallback
          : bundledFlags.contains(code.toLowerCase())
          ? SvgPicture.asset(
              'assets/flags/${code.toLowerCase()}.svg',
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            )
          // Not carried: from the core, the code until it arrives.
          : FutureBuilder(
              future: RemoteFlags.load(code.toLowerCase()),
              builder: (context, snapshot) => switch (snapshot.data) {
                final svg? => SvgPicture.memory(
                  svg,
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                ),
                null => fallback,
              },
            ),
    );
  }
}

/// The name of a routing region (`routing.region`) in the UI language.
String regionName(AppLocalizations l, String code) => switch (code) {
  'ir' => l.regionIr,
  'cn' => l.regionCn,
  'ru' => l.regionRu,
  'af' => l.regionAf,
  'tr' => l.regionTr,
  'id' => l.regionId,
  'br' => l.regionBr,
  _ => l.regionNone,
};

/// The languages, each in its own words.
const languageNames = {
  'en': 'English',
  'fa': 'فارسی',
  'ar': 'العربية',
  'zh': '简体中文',
  'zh_Hant': '繁體中文',
  'ru': 'Русский',
  'es': 'Español',
  'pt': 'Português (Brasil)',
  'tr': 'Türkçe',
  'fr': 'Français',
  'hu': 'Magyar',
  'id': 'Bahasa Indonesia',
  'az': 'Azərbaycan dili',
  'vi': 'Tiếng Việt',
  'bn': 'বাংলা',
};

/// The bundled font for a language: Vazirmatn for the Arabic script
/// (Persian, Arabic); null for the system font.
String? languageFont(String code) =>
    const {'fa', 'ar'}.contains(code) ? 'Vazirmatn' : null;

/// A title or label in its own language's font.
TextStyle? languageStyle(String code) => switch (languageFont(code)) {
  final font? => TextStyle(fontFamily: font),
  null => null,
};

/// The margin around a page: narrower on a phone.
EdgeInsets pagePadding(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600
    ? const EdgeInsets.fromLTRB(16, 16, 16, 20)
    : const EdgeInsets.fromLTRB(28, 24, 28, 28);

/// Marks a page opened with its own top bar (Android), which names it.
class OwnTopBar extends InheritedWidget {
  const OwnTopBar({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OwnTopBar>() != null;

  @override
  bool updateShouldNotify(OwnTopBar oldWidget) => false;
}

/// A page's title; nothing when the page has its own top bar.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => OwnTopBar.of(context)
      ? const SizedBox.shrink()
      : Text(text, style: Theme.of(context).textTheme.headlineSmall);
}

/// A titled card section.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A usage bar with the account-switch threshold marked.
/// The color of a quota by what is left: green, amber for the last 5 GB,
/// red for the last 1 GB.
Color quotaColor(int remainingBytes) {
  const gb = 1024 * 1024 * 1024;
  return remainingBytes <= gb
      ? StatusColors.bad
      : remainingBytes <= 5 * gb
      ? StatusColors.busy
      : StatusColors.good;
}

class QuotaBar extends StatelessWidget {
  const QuotaBar({
    super.key,
    required this.percent,
    required this.remainingBytes,
    this.threshold = 0,
  });

  final double percent;
  final int remainingBytes;
  final double threshold;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = (percent / 100).clamp(0.0, 1.0);
    final color = quotaColor(remainingBytes);
    return SizedBox(
      height: 8,
      child: LayoutBuilder(
        builder: (context, box) => Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: value,
                  color: color,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ),
            if (threshold > 0 && threshold < 100)
              PositionedDirectional(
                start: box.maxWidth * threshold / 100 - 1,
                top: -3,
                bottom: -3,
                child: Tooltip(
                  message: AppLocalizations.of(context)
                      .switchAt(threshold.round()),
                  child: Container(width: 2, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small rounded label.
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color, this.icon});

  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c),
          ),
        ],
      ),
    );
  }
}

/// Runs [action] and shows its error, if any, in a snack bar.
Future<bool> runShowingErrors(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } on CoreApiException catch (e) {
    if (context.mounted) showError(context, e.message);
  } on CoreUnavailable catch (e) {
    if (context.mounted) {
      showError(context, describeProblem(AppLocalizations.of(context), e));
    }
  } on VpnNotAllowed {
    if (context.mounted) {
      showError(context, AppLocalizations.of(context).vpnNotAllowed);
    }
  }
  return false;
}

void showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        width: 520,
      ),
    );
}
