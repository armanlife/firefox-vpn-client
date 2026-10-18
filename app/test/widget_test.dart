import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firefox_vpn/app_settings.dart';
import 'package:firefox_vpn/core/core_api.dart';
import 'package:firefox_vpn/core/core_controller.dart';
import 'package:firefox_vpn/core/models.dart';
import 'package:firefox_vpn/desktop/close_dialog.dart';
import 'package:firefox_vpn/l10n/app_localizations.dart';
import 'package:firefox_vpn/ui/app.dart';
import 'package:firefox_vpn/ui/widgets.dart';

Map<String, Object?> _account(
  String id,
  String status, {
  bool active = false,
}) => {
  'id': id,
  'name': '$id@example.com',
  'email': '$id@example.com',
  'enabled': true,
  'active': active,
  'status': status,
  'usage': {'limit_bytes': 50 << 30, 'remaining_bytes': 30 << 30},
  'used_percent': 40,
};

/// An in-memory core; it never opens a socket.
class FakeApi implements CoreApi {
  String mode = 'set';

  /// False for a phone: no system proxy; the proxy is turned on or off.
  bool systemProxySupported = true;
  bool on = true;

  /// Mozilla's recommended location, as its server list names it.
  bool recommended = false;

  /// Whether connection tests pass (false: no internet).
  bool online = true;

  /// False: no account added yet.
  bool hasAccounts = true;

  /// The phone reported no network (no Wi-Fi, no mobile data).
  bool noNetwork = false;

  Map<String, Object?> get _lastTest => {
    'at': DateTime.now().toUtc().toIso8601String(),
    'ok': online,
    'http_status': online ? 204 : 0,
    'tunnel_ms': 120,
    'tls_ms': 90,
    'response_ms': 70,
    'total_ms': 280,
  };

  @override
  Future<ConnectionTest> test() async => ConnectionTest.fromJson(_lastTest);
  bool portTaken = false;
  String location = '';
  Map<String, Object?> config = {
    'routing': {'enabled': false, 'region': ''},
  };
  final accountsJson = [
    _account('alice', 'ready', active: true),
    _account('bob', 'reauth_required'),
  ];

  @override
  CoreEndpoint get endpoint =>
      CoreEndpoint(Uri.parse('http://127.0.0.1:9'), 'test');

  @override
  void close() {}

  @override
  Future<CoreStatus> status() async => CoreStatus.fromJson({
    'state': portTaken
        ? {
            'phase': 'error',
            'message': 'listen tcp 127.0.0.1:10810: bind: address in use',
            'code': 'proxy_port_in_use',
            'address': '127.0.0.1:10810',
          }
        : on
        ? {'phase': 'running', 'message': ''}
        : {'phase': 'off', 'message': 'Proxy off'},
    'system_proxy': systemProxySupported ? mode : 'clear',
    'system_proxy_supported': systemProxySupported,
    if (noNetwork) 'no_network': true,
    'proxy': recommended
        ? {
            'listen': '127.0.0.1:10810',
            'country_code': 'REC',
            'country_name': 'Recomended Location',
            'city_name': 'Recomended Location',
            'selection_source': 'recommended_location',
          }
        : {
            'listen': '127.0.0.1:10810',
            'country_code': 'NL',
            'country_name': 'Netherlands',
            'city_name': 'Amsterdam',
            'transport': 'HTTP/3',
          },
    if (recommended)
      'exit': {'ipv4': '192.0.2.7', 'country_code': 'BE', 'city': 'Brussels'},
    'active_account': accountsJson.first,
    'last_test': _lastTest,
    if (!systemProxySupported)
      'notices': [
        {
          'kind': 'port',
          'detail': '5228',
          'count': 2,
          'hosts': ['mtalk.test'],
        },
      ],
    'accounts': hasAccounts
        ? {'total': 2, 'ready': 1, 'reauth_required': 1}
        : {'total': 0},
    'switch_threshold_percent': 90,
    'version': '9.9',
  });

  @override
  Future<AccountList> accounts() async => AccountList.fromJson({
    'accounts': accountsJson,
    'switch_threshold_percent': 90,
  });

  @override
  Future<void> setSystemProxy(String mode) async => this.mode = mode;

  @override
  Future<void> setPower(bool on) async => this.on = on;

  @override
  Future<RoutingInfo> routing() async => RoutingInfo.fromJson({
    'enabled':
        config['routing'] is Map &&
        (config['routing'] as Map)['enabled'] == true,
    'region_rules': ['geosite:ir', 'geoip:ir', 'geoip:private'],
  });

  @override
  Future<LocationList> locations() async => LocationList.fromJson({
    'locations': [
      {
        'code': 'NL',
        'name': 'Netherlands',
        'city': 'Amsterdam',
        'recommended': true,
        'ping_ms': 180,
      },
      {'code': 'DE', 'name': 'Germany', 'city': 'Frankfurt', 'ping_ms': 650},
      {'code': 'JP', 'name': 'Japan', 'locked': true},
    ],
  });

  @override
  Future<void> setLocation(String country) async => location = country;

  /// Delay measurements asked for.
  int pings = 0;

  @override
  Future<LocationList> pingLocations(List<String> codes) async {
    pings++;
    return locations();
  }

  @override
  Future<List<LogEntry>> logs(int after) async => after > 0
      ? const []
      : [
          LogEntry.fromJson({
            'id': 1,
            'level': 'INFO',
            'message': 'proxy started',
          }),
          LogEntry.fromJson({
            'id': 2,
            'level': 'WARN',
            'message': 'renewal slow',
          }),
        ];

  @override
  Future<Map<String, Object?>> settings() async =>
      jsonDecode(jsonEncode(config)) as Map<String, Object?>;

  @override
  Future<void> saveSettings(Map<String, Object?> config) async =>
      this.config = config;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No endless animations (the connected button breathes), as with
/// Windows' animation effects off.
void stillMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

void main() {
  testWidgets('shows the state, turns the VPN off, lists accounts', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi();
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    expect(find.text('Connected'), findsOneWidget);
    // Where the traffic goes: the country, under how it was chosen.
    expect(find.text('Netherlands'), findsOneWidget);
    expect(find.text('Recommended location'), findsOneWidget);
    expect(find.textContaining('Amsterdam'), findsNothing);
    // The data used rather than the email.
    expect(find.text('Data used'), findsOneWidget);
    expect(find.textContaining('@example.com'), findsNothing);
    // The two modes, picked by name; System proxy is on.
    expect(find.text('Proxy'), findsOneWidget);
    expect(find.text('System proxy'), findsOneWidget);
    expect(find.textContaining('Windows and most apps'), findsOneWidget);

    // Proxy mode: Windows is left alone, and nothing disconnects.
    await tester.tap(find.text('Proxy'));
    await tester.pumpAndSettle();
    expect(api.mode, 'clear');
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Netherlands'), findsOneWidget);
    // The proxy's address shows when the mouse is over Proxy.
    expect(
      find.byTooltip('Proxy service active · 127.0.0.1:10810'),
      findsOneWidget,
    );
    expect(find.textContaining('Only apps set up'), findsOneWidget);

    await tester.tap(find.text('System proxy'));
    await tester.pumpAndSettle();
    expect(api.mode, 'set');
    expect(find.text('Connected'), findsOneWidget);

    // The button turns the proxy off, and on again.
    await tester.tap(find.byTooltip('Click to disconnect'));
    await tester.pumpAndSettle();
    expect(api.on, isFalse);
    expect(find.text('Disconnected'), findsOneWidget);
    await tester.tap(find.byTooltip('Click to connect'));
    await tester.pumpAndSettle();
    expect(api.on, isTrue);
    expect(find.text('Connected'), findsOneWidget);

    await tester.tap(find.text('Accounts').first);
    await tester.pumpAndSettle();
    expect(find.text('alice@example.com'), findsOneWidget);
    expect(find.text('Needs sign-in'), findsOneWidget);
    expect(find.text('Sign in again'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('explains a missing core', (tester) async {
    stillMotion(tester);
    final core = CoreController(
      () async => throw const CoreUnavailable(
        CoreProblem.noCore,
        'C:/x/firefox-vpn-core.exe',
      ),
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    expect(find.text("Can't reach the core"), findsOneWidget);
    expect(
      find.text(
        'The core program was not found next to the app (C:/x/firefox-vpn-core.exe).',
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('speaks Persian right to left', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final core = CoreController(
      () async => FakeApi(),
      pollInterval: const Duration(hours: 1),
    );
    final settings = AppSettings()..language = 'fa';
    await tester.pumpWidget(VpnApp(core: core, settings: settings));
    core.start();
    await tester.pumpAndSettle();

    expect(find.text('متصل'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('متصل'))),
      TextDirection.rtl,
    );

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('the close dialog returns the choice and remember flag', (
    tester,
  ) async {
    stillMotion(tester);
    CloseChoice? choice;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showCloseDialog(context),
            child: const Text('close'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remember my choice'));
    await tester.tap(find.text('Minimize to tray'));
    await tester.pumpAndSettle();
    expect(choice, (action: CloseAction.tray, remember: true));
  });

  testWidgets('the welcome page sets the language and the routing', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi();
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    final settings = AppSettings()
      ..firstRun = true
      ..language = 'en';
    await tester.pumpWidget(VpnApp(core: core, settings: settings));
    core.start();
    await tester.pumpAndSettle();
    expect(find.text('Welcome'), findsOneWidget);

    // Persian brings Iran's routing with it.
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('فارسی').last);
    await tester.pumpAndSettle();
    expect(find.text('خوش آمدید'), findsOneWidget);
    expect(find.text('ایران'), findsOneWidget);

    await tester.tap(find.text('شروع'));
    await tester.pumpAndSettle();
    expect(settings.firstRun, isFalse);
    expect(settings.language, 'fa');
    expect(api.config['routing'], {'enabled': true, 'region': 'ir'});
    expect(find.text('متصل'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('offers another port when the proxy port is taken', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()..portTaken = true;
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Port 10810 is used by another program, so the proxy cannot start.',
      ),
      findsOneWidget,
    );
    expect(find.text('Change port'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  for (final (language, connected) in [
    ('zh', '已连接'),
    ('ru', 'Подключено'),
    ('es', 'Conectado'),
    ('tr', 'Bağlı'),
    ('pt', 'Conectado'),
    ('zh_Hant', '已連線'),
    ('vi', 'Đã kết nối'),
    ('ar', 'متصل'),
    ('bn', 'সংযুক্ত'),
    ('fr', 'Connecté'),
    ('hu', 'Csatlakozva'),
    ('id', 'Terhubung'),
    ('az', 'Qoşulub'),
  ]) {
    testWidgets('speaks $language', (tester) async {
      stillMotion(tester);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final core = CoreController(
        () async => FakeApi(),
        pollInterval: const Duration(hours: 1),
      );
      await tester.pumpWidget(
        VpnApp(core: core, settings: AppSettings()..language = language),
      );
      core.start();
      await tester.pumpAndSettle();
      expect(find.text(connected), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.text(connected))),
        AppSettings.rtlLanguages.contains(language)
            ? TextDirection.rtl
            : TextDirection.ltr,
      );

      await tester.pumpWidget(const SizedBox());
      core.dispose();
    });
  }

  testWidgets('shows the real delay, and the logs for everyone', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final core = CoreController(
      () async => FakeApi(),
      pollInterval: const Duration(hours: 1),
    );
    final settings = AppSettings();
    await tester.pumpWidget(VpnApp(core: core, settings: settings));
    core.start();
    await tester.pumpAndSettle();

    // The response time, as v2ray clients show it; no test stages.
    expect(find.text('70 ms'), findsWidgets);
    expect(find.text('Total 280 ms'), findsNothing);
    expect(find.textContaining('Tunnel'), findsNothing);
    expect(find.text('HTTP 204'), findsNothing);
    // The logs are there for everyone.
    expect(find.text('Logs'), findsOneWidget);

    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('proxy started'), findsOneWidget);
    expect(find.textContaining('renewal slow'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('lists servers by delay and uses one', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi();
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Servers'));
    await tester.pumpAndSettle();
    // Never measured: the page measures the delays as it opens.
    expect(api.pings, 1);
    // The app's choices first, then the locations with their delay.
    expect(find.text('Recommended'), findsOneWidget);
    expect(find.text('Fastest'), findsOneWidget);
    expect(find.text('Netherlands'), findsOneWidget);
    expect(find.text('Germany'), findsOneWidget);
    expect(find.text('180 ms'), findsOneWidget);
    // A locked location that never answered is behind "Show locked".
    expect(find.text('Japan'), findsNothing);

    // A tap on a row chooses it.
    await tester.tap(find.text('Germany'));
    await tester.pumpAndSettle();
    expect(api.location, 'DE');
    await tester.tap(find.text('Recommended'));
    await tester.pumpAndSettle();
    expect(api.location, '');

    await tester.tap(find.text('Show locked locations (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Japan'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('opens settings sections and the About tab', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()
      ..config = {
        'proxy': {'listen': '127.0.0.1:10810'},
        'routing': {
          'enabled': true,
          'region': 'ir',
          'direct': ['geoip:ir', 'domain:my.example'],
        },
      };
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Routing'));
    await tester.pumpAndSettle();
    expect(find.text('Direct connection for local sites'), findsOneWidget);
    // The country's rules are in the editable Direct list.
    final direct = find.widgetWithText(TextField, 'Direct');
    expect(
      tester.widget<TextField>(direct).controller!.text,
      'geoip:ir\ndomain:my.example',
    );
    // Restoring puts the region's rules back first, keeping the user's.
    await tester.tap(find.text("Restore the region's rules"));
    await tester.pumpAndSettle();
    final routing = api.config['routing'] as Map<String, Object?>;
    expect(routing['direct'], [
      'geosite:ir',
      'geoip:ir',
      'geoip:private',
      'domain:my.example',
    ]);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('DNS'), findsOneWidget);

    // Choices open in a dialog in the middle of the window.
    await tester.tap(find.text('General'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System default'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Esc goes back one level too.
    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();
    expect(find.text('Listen on'), findsOneWidget);
    expect(find.text('127.0.0.1 · this device only'), findsOneWidget);
    // The app's port is under Advanced, not here; locked locations and
    // sleep are connection settings.
    expect(find.text('App port'), findsNothing);
    expect(find.text('Allow locked locations'), findsOneWidget);
    expect(find.text('Sleep when idle after'), findsOneWidget);

    // Changing the proxy port starts from the current one, not from "taken".
    await tester.tap(find.text('Proxy port'));
    await tester.pumpAndSettle();
    expect(find.textContaining('is taken'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      '10810',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // The proxy login: one form, both fields saved together.
    await tester.tap(find.text('Proxy login'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Proxy username'),
      'user',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Fill in both, or leave both empty.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Proxy password'),
      'secret',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final proxy = api.config['proxy'] as Map<String, Object?>;
    expect((proxy['username'], proxy['password']), ('user', 'secret'));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Listen on'), findsNothing);
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    // Only the computer's app port and web dashboard.
    expect(find.text('App port'), findsOneWidget);
    expect(find.text('Web dashboard'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('DNS'), findsOneWidget);

    // The accounts page says where to make an account.
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    expect(find.text("Don't have a Firefox Account?"), findsOneWidget);
    expect(find.text('accounts.firefox.com'), findsOneWidget);

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('9.9'), findsOneWidget);
    expect(find.text('Check for updates'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('a phone gets Home and Settings, and pages with a back bar', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final core = CoreController(
      () async => FakeApi(),
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Logs'), findsNothing);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accounts'));
    await tester.pumpAndSettle();
    // The accounts page under its own top bar, with a back button.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('alice@example.com'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Account switching'), findsOneWidget);

    // Back on the Settings tab goes Home rather than out of the app.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.text('Account switching'), findsNothing);
    expect(find.text('Data used'), findsOneWidget);

    // Logs cleared stay cleared when the page opens again.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Logs'), 200);
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('proxy started'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('proxy started'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('proxy started'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('a phone in Persian lays the settings out right to left', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final core = CoreController(
      () async => FakeApi(),
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(
      VpnApp(core: core, settings: AppSettings()..language = 'fa'),
    );
    core.start();
    await tester.pumpAndSettle();

    await tester.tap(find.text('تنظیمات').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('عمومی'));
    await tester.pumpAndSettle();
    // One row per setting: the name on the right (the start), the switch
    // at the end, on the left.
    final label = tester.getRect(find.text('نمایش IP عمومی'));
    final control = tester.getRect(find.byType(Switch).first);
    expect(label.right, greaterThan(300));
    expect(control.right, lessThan(label.left));
    expect((control.center.dy - label.center.dy).abs(), lessThan(24));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('تعویض خودکار حساب'), 200);
    await tester.tap(find.text('تعویض خودکار حساب'));
    await tester.pumpAndSettle();
    // A text setting's Save goes under its field, which keeps the width.
    final field = tester.getRect(find.byType(TextField).first);
    final save = tester.getRect(find.byType(FilledButton).first);
    expect(save.top, greaterThan(field.bottom));
    expect(field.width, greaterThan(300));

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('a phone turns the whole proxy on and off', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()
      ..systemProxySupported = false
      ..recommended = true;
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
      turnOn: (on) async => api.on = on,
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    // On, with no system proxy: connected, not "proxy only".
    expect(find.text('Connected'), findsOneWidget);
    // Connected through the recommended location: the exit's country,
    // without the city, under "Recommended location".
    expect(find.text('Recommended location'), findsOneWidget);
    expect(find.text('Belgium'), findsOneWidget);
    expect(find.textContaining('Brussels'), findsNothing);
    // No public IP on the phone's home.
    expect(find.textContaining('192.0.2.7'), findsNothing);
    // The data used, in the ring and in large type; the email is not on
    // the phone's home.
    expect(find.textContaining('40%'), findsOneWidget);
    expect(find.text('Data used'), findsOneWidget);
    expect(find.textContaining('20.0 GB'), findsOneWidget);
    expect(find.textContaining('@example.com'), findsNothing);
    // Apps in the VPN trying refused ports are no news on the phone.
    expect(find.textContaining('5228'), findsNothing);
    // The local address is not shown unless shared with the LAN.
    expect(find.textContaining('10810'), findsNothing);

    await tester.tap(find.byTooltip('Tap to disconnect'));
    await tester.pumpAndSettle();
    expect(api.on, isFalse);
    expect(find.text('Disconnected'), findsOneWidget);
    // Off: the chosen location, the recommended one by default.
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Recommended location'), findsOneWidget);

    await tester.tap(find.byTooltip('Tap to connect'));
    await tester.pumpAndSettle();
    expect(api.on, isTrue);
    expect(find.text('Connected'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  test('the quota turns amber for the last 5 GB and red for the last 1 GB', () {
    const gb = 1024 * 1024 * 1024;
    expect(quotaColor(20 * gb), StatusColors.good);
    expect(quotaColor(5 * gb), StatusColors.busy);
    expect(quotaColor(2 * gb), StatusColors.busy);
    expect(quotaColor(gb), StatusColors.bad);
    expect(quotaColor(0), StatusColors.bad);
  });

  testWidgets('a phone says connecting until a test passes', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()
      ..systemProxySupported = false
      ..online = false;
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
      turnOn: (on) async => api.on = on,
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    // No internet: the proxy runs, but the VPN does not claim to work.
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.textContaining('No connection'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);

    // The internet is back: the next test confirms it.
    api.online = true;
    await core.runTest();
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);

    // Wi-Fi and mobile data off: Android says so, and the app at once,
    // without a test.
    api.noNetwork = true;
    await core.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('No internet connection'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('a nearly used account suggests another one, for a minute', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // 3 GB left, and the other account needs signing in: nobody takes over.
    final api = FakeApi();
    api.accountsJson.first['usage'] = {
      'limit_bytes': 50 << 30,
      'remaining_bytes': 3 << 30,
    };
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    final settings = AppSettings();
    await tester.pumpWidget(VpnApp(core: core, settings: settings));
    core.start();
    await tester.pumpAndSettle();
    await core.runTest();
    await tester.pumpAndSettle();

    final notice = find.textContaining('running out of data');
    expect(notice, findsOneWidget);
    expect(find.textContaining('3 GB'), findsOneWidget);
    expect(find.textContaining('50 GB'), findsOneWidget);

    // Gone after a minute.
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('connecting without an account opens Add account', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()..hasAccounts = false;
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    // Waiting for an account counts as on: the button would disconnect.
    await tester.tap(find.byTooltip('Click to disconnect'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('the computer says connecting until a test passes', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()
      ..online = false
      ..recommended = true;
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    final settings = AppSettings();
    await tester.pumpWidget(VpnApp(core: core, settings: settings));
    core.start();
    await tester.pumpAndSettle();

    // The system proxy is set, but no test has passed.
    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.textContaining('No connection'), findsOneWidget);
    // The proxy service still runs for apps set up by hand.
    // The proxy's address shows when the mouse is over Proxy.
    expect(
      find.byTooltip('Proxy service active · 127.0.0.1:10810'),
      findsOneWidget,
    );

    api.online = true;
    await core.runTest();
    await tester.pumpAndSettle();
    expect(find.text('Connected'), findsOneWidget);

    // The public IP shows only when asked for (Settings, Advanced); the
    // exit's country shows either way.
    expect(find.text('Belgium'), findsWidgets);
    expect(find.textContaining('192.0.2.7'), findsNothing);
    settings.update(showPublicIp: true);
    await tester.pumpAndSettle();
    expect(find.textContaining('192.0.2.7'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
