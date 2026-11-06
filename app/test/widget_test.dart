import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:arman_vpn/app_info.dart';
import 'package:arman_vpn/app_settings.dart';
import 'package:arman_vpn/core/core_api.dart';
import 'package:arman_vpn/core/core_controller.dart';
import 'package:arman_vpn/core/models.dart';
import 'package:arman_vpn/core/tun_service.dart';
import 'package:arman_vpn/core/updates.dart';
import 'package:arman_vpn/desktop/close_dialog.dart';
import 'package:arman_vpn/l10n/app_localizations.dart';
import 'package:arman_vpn/ui/app.dart';
import 'package:arman_vpn/ui/settings_page.dart'
    show SettingsGroup, pickProgramFile;
import 'package:arman_vpn/ui/signin_dialog.dart';
import 'package:arman_vpn/ui/widgets.dart';

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

  /// The failure code of a failed connection test.
  String testErrorCode = '';

  bool connectPending = false;

  /// Why the last connect was given up (`connect_failure`).
  String connectFailure = '';

  /// The status's `upstream_proxy`: its address while it is on.
  String upstreamProxy = '';

  /// The status's `exit_mismatch`, as the core would send it.
  Map<String, Object?>? exitMismatch;

  /// Another program's system proxy in place of the core's (`by`).
  String? systemProxyTakenBy;

  /// Times the app asked for set while set.
  int retakes = 0;

  /// The TUN mode is offered (Windows), and the status's `tun`.
  bool tunSupported = false;
  Map<String, Object?>? tun;

  Map<String, Object?> get _lastTest => {
    'at': DateTime.now().toUtc().toIso8601String(),
    'ok': online,
    if (!online && testErrorCode.isNotEmpty) 'error_code': testErrorCode,
    'http_status': online ? 204 : 0,
    'tunnel_ms': 120,
    'tls_ms': 90,
    'response_ms': 70,
    'total_ms': 280,
  };

  int tests = 0;

  @override
  Future<ConnectionTest> test() async {
    tests++;
    return ConnectionTest.fromJson(_lastTest);
  }

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
    'system_proxy': systemProxySupported || tunSupported ? mode : 'clear',
    'system_proxy_supported': systemProxySupported,
    'selection': location,
    if (connectPending) 'connect_pending': true,
    if (connectFailure.isNotEmpty) 'connect_failure': connectFailure,
    if (exitMismatch != null) 'exit_mismatch': exitMismatch,
    if (systemProxyTakenBy != null)
      'system_proxy_taken': {'by': systemProxyTakenBy},
    if (tunSupported) 'tun_supported': true,
    if (tunSupported && tun != null) 'tun': tun,
    if (update != null) 'update': update,
    if (noNetwork) 'no_network': true,
    if (upstreamProxy.isNotEmpty) 'upstream_proxy': upstreamProxy,
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
    'accounts': hasAccounts ? accountsJson : const [],
    'switch_threshold_percent': 90,
  });

  @override
  Future<void> setSystemProxy(String mode) async {
    if (mode == 'set' && this.mode == 'set') {
      retakes++;
      systemProxyTakenBy = null;
    }
    this.mode = mode;
  }

  @override
  Future<void> setPower(bool on) async => this.on = on;

  /// The status's `update` (the Windows app's own update), and what the app
  /// asked of it.
  Map<String, Object?>? update;
  final downloads = <String>[];
  final installs = <(String, List<String>)>[];

  @override
  Future<void> downloadUpdate(String version) async {
    downloads.add(version);
    update = {
      'state': 'downloading',
      'version': version,
      'done': 30,
      'total': 100,
    };
  }

  @override
  Future<void> installUpdate(String version, int pid, List<String> args) async {
    installs.add((version, args));
    update = {'state': 'installing', 'version': version};
  }

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
      // Marked locked in Mozilla's list; listed like any other.
      {'code': 'JP', 'name': 'Japan', 'locked': true, 'ping_error': 'timeout'},
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

  /// The proxy's connections, in the order they started; clearing keeps
  /// the open ones, as the core does.
  List<Map<String, Object?>> conns = [
    {
      'id': 1,
      'start': '2026-10-26T10:00:01Z',
      'end': '2026-10-26T10:00:01Z',
      'inbound': 'http',
      'target': 'mail.example.com:993',
      'network': 'tcp',
      'route': 'port',
    },
    {
      'id': 2,
      'start': '2026-10-26T10:00:03Z',
      'end': '2026-10-26T10:00:04Z',
      'inbound': 'socks5',
      'target': 'example.ir:443',
      'network': 'tcp',
      'route': 'direct',
    },
    {
      'id': 3,
      'start': '2026-10-26T10:00:05Z',
      'inbound': 'tun',
      'target': 'web.telegram.org:443',
      'network': 'tcp',
      'route': 'vpn',
      'transport': 'h2',
      'up': 2048,
      'down': 1048576,
    },
  ];

  @override
  Future<List<ProxyConnection>> connections() async => [
    for (final c in conns) ProxyConnection.fromJson(c),
  ];

  @override
  Future<List<ProxyConnection>> clearConnections() async {
    conns = [
      for (final c in conns)
        if (c['end'] == null) c,
    ];
    return connections();
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

  /// The programs running on the computer (GET /api/tun/programs).
  List<Map<String, Object?>> running = [];

  @override
  Future<List<RunningProgram>> runningPrograms() async => [
    for (final p in running) RunningProgram.fromJson(p),
  ];

  /// The email of the last sign-in started.
  String signInEmail = '';

  /// What a started sign-in answers; otherwise it is working, as the
  /// core's is, and the next read finds the password accepted and an email
  /// code asked for.
  Map<String, Object?>? signInOutcome;

  @override
  Future<SignInState> startSignIn(String email, String password) async {
    signInEmail = email;
    return SignInState.fromJson({
      'id': 's1',
      'email': email,
      'step': SignInStep.working,
      ...?signInOutcome,
    });
  }

  @override
  Future<SignInState> signInState(String id) async => SignInState.fromJson({
    'id': id,
    'email': signInEmail,
    'step': SignInStep.needEmailCode,
    'password_accepted': true,
  });

  @override
  Future<void> cancelSignIn(String id) async {}

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
        'C:/x/arman-vpn-core.exe',
      ),
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    expect(find.text("Can't reach the core"), findsOneWidget);
    expect(
      find.text(
        'The core program was not found next to the app (C:/x/arman-vpn-core.exe).',
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

  testWidgets('a system language the app lacks gives English, not Arabic', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = const [
      Locale('de', 'DE'),
      Locale('it'),
    ];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);

    final core = CoreController(
      () async => FakeApi(),
      pollInterval: const Duration(hours: 1),
    );
    // No language chosen: first run, or "System default".
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Connected'));
    expect(Localizations.localeOf(context), const Locale('en'));
    expect(Directionality.of(context), TextDirection.ltr);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('the sign-in form is one a password manager fills and saves', (
    tester,
  ) async {
    stillMotion(tester);
    final api = FakeApi();
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    core.start();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSignInDialog(context, core),
            child: const Text('add'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields[0].autofillHints, contains(AutofillHints.email));
    expect(fields[1].autofillHints, [AutofillHints.password]);
    expect(find.byType(AutofillGroup), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret-pass');
    calls.clear();
    List<MethodCall> finish() => calls
        .where((c) => c.method == 'TextInput.finishAutofillContext')
        .toList();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump();
    // Until Mozilla accepts the password, the form stays (the button busy)
    // and nothing is offered for saving.
    expect(api.signInEmail, 'me@example.com');
    expect(find.byType(AutofillGroup), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(finish(), isEmpty);

    // The next read finds it accepted: the save is asked for, then the
    // form's cancel when it closes follows (the engine ignores it then: no
    // field is connected any more).
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(finish(), isNotEmpty);
    expect(finish().first.arguments, true);

    // The code step's field is offered one-time codes.
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).autofillHints, [
      AutofillHints.oneTimeCode,
    ]);
    // The emailed code takes digits only, from the number keyboard; a
    // Persian keyboard's digits become 0-9.
    final code = tester.widget<TextField>(find.byType(TextField));
    expect(code.keyboardType, TextInputType.number);
    await tester.enterText(find.byType(TextField), '۱۲a3 4-۵٦');
    expect(code.controller!.text, '123456');

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('an email without an account says so and how to make one', (
    tester,
  ) async {
    stillMotion(tester);
    final api = FakeApi()
      ..signInOutcome = {
        'step': SignInStep.failed,
        'message': 'The account was not added.',
        'error': 'No Firefox Account exists for this email.',
        'error_code': SignInError.noAccount,
      };
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    core.start();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSignInDialog(context, core),
            child: const Text('add'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'nobody@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final l = lookupAppLocalizations(const Locale('fa'));
    // The form is back with the email as typed, to correct it.
    expect(find.text(l.signInFailed), findsNothing);
    expect(find.text('nobody@example.com'), findsOneWidget);
    expect(find.text(l.signInNoAccount), findsOneWidget);
    expect(find.text(l.signInNoAccountHint), findsOneWidget);
    expect(find.text(l.createAccountButton), findsOneWidget);
    expect(find.textContaining('No Firefox Account'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('an account without a password offers to set one', (
    tester,
  ) async {
    stillMotion(tester);
    final api = FakeApi()
      ..signInOutcome = {
        'step': SignInStep.failed,
        'message': 'The account was not added.',
        'error': 'This account has no password.',
        'error_code': SignInError.noPassword,
      };
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    core.start();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fa'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSignInDialog(context, core),
            child: const Text('add'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'google@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'pw');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final l = lookupAppLocalizations(const Locale('fa'));
    // Its own text, and the button to set a password instead of Try again.
    expect(find.text(l.signInNoPassword), findsOneWidget);
    expect(find.text(l.setPasswordButton), findsOneWidget);
    expect(find.text(l.tryAgain), findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('a wrong password keeps the form and what was typed', (
    tester,
  ) async {
    stillMotion(tester);
    final api = FakeApi()
      ..signInOutcome = {
        'step': SignInStep.failed,
        'error': 'Incorrect password.',
        'error_code': SignInError.wrongPassword,
      };
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    core.start();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSignInDialog(context, core),
            child: const Text('add'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );
    bool saveAsked() => calls.any(
      (c) =>
          c.method == 'TextInput.finishAutofillContext' && c.arguments == true,
    );
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'me@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'almost-righ');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    final l = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l.signInWrongPassword), findsOneWidget);
    // A refused password is not offered for saving.
    expect(saveAsked(), isFalse);
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(2));
    expect(fields[0].controller!.text, 'me@example.com');
    expect(fields[1].controller!.text, 'almost-righ');
    expect(fields[1].focusNode!.hasFocus, isTrue);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);

    // Sending the corrected password starts a new sign-in.
    api.signInOutcome = null;
    await tester.enterText(find.byType(TextField).at(1), 'almost-right');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pumpAndSettle();
    // Accepted: now it is offered.
    expect(saveAsked(), isTrue);
    expect(find.text(l.signInWrongPassword), findsNothing);
    expect(find.text(l.stepEmailCode('me@example.com')), findsOneWidget);

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

    final api = FakeApi();
    final core = CoreController(
      () async => api,
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

    // The proxy's connections, in the second tab, in the order they started;
    // how each came and its traffic only when asked for.
    await tester.tap(find.text('Connections'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('1 open'), findsOneWidget);
    expect(find.text('web.telegram.org:443'), findsOneWidget);
    expect(find.text('Proxy'), findsOneWidget);
    expect(find.text('Direct'), findsOneWidget);
    expect(find.text('Port refused'), findsOneWidget);
    expect(find.textContaining('1.0 MB'), findsNothing);
    expect(find.text('TUN'), findsNothing);
    expect(find.text('TCP'), findsNWidgets(3));
    // The destination gets the most room.
    expect(
      tester.getSize(find.text('web.telegram.org:443')).width,
      greaterThan(100),
    );
    expect(
      tester.getTopLeft(find.text('example.ir:443')).dy,
      lessThan(tester.getTopLeft(find.text('web.telegram.org:443')).dy),
    );
    // Columns are chosen, and the choice is kept.
    await tester.tap(find.byTooltip('Columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Traffic'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxMenuButton, 'Inbound'));
    await tester.pumpAndSettle();
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(find.text('TUN'), findsOneWidget);
    expect(find.textContaining('H2'), findsNothing);
    expect(find.textContaining('1.0 MB'), findsOneWidget);
    expect(settings.hiddenConnectionColumns, {'duration'});

    // Clear empties the list, the open ones too, also when the tab opens
    // again; later connections show.
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(find.text('No connections yet.'), findsOneWidget);
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connections'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('web.telegram.org:443'), findsNothing);
    api.conns.add({
      'id': 4,
      'start': '2026-10-26T10:00:09Z',
      'target': 'new.example.com:443',
      'route': 'vpn',
    });
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('new.example.com:443'), findsOneWidget);

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
    // Every location is in the one list, also one Mozilla marks locked
    // that did not answer; there is nothing to show or hide.
    expect(find.text('Japan'), findsOneWidget);
    expect(find.textContaining('locked'), findsNothing);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

    // A tap on a row chooses it.
    await tester.tap(find.text('Germany'));
    await tester.pumpAndSettle();
    expect(api.location, 'DE');
    await tester.tap(find.text('Recommended'));
    await tester.pumpAndSettle();
    expect(api.location, '');
    await tester.tap(find.text('Japan'));
    await tester.pumpAndSettle();
    expect(api.location, 'JP');

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('the phone lists General first, then the groups', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(400, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()..systemProxySupported = false;
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final tops = [
      for (final name in [
        'General',
        'Servers',
        'Accounts',
        'Network',
        'Connection',
        'Routing',
        'DNS',
        'If Mozilla is blocked',
        'Relay server',
        'TLS fragmentation',
        'Upstream proxy',
        'App',
        'Logs',
        'About',
      ])
        tester.getTopLeft(find.text(name).first).dy,
    ];
    expect(tops, [...tops]..sort());
    // The group's title and its first row.
    expect(find.text('General'), findsNWidgets(2));

    // The relay server has a row of its own, and is not under Connection too.
    await tester.tap(find.text('Relay server'));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Relay server');
    expect(field, findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connection'));
    await tester.pumpAndSettle();
    expect(field, findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('the accounts page has the switching with a second account', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 1400);
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
    await tester.tap(find.text('Accounts').first);
    await tester.pumpAndSettle();

    final row = find.text('Account switching');
    expect(row, findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(of: row, matching: find.byType(ListTile)),
        matching: find.textContaining('90%'),
      ),
      findsOneWidget,
    );

    await tester.tap(row);
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(field).controller!.text, '90');
    await tester.enterText(field, '0');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('from 1 to 100'), findsOneWidget);
    expect(api.config['accounts'], isNull);
    await tester.enterText(field, '70');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    final accounts = api.config['accounts'] as Map<String, Object?>;
    expect(accounts['switch_threshold_percent'], 70);

    // One account: nothing to switch to.
    api.accountsJson.removeLast();
    await core.refresh(accountsToo: true);
    await tester.pumpAndSettle();
    expect(row, findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('a computer lists the settings in the same groups', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 1400);
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
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final list = find.byType(SettingsGroup);
    expect(list, findsNWidgets(3));
    String texts(int i) => tester
        .widgetList<Text>(
          find.descendant(of: list.at(i), matching: find.byType(Text)),
        )
        .map((t) => t.data)
        .join(', ');
    expect(texts(0), 'General, General, Connection, Routing, DNS');
    expect(
      texts(1),
      'If Mozilla is blocked, Relay server, TLS fragmentation, '
      'Upstream proxy',
    );
    expect(texts(2), 'App, Advanced, Logs');

    // Logs, in the side menu too, open that same page.
    await tester.tap(
      find.descendant(of: list.at(2), matching: find.text('Logs')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('proxy started'), findsOneWidget);
    expect(list, findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('the relay server is under If Mozilla is blocked', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 1400);
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
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Relay server'));
    await tester.pumpAndSettle();

    expect(find.text('If Mozilla is blocked'), findsOneWidget);
    final field = find.widgetWithText(TextField, 'Relay server');
    // Save goes under the field on a computer too: long addresses need the width.
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.getRect(save).top, greaterThan(tester.getRect(field).bottom));
    expect(tester.getRect(field).width, greaterThan(600));
    await tester.enterText(field, 'http://relay.example');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Must be an https:// address.'), findsOneWidget);
    await tester.enterText(field, 'https://relay.example/?secret=k');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final network = api.config['network'] as Map<String, Object?>;
    expect(network['api_relay'], 'https://relay.example/?secret=k');

    // ECH works by itself: there is nothing to choose.
    expect(find.textContaining('ECH'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('TLS fragmentation is in the list of settings', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 1400);
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
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TLS fragmentation'));
    await tester.pumpAndSettle();

    // Off by default.
    bool selected(String label) =>
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>).last)
            .groupValue ==
        label;
    expect(selected('off'), isTrue);
    expect(find.text('Normal TLS connection'), findsOneWidget);
    expect(
      find.text('Splits the TLS header at the first byte (0x16)'),
      findsOneWidget,
    );
    expect(
      find.text('Splits the server name (SNI) across TCP packets'),
      findsOneWidget,
    );
    final sni = find.text('Server name (SNI)');
    await tester.ensureVisible(sni);
    await tester.pumpAndSettle();
    await tester.tap(sni);
    await tester.pumpAndSettle();
    expect(
      (api.config['network'] as Map<String, Object?>)['hello_split'],
      'sni',
    );
    expect(selected('sni'), isTrue);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('the upstream proxy is in the list of settings', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()
      ..config = {
        'proxy': {'listen': '127.0.0.1:10810'},
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
    await tester.tap(find.text('Upstream proxy'));
    await tester.pumpAndSettle();

    final address = find.widgetWithText(TextField, 'SOCKS5 proxy address');
    final port = find.widgetWithText(TextField, 'Port');
    final username = find.widgetWithText(TextField, 'Proxy username');
    final password = find.widgetWithText(TextField, 'Proxy password');
    final save = find.widgetWithText(FilledButton, 'Save');
    Future<void> enter(Finder field, String text) async {
      await tester.enterText(field, text);
      await tester.pump();
    }

    Future<void> submit() async {
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
    }

    Map<String, Object?> network() =>
        api.config['network'] as Map<String, Object?>? ?? const {};
    String text(Finder field) =>
        tester.widget<TextField>(field).controller!.text;

    // What the core would refuse is said here.
    await enter(address, '127.0.0.1');
    await submit();
    expect(find.text('Enter a port from 1 to 65535.'), findsOneWidget);
    expect(network()['upstream_proxy'], isNull);
    await enter(address, '');
    await enter(port, '1080');
    await submit();
    expect(
      find.text("Enter the proxy's address, such as 127.0.0.1."),
      findsOneWidget,
    );
    await enter(address, '127.0.0.1');
    await enter(port, '10810');
    await submit();
    expect(
      find.text("That's this app's own proxy. Enter another one."),
      findsOneWidget,
    );
    expect(network()['upstream_proxy'], isNull);

    // A paste: spaces inside it and a port with the address go by themselves.
    await enter(address, ' 127. 0.0.1:10808 ');
    expect(text(address), '127.0.0.1:10808');
    await enter(port, '');
    await enter(username, ' u ');
    await submit();
    expect(text(port), '10808');
    expect(text(address), '127.0.0.1');
    expect(find.text('Fill in both, or leave both empty.'), findsOneWidget);
    expect(network()['upstream_proxy'], isNull);

    await enter(password, ' p ');
    await submit();
    expect(network()['upstream_proxy'], '127.0.0.1:10808');
    expect(network()['upstream_proxy_username'], 'u');
    expect(network()['upstream_proxy_password'], 'p');

    // A failed save leaves a field's caret where it was.
    final portField = tester.widget<TextField>(port).controller!;
    portField.selection = const TextSelection.collapsed(offset: 2);
    await enter(password, '');
    await submit();
    expect(find.text('Fill in both, or leave both empty.'), findsOneWidget);
    expect(portField.selection.baseOffset, 2);
    await enter(password, 'p');

    // An address of IPv6, and a scheme.
    await enter(address, 'socks5://[2001:db8::1]:1080/');
    await submit();
    expect(network()['upstream_proxy'], '[2001:db8::1]:1080');
    expect(text(address), '2001:db8::1');
    expect(text(port), '1080');

    // Empty again: directly.
    await enter(address, '');
    await enter(port, '');
    await enter(username, '');
    await enter(password, '');
    await submit();
    expect(network()['upstream_proxy'], '');

    // Turning it on needs an address; the switch stays off without one.
    final toggle = find.byType(Switch);
    Future<void> flip() async {
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
    }

    await flip();
    expect(
      find.text("Enter the proxy's address, such as 127.0.0.1."),
      findsOneWidget,
    );
    expect(find.text('Enter a port from 1 to 65535.'), findsOneWidget);
    expect(network()['upstream_proxy_enabled'], isNot(true));
    expect(tester.widget<Switch>(toggle).value, isFalse);

    // On with what is filled in.
    await enter(address, '127.0.0.1');
    await enter(port, '1080');
    await flip();
    expect(network()['upstream_proxy_enabled'], isTrue);
    expect(network()['upstream_proxy'], '127.0.0.1:1080');
    expect(tester.widget<Switch>(toggle).value, isTrue);

    // Off keeps everything, on screen and in the settings.
    await flip();
    expect(network()['upstream_proxy_enabled'], isFalse);
    expect(network()['upstream_proxy'], '127.0.0.1:1080');
    expect(text(address), '127.0.0.1');
    expect(text(port), '1080');
    expect(tester.widget<Switch>(toggle).value, isFalse);

    // Saved while off, it stays off; on again needs no typing.
    await enter(port, '1081');
    await submit();
    expect(network()['upstream_proxy_enabled'], isFalse);
    expect(network()['upstream_proxy'], '127.0.0.1:1081');
    await flip();
    expect(network()['upstream_proxy_enabled'], isTrue);
    expect(network()['upstream_proxy'], '127.0.0.1:1081');

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets(
    'in Persian the upstream proxy still reads as an address, then a port',
    (tester) async {
      stillMotion(tester);
      tester.view.physicalSize = const Size(1200, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeApi();
      final core = CoreController(
        () async => api,
        pollInterval: const Duration(hours: 1),
      );
      final settings = AppSettings()..language = 'fa';
      await tester.pumpWidget(VpnApp(core: core, settings: settings));
      core.start();
      await tester.pumpAndSettle();
      await tester.tap(find.text('تنظیمات').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('پروکسی بالادستی'));
      await tester.pumpAndSettle();
      final address = find.widgetWithText(TextField, 'آدرس پروکسی SOCKS5');
      final port = find.widgetWithText(TextField, 'پورت');
      expect(tester.getCenter(address).dx, lessThan(tester.getCenter(port).dx));
      for (final field in [address, port]) {
        final widget = tester.widget<TextField>(field);
        expect(widget.textAlign, TextAlign.left);
        expect(widget.textDirection, TextDirection.ltr);
      }

      // Tab goes from the address to the port, not back over the page's order.
      bool focused(Finder field) => tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus;
      await tester.tap(address);
      await tester.pump();
      expect(focused(address), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(focused(port), isTrue);

      await tester.pumpWidget(const SizedBox());
      core.dispose();
    },
  );

  testWidgets('the home page says while the upstream proxy is on', (
    tester,
  ) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 1400);
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
    final mark = find.text('Upstream proxy is on');
    expect(mark, findsNothing);

    api.upstreamProxy = '127.0.0.1:1080';
    await core.refresh();
    await tester.pumpAndSettle();
    expect(mark, findsOneWidget);

    // Disconnected too.
    api.on = false;
    await core.refresh();
    await tester.pumpAndSettle();
    expect(mark, findsOneWidget);

    // The failure's own button says it then.
    api
      ..on = true
      ..online = false
      ..testErrorCode = 'upstream_proxy';
    await core.refresh();
    await core.runTest();
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Upstream proxy'), findsOneWidget);
    expect(mark, findsNothing);

    // It opens the setting.
    api
      ..online = true
      ..testErrorCode = '';
    await core.runTest();
    await tester.pumpAndSettle();
    await tester.tap(mark);
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'SOCKS5 proxy address'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('a failure through the upstream proxy names it', (tester) async {
    final l = await AppLocalizations.delegate.load(const Locale('en'));
    expect(failureCodeText(l, Failure.upstreamProxy), l.failUpstreamProxy);
    expect(l.failUpstreamProxy, contains('upstream proxy'));
  });

  testWidgets('without an account the servers page says to add one', (
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

    await tester.tap(find.text('Servers'));
    await tester.pumpAndSettle();
    // No delay test, which would fail without an account; the notice
    // with its button instead, and the locations still to choose from.
    expect(api.pings, 0);
    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add account'), findsOneWidget);
    expect(find.text('Netherlands'), findsOneWidget);
    final test = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Test real delay'),
    );
    expect(test.onPressed, isNull);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  });

  testWidgets('a refused location offers the recommended one', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The chosen location's server refuses the account: the test fails.
    final api = FakeApi()
      ..location = 'JP'
      ..online = false
      ..testErrorCode = Failure.locationRefused;
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    expect(
      find.text(
        "This country isn't open to your account. Choose another country.",
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Use the recommended location'));
    await tester.pumpAndSettle();
    expect(api.location, '');

    // A connect given up for the same reason offers it too.
    api
      ..on = false
      ..online = true
      ..location = 'JP'
      ..connectFailure = Failure.locationRefused;
    await core.refresh();
    await tester.pumpAndSettle();
    expect(
      find.text(
        "This country isn't open to your account. Choose another country.",
      ),
      findsOneWidget,
    );
    expect(find.text('Use the recommended location'), findsOneWidget);

    // Other failures do not.
    api.connectFailure = Failure.unreachable;
    await core.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Use the recommended location'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('warns when the public IP is in another country', (tester) async {
    stillMotion(tester);
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeApi()
      ..location = 'GB'
      ..exitMismatch = {
        'chosen_country_code': 'GB',
        'chosen_country_name': 'United Kingdom',
        'exit_country_code': 'DE',
      };
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();

    // A soft warning: still connected.
    expect(find.text('Connected'), findsOneWidget);
    expect(
      find.text('You chose United Kingdom, but your IP is in Germany.'),
      findsOneWidget,
    );

    // Never for the recommended location or the fastest one.
    for (final selection in ['', 'fastest']) {
      api.location = selection;
      await core.refresh();
      await tester.pumpAndSettle();
      expect(find.textContaining('but your IP is in'), findsNothing);
    }

    // Nor without a mismatch.
    api
      ..location = 'GB'
      ..exitMismatch = null;
    await core.refresh();
    await tester.pumpAndSettle();
    expect(find.textContaining('but your IP is in'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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
    await tester.tap(find.text('General').last);
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
    // The app's port is under Advanced, not here; sleep is a connection
    // setting. Every location is usable: no switch for locked ones.
    expect(find.text('App port'), findsNothing);
    expect(find.text('Allow locked locations'), findsNothing);
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
    // Its form's Save, before the Worker's at the end of the page.
    final save = find.widgetWithText(FilledButton, 'Save').first;
    await tester.enterText(
      find.widgetWithText(TextField, 'Proxy username'),
      'user',
    );
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Fill in both, or leave both empty.'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Proxy password'),
      'secret',
    );
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
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
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Accounts'),
      ),
    );
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
    expect(find.text('Network'), findsOneWidget);

    // Back on the Settings tab goes Home rather than out of the app.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.text('Network'), findsNothing);
    expect(find.text('Data used'), findsOneWidget);

    // Logs cleared stay cleared when the page opens again.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Logs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    expect(find.textContaining('proxy started'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
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
    await tester.tap(find.text('عمومی').last);
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
    await tester.scrollUntilVisible(find.text('سرور رله'), 200);
    await tester.tap(find.text('سرور رله'));
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

  test('the quota turns amber 10 points before the switch and red at it', () {
    expect(quotaColor(50, 95), StatusColors.good);
    expect(quotaColor(84.9, 95), StatusColors.good);
    expect(quotaColor(85, 95), StatusColors.busy);
    expect(quotaColor(95, 95), StatusColors.bad);
    expect(quotaColor(100, 95), StatusColors.bad);
    // The user's own threshold moves both.
    expect(quotaColor(72, 80), StatusColors.busy);
    expect(quotaColor(80, 80), StatusColors.bad);
    // Unknown threshold: the core's default, 95%.
    expect(quotaColor(90, 0), StatusColors.busy);
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
    expect(find.textContaining("Couldn't connect"), findsOneWidget);
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

  for (final desktop in [false, true]) {
    final layout = desktop ? 'desktop' : 'phone';
    testWidgets('the $layout home waits for the final connect result', (
      tester,
    ) async {
      stillMotion(tester);
      tester.view.physicalSize = desktop
          ? const Size(1200, 900)
          : const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final l = await AppLocalizations.delegate.load(const Locale('en'));
      final api = FakeApi()
        ..systemProxySupported = desktop
        ..on = false
        ..online = false
        ..testErrorCode = Failure.unreachable;
      final core = CoreController(
        () async => api,
        pollInterval: const Duration(hours: 1),
        turnOn: (on) async => api.connectPending = on,
      );
      await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
      core.start();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byTooltip(desktop ? l.tapToConnect : l.tapToConnectPhone),
      );
      await tester.pumpAndSettle();
      expect(find.text(l.stateConnecting), findsOneWidget);
      expect(api.on, isFalse, reason: 'the engine has not started yet');

      api.on = true;
      await core.refresh();
      await tester.pumpAndSettle();
      expect(find.text(l.stateConnecting), findsOneWidget);
      expect(find.text(l.failUnreachable), findsNothing);
      expect(api.tests, 0, reason: 'the core owns the pending attempt');

      api.noNetwork = true;
      await core.refresh();
      await tester.pumpAndSettle();
      expect(find.text(l.stateConnecting), findsOneWidget);
      expect(find.text(l.noNetwork), findsNothing);

      // A different final reason wins even before the engine stops.
      api
        ..connectPending = false
        ..connectFailure = Failure.noNetwork;
      await core.refresh();
      await tester.pumpAndSettle();
      expect(find.text(l.stateOff), findsOneWidget);
      expect(find.text(l.failNoInternet), findsOneWidget);
      expect(find.text(l.failUnreachable), findsNothing);
      expect(api.tests, 0);

      await tester.pumpWidget(const SizedBox());
      core.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

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
    expect(find.textContaining('3 GB'), findsNothing);
    expect(find.textContaining('50 GB'), findsOneWidget);

    // Gone after a minute.
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(notice, findsNothing);

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('connecting without an account opens the accounts page', (
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
    // The page that explains accounts, not the sign-in form.
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('No accounts yet'), findsOneWidget);
    expect(find.text('Add account'), findsWidgets);

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
    expect(find.textContaining("Couldn't connect"), findsOneWidget);
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

  testWidgets(
    'another program taking the system proxy is shown, and taken back',
    (tester) async {
      stillMotion(tester);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = FakeApi()..systemProxyTakenBy = '127.0.0.1:7890';
      final core = CoreController(
        () async => api,
        pollInterval: const Duration(hours: 1),
      );
      await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
      core.start();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Another program set the system proxy to'),
        findsOneWidget,
      );
      await tester.tap(find.text('Set it again'));
      await tester.pumpAndSettle();
      expect(api.retakes, 1);
      expect(find.text('Set it again'), findsNothing);

      // Turned off by the other program; not shown in Proxy mode.
      api.systemProxyTakenBy = '';
      await core.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text(
          "Another program turned the system proxy off, so traffic doesn't go through the VPN.",
        ),
        findsOneWidget,
      );
      api.mode = 'clear';
      await core.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Set it again'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      core.dispose();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('the smallest windows keep everything inside', (tester) async {
    stillMotion(tester);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // The computer layout at the window's smallest inside: the side menu's
    // traffic stays in view, and its pages scroll above it.
    tester.view.physicalSize = const Size(800, 441);
    final api = FakeApi();
    final core = CoreController(
      () async => api,
      pollInterval: const Duration(hours: 1),
    );
    await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
    core.start();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Total traffic')).dy,
      lessThanOrEqualTo(441),
    );

    // Just under the computer layout's width, the phone's, with a problem
    // box and a notice: nothing runs past the bottom.
    api
      ..systemProxySupported = false
      ..online = false
      ..location = 'JP'
      ..testErrorCode = Failure.locationRefused;
    tester.view.physicalSize = const Size(624, 441);
    await core.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.text(
        "This country isn't open to your account. Choose another country.",
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    core.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  group('updates', () {
    const page = 'https://github.com/o/r/releases/tag/v9.9.9';

    Future<(FakeApi, CoreController, AppSettings)> pumpUpdates(
      WidgetTester tester, {
      Map<String, Object?>? update,
      List<String> args = const [],
      Release? found,
    }) async {
      stillMotion(tester);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeApi()..update = update;
      final core = CoreController(
        () async => api,
        pollInterval: const Duration(hours: 1),
      );
      final settings = AppSettings();
      Updates.start(core, settings, args: args);
      Updates.available.value = found;
      await tester.pumpWidget(VpnApp(core: core, settings: settings));
      core.start();
      await tester.pump();
      await tester.pump();
      return (api, core, settings);
    }

    Future<void> done(WidgetTester tester, CoreController core) async {
      Updates.reset();
      await tester.pumpWidget(const SizedBox());
      core.dispose();
    }

    testWidgets('a copy that does not update itself offers the download', (
      tester,
    ) async {
      final (_, core, _) = await pumpUpdates(
        tester,
        found: const Release('9.9.9', page),
      );
      expect(find.text('Version 9.9.9 is available.'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Update'), findsNothing);
      await done(tester, core);
    });

    testWidgets('a version found downloads by itself; Update installs it', (
      tester,
    ) async {
      final (api, core, _) = await pumpUpdates(
        tester,
        update: {'state': 'idle'},
        found: const Release('9.9.9', page),
      );
      var quit = 0;
      Updates.quitApp = () async => quit++;
      await tester.pump();
      expect(api.downloads, ['9.9.9']);
      expect(find.text('Downloading version 9.9.9…'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, closeTo(0.3, 0.001));
      // Downloaded: it waits for the next start, or for Update, which
      // installs it at once, and the app quits.
      api.update = {'state': 'ready', 'version': '9.9.9'};
      await core.refresh();
      await tester.pump();
      expect(api.installs, isEmpty);
      expect(find.text('Version 9.9.9 is ready to install.'), findsOneWidget);
      await tester.tap(find.text('Update'));
      await tester.pump();
      await tester.pump();
      expect(api.installs.single.$1, '9.9.9');
      expect(api.installs.single.$2, isEmpty);
      expect(quit, 1);
      await tester.pump();
      expect(
        find.text(
          'Installing version 9.9.9. The app will close and open again.',
        ),
        findsOneWidget,
      );
      await done(tester, core);
    });

    testWidgets('a version downloaded before installs at the start', (
      tester,
    ) async {
      var quit = 0;
      Updates.quitApp = () async => quit++;
      final (api, core, _) = await pumpUpdates(
        tester,
        update: {'state': 'ready', 'version': '9.9.9'},
        args: ['--autostart', '--data-dir=elsewhere'],
      );
      // With the app's own arguments (its data folder too, so the new
      // version opens the same one), and before it connects.
      expect(api.installs.single.$1, '9.9.9');
      expect(api.installs.single.$2, ['--autostart', '--data-dir=elsewhere']);
      expect(Updates.installingAtStart.value, isTrue);
      expect(quit, 1);
      await done(tester, core);
    });

    testWidgets('right after a failed update the start installs nothing', (
      tester,
    ) async {
      final (api, core, _) = await pumpUpdates(
        tester,
        update: {
          'state': 'ready',
          'version': '9.9.9',
          'last': {
            'from': '9.9.8',
            'to': '9.9.9',
            'ok': false,
            'error': 'moving the old data aside: in use',
          },
        },
        found: const Release('9.9.9', page),
      );
      expect(api.installs, isEmpty);
      expect(Updates.installingAtStart.value, isFalse);
      expect(
        find.text(
          "The update to version 9.9.9 didn't finish, so the app went back "
          'to the previous version.',
        ),
        findsOneWidget,
      );
      await done(tester, core);
    });

    testWidgets('a version found downloads once by itself', (tester) async {
      final (api, core, _) = await pumpUpdates(
        tester,
        update: {'state': 'idle'},
      );
      Updates.found(const Release('9.9.9', page));
      await tester.pump();
      expect(api.downloads, ['9.9.9']);
      // It failed: not again until the next start.
      api.update = {
        'state': 'failed',
        'version': '9.9.9',
        'error': 'the signature does not match',
      };
      await core.refresh();
      await tester.pump();
      expect(api.downloads, ['9.9.9']);
      expect(find.text("Couldn't update to version 9.9.9."), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      await done(tester, core);
    });

    testWidgets('after an update the home page says what it did', (
      tester,
    ) async {
      final (api, core, _) = await pumpUpdates(
        tester,
        update: {
          'state': 'idle',
          'last': {'from': '9.9.8', 'to': '9.9.9', 'ok': true},
        },
      );
      expect(find.text('Updated to version 9.9.9.'), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.text('Updated to version 9.9.9.'), findsNothing);
      Updates.resultSeen.value = false;
      api.update = {
        'state': 'idle',
        'last': {
          'from': '9.9.8',
          'to': '9.9.9',
          'ok': false,
          'error': 'moving the old core aside: in use',
        },
      };
      await core.refresh();
      await tester.pump();
      expect(
        find.text(
          "The update to version 9.9.9 didn't finish, so the app went back "
          'to the previous version.',
        ),
        findsOneWidget,
      );
      await done(tester, core);
    });

    test('the status reads the update', () {
      final s = CoreStatus.fromJson({
        'update': {
          'state': 'downloading',
          'version': '1.2.3',
          'done': 25,
          'total': 100,
          'last': {'from': '1.2.2', 'to': '1.2.3', 'ok': false, 'error': 'x'},
        },
      });
      expect(s.update!.downloading, isTrue);
      expect(s.update!.progress, 0.25);
      expect(s.update!.last!.ok, isFalse);
      expect(s.update!.last!.error, 'x');
      expect(CoreStatus.fromJson({}).update, isNull);
      expect(UpdateState.fromJson({'state': 'downloading'}).progress, isNull);
    });
  });

  group('TUN mode', () {
    Future<(FakeApi, CoreController, FakeTunService)> pumpTun(
      WidgetTester tester, {
      String mode = 'clear',
      Map<String, Object?>? tun,
      TunServiceResult result = const TunServiceDone(),
      bool systemProxy = true,
      AppSettings? settings,
    }) async {
      stillMotion(tester);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = FakeApi()
        ..mode = mode
        ..systemProxySupported = systemProxy
        ..tunSupported = true
        ..tun = tun ?? {'state': 'off', 'installed': false};
      final service = FakeTunService(api, result);
      final core = CoreController(
        () async => api,
        pollInterval: const Duration(hours: 1),
        tunService: service,
      );
      await tester.pumpWidget(
        VpnApp(core: core, settings: settings ?? AppSettings()),
      );
      core.start();
      await tester.pumpAndSettle();
      return (api, core, service);
    }

    Future<void> done(WidgetTester tester, CoreController core) async {
      await tester.pumpWidget(const SizedBox());
      core.dispose();
    }

    testWidgets('is offered only where the core runs it', (tester) async {
      stillMotion(tester);
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final core = CoreController(
        () async => FakeApi(),
        pollInterval: const Duration(hours: 1),
      );
      await tester.pumpWidget(VpnApp(core: core, settings: AppSettings()));
      core.start();
      await tester.pumpAndSettle();
      expect(find.text('System proxy'), findsWidgets);
      expect(find.text('TUN'), findsNothing);
      await done(tester, core);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('installs its service on the first choice, then switches', (
      tester,
    ) async {
      final (api, core, service) = await pumpTun(tester);
      // The modes are one track (_ModeSwitch), not segmented buttons.
      expect(find.byType(SegmentedButton<String>), findsNothing);
      await tester.tap(find.text('TUN'));
      await tester.pumpAndSettle();
      expect(service.installs, 1);
      // The reason macOS' prompt shows, in the app's language.
      expect(
        service.prompt,
        'Arman VPN wants to install the service for TUN mode.',
      );
      expect(api.mode, 'tun');
      api.tun = {'state': 'on', 'installed': true};
      await core.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('All Windows traffic goes through the VPN.'),
        findsOneWidget,
      );
      // Installed: choosing it again asks for nothing.
      await tester.tap(find.text('Proxy').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('TUN'));
      await tester.pumpAndSettle();
      expect(service.installs, 1);
      expect(api.mode, 'tun');
      await done(tester, core);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    // A Linux desktop without a system proxy setting (not GNOME or KDE)
    // still has TUN mode.
    testWidgets('is offered without a system proxy setting', (tester) async {
      final (api, core, service) = await pumpTun(tester, systemProxy: false);
      expect(find.text('System proxy'), findsNothing);
      await tester.tap(find.text('TUN'));
      await tester.pumpAndSettle();
      expect(service.installs, 1);
      expect(api.mode, 'tun');
      api.tun = {'state': 'on', 'installed': true};
      await core.refresh();
      await tester.pumpAndSettle();
      expect(
        find.text('All Linux traffic goes through the VPN.'),
        findsOneWidget,
      );
      // The settings have the same choice.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connection'));
      await tester.pumpAndSettle();
      expect(find.text('Connection mode'), findsOneWidget);
      await done(tester, core);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('the settings remove the service', (tester) async {
      final (api, core, service) = await pumpTun(
        tester,
        tun: {'state': 'off', 'installed': true},
      );
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      // Out of the way: in the Advanced settings, not with TUN mode's.
      expect(find.text('TUN settings'), findsNothing);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Remove the TUN service'), findsOneWidget);
      final remove = find.widgetWithText(OutlinedButton, 'Remove');
      await tester.ensureVisible(remove);
      await tester.pumpAndSettle();
      // Asked first: Cancel keeps it.
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.removals, 0);
      await tester.tap(remove);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(service.removals, 1);
      expect(
        service.prompt,
        'Arman VPN wants to remove the service for TUN mode.',
      );
      expect(find.text('The TUN service was removed.'), findsOneWidget);
      expect(api.tun?['installed'], isFalse);
      await done(tester, core);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('the TUN settings keep the programs that skip the VPN', (
      tester,
    ) async {
      final (api, core, _) = await pumpTun(
        tester,
        mode: 'tun',
        tun: {'state': 'on', 'installed': true, 'programs_supported': true},
      );
      api.config['tun'] = {
        'programs': [
          {'name': 'steam.exe'},
        ],
      };
      final oldPick = pickProgramFile;
      addTearDown(() => pickProgramFile = oldPick);
      String? pickedTitle;
      pickProgramFile = (title, label) async {
        pickedTitle = '$title / $label';
        return r'C:\Games\Spacewar\Game.exe';
      };
      List<Object?> programs() =>
          (api.config['tun'] as Map)['programs'] as List<Object?>;

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      // After Routing.
      final routing = tester.getTopLeft(find.text('Routing')).dy;
      expect(
        tester.getTopLeft(find.text('TUN settings')).dy,
        greaterThan(routing),
      );
      await tester.tap(find.text('TUN settings'));
      await tester.pumpAndSettle();
      expect(find.text('Notice when UDP is blocked'), findsOneWidget);
      // Removing the service is in the Advanced settings, not here.
      expect(find.text('Remove the TUN service'), findsNothing);
      // A program's name reads left to right, from the left, in every
      // language.
      final steam = find.text('steam.exe');
      expect(steam, findsOneWidget);
      expect(tester.widget<Text>(steam).textDirection, TextDirection.ltr);
      expect(find.text('All traffic'), findsOneWidget);

      // Only its UDP, from the row's choice.
      await tester.tap(find.text('All traffic'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Only its UDP connects directly; the rest goes through the VPN.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('UDP only'));
      await tester.pumpAndSettle();
      expect(programs(), [
        {'name': 'steam.exe', 'udp_only': true},
      ]);

      // The three ways to add one.
      Future<void> add(String way) async {
        await tester.tap(find.text('Add program'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(way));
        await tester.pumpAndSettle();
      }

      // From the open dialog, by its file name, with its path to see.
      await add('Choose a file…');
      expect(pickedTitle, 'Add program / Programs');
      expect(programs(), [
        {'name': 'steam.exe', 'udp_only': true},
        {'name': 'Game.exe', 'path': r'C:\Games\Spacewar\Game.exe'},
      ]);
      expect(find.text(r'C:\Games\Spacewar\Game.exe'), findsOneWidget);
      // The same one again is not added twice.
      await add('Choose a file…');
      expect(programs(), hasLength(2));

      // From the running programs, found with the search; the ones in the
      // list are marked and cannot be picked.
      api.running = [
        {'name': 'steam.exe', 'path': r'C:\Games\Steam\steam.exe'},
        {
          'name': 'Telegram.exe',
          'path': r'C:\Users\u\AppData\Roaming\Telegram Desktop\Telegram.exe',
        },
        {'name': 'curl.exe', 'path': r'C:\Tools\curl.exe'},
      ];
      await add('From running programs');
      expect(find.text('curl.exe'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'tele');
      await tester.pumpAndSettle();
      expect(find.text('curl.exe'), findsNothing);
      await tester.tap(find.text('Telegram.exe'));
      await tester.pumpAndSettle();
      expect(programs().last, {
        'name': 'Telegram.exe',
        'path': r'C:\Users\u\AppData\Roaming\Telegram Desktop\Telegram.exe',
      });

      // By a name with *.
      await add('Type a name…');
      expect(
        find.text(
          "A program's file name, such as steam.exe; * stands for any text (steam* is every Steam program).",
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).last, ' steam* ');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add program'));
      await tester.pumpAndSettle();
      expect(programs().last, {'name': 'steam*'});
      expect(programs(), hasLength(4));

      for (final _ in [0, 1, 2, 3]) {
        await tester.tap(find.byTooltip('Remove').first);
        await tester.pumpAndSettle();
      }
      expect(programs(), isEmpty);
      // None running.
      api.running = [];
      await add('From running programs');
      expect(find.text('No other programs are running.'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('No programs yet.'), findsOneWidget);
      await done(tester, core);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('a refused call names the program and offers nothing else', (
      tester,
    ) async {
      final settings = AppSettings();
      final (api, core, _) = await pumpTun(
        tester,
        mode: 'tun',
        settings: settings,
        tun: {
          'state': 'on',
          'installed': true,
          'programs_supported': true,
          'refused_udp': 'Telegram.exe',
        },
      );
      final card = find.textContaining(
        "'s UDP traffic can't go through the VPN.",
      );
      expect(card, findsOneWidget);
      expect(
        tester.widget<Text>(card).data,
        startsWith("\u2066Telegram\u2069's UDP"),
      );
      // Sending it directly is chosen in the TUN settings, not with a tap here.
      expect(find.text('Send its UDP directly'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(api.config['tun'], isNull);

      // Another program, and the notice turned off.
      api.tun = {...api.tun!, 'refused_udp': 'Discord.exe'};
      await core.refresh();
      await tester.pumpAndSettle();
      expect(card, findsOneWidget);
      await tester.tap(find.text("Don't show again"));
      await tester.pumpAndSettle();
      expect(settings.udpNotice, isFalse);
      expect(card, findsNothing);

      // Nothing to offer while the TUN is off, or where programs cannot
      // skip it (macOS).
      settings.update(udpNotice: true);
      api.tun = {...api.tun!, 'state': 'starting'};
      await core.refresh();
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      api.tun = {...api.tun!, 'state': 'on', 'programs_supported': false};
      await core.refresh();
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      await done(tester, core);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('keeps the mode when Windows was not given permission', (
      tester,
    ) async {
      final (api, core, service) = await pumpTun(
        tester,
        result: const TunServiceCancelled(),
      );
      await tester.tap(find.text('TUN'));
      await tester.pumpAndSettle();
      expect(service.installs, 1);
      expect(api.mode, 'clear');
      expect(
        find.text(
          "TUN mode needs administrator permission once. It wasn't given, so the mode didn't change.",
        ),
        findsOneWidget,
      );
      await done(tester, core);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('says why it does not run, with Install where that helps', (
      tester,
    ) async {
      final (api, core, service) = await pumpTun(
        tester,
        mode: 'tun',
        tun: {'state': 'error', 'code': 'not_running', 'installed': true},
      );
      expect(
        find.text("The TUN service isn't running. Trying again…"),
        findsOneWidget,
      );
      await tester.tap(find.text('Install again'));
      await tester.pumpAndSettle();
      expect(service.installs, 1);

      for (final (code, text, button) in [
        (
          'outdated',
          'The TUN service is older than this app. Install it again to use TUN mode.',
          'Install again',
        ),
        ('missing', "The TUN service isn't installed.", 'Install'),
        (
          'app_outdated',
          'The TUN service is newer than this app. Update the app to use TUN mode.',
          null,
        ),
        ('busy', 'Another copy of Arman VPN is using TUN mode.', null),
        (
          'no_driver',
          "The system's TUN driver isn't available. Restart the computer and try again.",
          null,
        ),
        ('lost', 'TUN mode stopped unexpectedly. Trying again…', null),
        ('failed', "TUN mode couldn't start. Trying again…", null),
      ]) {
        api.tun = {'state': 'error', 'code': code, 'installed': true};
        await core.refresh();
        await tester.pumpAndSettle();
        expect(find.text(text), findsOneWidget, reason: code);
        expect(
          find.text('Install again'),
          button == 'Install again' ? findsOneWidget : findsNothing,
          reason: code,
        );
        expect(
          find.text('Install'),
          button == 'Install' ? findsOneWidget : findsNothing,
          reason: code,
        );
      }
      api.tun = {'state': 'starting', 'installed': true};
      await core.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Starting TUN mode…'), findsOneWidget);
      // Nothing to say while the proxy is off.
      api.on = false;
      await core.refresh();
      await tester.pumpAndSettle();
      expect(find.text('Starting TUN mode…'), findsNothing);
      await done(tester, core);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  });

  test('the computer uses the VPN with the system proxy or a running TUN', () {
    CoreStatus status(String mode, [String tun = 'off']) =>
        CoreStatus.fromJson({
          'state': {'phase': 'running'},
          'system_proxy': mode,
          'tun_supported': true,
          'tun': {'state': tun, 'installed': true, 'service_version': '1.2.3'},
        });
    expect(status('set').computerUsesVpn, isTrue);
    expect(status('clear').computerUsesVpn, isFalse);
    expect(status('tun').computerUsesVpn, isFalse);
    expect(status('tun', 'on').computerUsesVpn, isTrue);
    final tun = status('tun', 'on').tun!;
    expect(tun.installed, isTrue);
    expect(tun.serviceVersion, '1.2.3');
    expect(CoreStatus.fromJson({}).tun, isNull);
  });
}

/// The TUN service's program, without the system's: an install that works
/// makes the core report it installed. It notes the reason it was given for
/// macOS' prompt.
class FakeTunService implements TunService {
  FakeTunService(this.api, this.result);

  final FakeApi api;
  final TunServiceResult result;
  int installs = 0;
  int removals = 0;
  String? prompt;

  @override
  String get executable => 'arman-vpn-tun.exe';

  @override
  Future<TunServiceResult> install({String? prompt}) async {
    installs++;
    this.prompt = prompt;
    if (result is TunServiceDone) {
      api.tun = {...?api.tun, 'installed': true};
    }
    return result;
  }

  @override
  Future<TunServiceResult> uninstall({String? prompt}) async {
    removals++;
    this.prompt = prompt;
    if (result is TunServiceDone) {
      api.tun = {...?api.tun, 'installed': false};
    }
    return result;
  }
}
