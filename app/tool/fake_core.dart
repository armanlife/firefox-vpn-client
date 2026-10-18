// A stand-in for the core's dashboard API with made-up data, for working
// on the UI without a real core or real accounts. It never contacts the
// network.
//
//   dart run tool/fake_core.dart <data-dir> [port]
//   flutter run -d windows --dart-entrypoint-args=--data-dir=<data-dir>
//
// It writes local-api.token and config.json into <data-dir>. The sign-in
// asks for an emailed code; 123456 is accepted.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

final _random = Random();
final _started = DateTime.now().toUtc();

String _systemProxy = 'set';
final Map<String, Object?> _config = {
  'proxy': {
    'enabled': true,
    'listen': '127.0.0.1:10810',
    'transport': 'h3',
    'country': '',
    'username': '',
    'password': '',
    'idle_sleep': '15m0s',
    'allow_locked': false,
  },
  'accounts': {
    'switch_threshold_percent': 90,
    'quota_check_interval': '6h0m0s',
  },
  'dashboard': {'listen': '127.0.0.1:19090'},
  'dns': {'servers': <String>[], 'fallback_to_system': true},
  'logging': {'verbose': false},
  'routing': {
    'enabled': true,
    'region': 'ir',
    'direct': <String>[],
    'block': <String>[],
  },
  'system_proxy': {'mode': 'set'},
};
DateTime _phaseSince = _started;
String _phase = 'running';
Map<String, Object?>? _lastTest;
int _down = 1832 * 1024 * 1024;
int _up = 96 * 1024 * 1024;

final _accounts = <Map<String, Object?>>[
  _account('a1', 'alice@example.com', 18.4, active: true),
  _account('a2', 'bob@example.com', 3.1),
  _account(
    'a3',
    'carol@example.com',
    0,
    status: 'reauth_required',
    reason: 'Firefox Account sign-in required',
    reasonCode: 'signin_required',
  ),
];

final _signIns = <String, Map<String, Object?>>{};

final _locations = <Map<String, Object?>>[
  {
    'code': 'NL',
    'name': 'Netherlands',
    'city': 'Amsterdam',
    'server': 'nl-ams-001.example.net:443',
    'recommended': true,
  },
  {
    'code': 'DE',
    'name': 'Germany',
    'city': 'Frankfurt',
    'server': 'de-fra-001.example.net:443',
  },
  {
    'code': 'FR',
    'name': 'France',
    'city': 'Paris',
    'server': 'fr-par-001.example.net:443',
  },
  {
    'code': 'GB',
    'name': 'United Kingdom',
    'city': 'London',
    'server': 'gb-lon-001.example.net:443',
  },
  {
    'code': 'SE',
    'name': 'Sweden',
    'city': 'Stockholm',
    'server': 'se-sto-001.example.net:443',
  },
  {
    'code': 'US',
    'name': 'United States',
    'city': 'New York',
    'server': 'us-nyc-001.example.net:443',
  },
  {
    'code': 'JP',
    'name': 'Japan',
    'city': 'Tokyo',
    'server': 'jp-tyo-001.example.net:443',
    'locked': true,
  },
];
String? _pingedAt;

final _logs = <Map<String, Object?>>[];

void _log(String level, String message) => _logs.add({
  'id': _logs.length + 1,
  'time': DateTime.now().toUtc().toIso8601String(),
  'level': level,
  'message': message,
});

Map<String, Object?> _account(
  String id,
  String email,
  double usedGb, {
  bool active = false,
  String status = 'ready',
  String reason = '',
  String reasonCode = '',
}) {
  const limit = 50 * 1024 * 1024 * 1024;
  final used = (usedGb * 1024 * 1024 * 1024).round();
  return {
    'id': id,
    'name': email,
    'email': email,
    'enabled': true,
    'active': active,
    'status': status,
    'reason': reason,
    if (reasonCode.isNotEmpty) 'reason_code': reasonCode,
    'usage': {
      'limit_bytes': limit,
      'remaining_bytes': limit - used,
      'reset_at': DateTime.utc(2026, 11, 1).toIso8601String(),
    },
    'used_percent': used * 100 / limit,
    'has_password': true,
  };
}

List<Map<String, Object?>> _accountViews() => [
  for (var i = 0; i < _accounts.length; i++)
    {..._accounts[i], 'position': i + 1},
];

Map<String, Object?> _status() {
  if (_phase == 'starting' &&
      DateTime.now().toUtc().difference(_phaseSince).inSeconds >= 2) {
    _phase = 'running';
    _phaseSince = DateTime.now().toUtc();
  }
  final running = _phase == 'running';
  final rateDown = running ? 400000 + _random.nextInt(900000) : 0;
  final rateUp = running ? 20000 + _random.nextInt(60000) : 0;
  _down += rateDown * 2;
  _up += rateUp * 2;
  final views = _accountViews();
  final counts = <String, int>{'total': views.length};
  for (final a in views) {
    final key = a['enabled'] == true ? a['status'] as String : 'disabled';
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final active = views.where((a) => a['active'] == true).firstOrNull;
  return {
    'state': {
      'phase': _phase,
      'message': switch (_phase) {
        'running' => 'Proxy is running',
        _ => 'Getting a proxy pass',
      },
      'since': _phaseSince.toIso8601String(),
    },
    if (running)
      'proxy': {
        'listen': '127.0.0.1:10810',
        'upstream': 'nl-ams-001.example.net:443',
        'country_code': 'NL',
        'country_name': 'Netherlands',
        'city_name': 'Amsterdam',
        'selection_source': 'recommended_location',
        'transport': 'HTTP/3',
        'started_at': _phaseSince.toIso8601String(),
      },
    if (running)
      'exit': {
        'ipv4': '203.0.113.42',
        'country_code': 'NL',
        'country_name': 'Netherlands',
        'city': 'Amsterdam',
        'network': 'Example Transit B.V.',
      },
    if (running)
      'pass': {
        'proxy_pass_expires_at': DateTime.now()
            .toUtc()
            .add(const Duration(minutes: 47))
            .toIso8601String(),
        'seconds_until_expiry': 47 * 60,
      },
    'notices': [
      {
        'kind': 'port',
        'detail': '5222',
        'hosts': ['chat.example.org:5222'],
        'count': 3,
        'last': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String(),
      },
    ],
    if (running)
      'traffic': {
        'down': _down,
        'up': _up,
        'direct_down': 240 * 1024 * 1024,
        'direct_up': 12 * 1024 * 1024,
        'down_rate': rateDown,
        'up_rate': rateUp,
      },
    'last_test': ?_lastTest,
    'active_account': ?active,
    'accounts': counts,
    'switch_threshold_percent': 90,
    'version': '3.4-fake',
    'can_exit': true,
    'system_proxy': _systemProxy,
    'system_proxy_supported': true,
    'data_dir': 'C:/fake/data',
  };
}

Map<String, Object?> _runTest() {
  final tunnel = 120 + _random.nextInt(80);
  final tls = 90 + _random.nextInt(60);
  final response = 60 + _random.nextInt(60);
  return _lastTest = {
    'at': DateTime.now().toUtc().toIso8601String(),
    'ok': true,
    'target': 'https://www.google.com/generate_204',
    'http_status': 204,
    'tunnel_ms': tunnel,
    'tls_ms': tls,
    'response_ms': response,
    'first_byte_ms': tunnel + tls + response,
    'total_ms': tunnel + tls + response + 4,
    'exit_ipv4': '203.0.113.42',
    'exit_country': 'NL',
    'exit_city': 'Amsterdam',
    'exit_network': 'Example Transit B.V.',
  };
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/fake_core.dart <data-dir> [port]');
    exit(2);
  }
  final dir = Directory(args[0])..createSync(recursive: true);
  final port = args.length > 1 ? int.parse(args[1]) : 19090;
  final token = base64Url.encode(
    List.generate(24, (_) => _random.nextInt(256)),
  );
  File('${dir.path}/local-api.token').writeAsStringSync(token);
  File('${dir.path}/config.json').writeAsStringSync(
    jsonEncode({
      'dashboard': {'listen': '127.0.0.1:$port'},
    }),
  );
  _lastTest = _runTest();
  _log('INFO', 'service starting data_dir=(fake)');
  _log(
    'INFO',
    'SOCKS5 proxy started listen=127.0.0.1:10810 upstream=nl-ams-001.example.net:443 transport=h3',
  );
  _log(
    'WARN',
    'refused port 5222 (Mozilla connects to 80, 443, 8080, 8443 only)',
  );
  _log('DEBUG', 'quota checked account=a1 used=18.4GiB');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln(
    'fake core on http://127.0.0.1:$port, data dir ${dir.absolute.path}',
  );
  await for (final req in server) {
    try {
      await _handle(req, token);
    } on Object catch (e) {
      _send(req, 500, {'error': '$e'});
    }
  }
}

Future<void> _handle(HttpRequest req, String token) async {
  if (req.headers.value('X-Local-Token') != token) {
    return _send(req, 401, {'error': 'login required'});
  }
  final body = await utf8.decoder.bind(req).join();
  final input = body.isEmpty
      ? <String, Object?>{}
      : jsonDecode(body) as Map<String, Object?>;
  final path = req.uri.path;
  final m = req.method;
  final seg = req.uri.pathSegments;

  if (m == 'GET' && path == '/api/status') return _send(req, 200, _status());
  if (m == 'GET' && path == '/api/accounts') {
    return _send(req, 200, {
      'accounts': _accountViews(),
      'switch_threshold_percent': 90,
    });
  }
  if (m == 'GET' && path == '/api/settings') {
    return _send(req, 200, {'config': _config, 'data_dir': 'C:/fake/data'});
  }
  if (m == 'PUT' && path == '/api/settings') {
    _config
      ..clear()
      ..addAll(input['config'] as Map<String, Object?>);
    return _send(req, 200, {'saved': true});
  }
  if (m == 'POST' && path == '/api/system-proxy') {
    final mode = input['mode'] as String;
    if (mode != 'set' && mode != 'clear') {
      return _send(req, 400, {
        'error': 'system_proxy.mode must be set or clear',
      });
    }
    _systemProxy = mode;
    return _send(req, 200, {'mode': _systemProxy});
  }
  if (m == 'GET' && path == '/api/locations') {
    return _send(req, 200, {'locations': _locations, 'pinged_at': _pingedAt});
  }
  if (m == 'POST' && path == '/api/locations/ping') {
    await Future<void>.delayed(const Duration(seconds: 2));
    final codes = (input['codes'] as List?)?.cast<String>() ?? const [];
    for (final loc in _locations) {
      if (codes.isNotEmpty && !codes.contains(loc.code)) continue;
      if (loc['locked'] == true) {
        loc['ping_error'] = 'refused';
      } else {
        loc['ping_ms'] = 150 + _random.nextInt(900);
      }
    }
    _pingedAt = DateTime.now().toUtc().toIso8601String();
    return _send(req, 200, {
      'locations': [
        for (final loc in _locations)
          {...loc, 'error': loc['ping_error']}..remove('ping_error'),
      ],
      'pinged_at': _pingedAt,
    });
  }
  if (m == 'POST' && path == '/api/location') {
    (_config['proxy'] as Map)['country'] = input['country'];
    _log('INFO', 'location changed country=${input['country']}');
    return _send(req, 200, {'ok': true});
  }
  if (m == 'GET' && path == '/api/logs') {
    final after = int.tryParse(req.uri.queryParameters['after'] ?? '') ?? 0;
    if (_random.nextInt(3) == 0) {
      _log('DEBUG', 'tunnel opened host=www.example.com:443');
    }
    return _send(req, 200, {
      'entries': _logs.where((e) => (e['id'] as int) > after).toList(),
    });
  }
  if (m == 'GET' && path == '/api/routing') {
    return _send(req, 200, {
      'enabled': true,
      'region': 'ir',
      'active': true,
      'summary': 'geosite:ir=57554 geoip:ir=2553 geoip:private=18',
      'files': [
        {
          'name': 'geosite.dat',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        {
          'name': 'geoip.dat',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
      ],
    });
  }
  if (m == 'POST' && path == '/api/routing/test') {
    final target = input['target'] as String;
    final direct = target.endsWith('.ir');
    return _send(req, 200, {
      'host': target,
      'route': direct ? 'direct' : 'proxy',
      if (direct) 'rule': 'geosite:ir',
    });
  }
  if (m == 'POST' && path == '/api/dns/test') {
    return _send(req, 200, {
      'results': [
        for (final host in ['accounts.firefox.com', 'vpn.mozilla.org'])
          {
            'host': host,
            'addrs': ['203.0.113.10'],
            'ms': 40,
            'system_ms': 25,
          },
      ],
    });
  }
  if (m == 'POST' && path == '/api/open-folder') {
    return _send(req, 200, {'result': 'opened'});
  }
  if (m == 'POST' && path == '/api/app/exit') {
    _send(req, 200, {'exiting': true});
    exit(0);
  }
  if (m == 'POST' && path == '/api/test') {
    if (_phase != 'running') {
      return _send(req, 409, {'error': 'the proxy is not running'});
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return _send(req, 200, _runTest());
  }
  if (m == 'POST' && path == '/api/proxy/restart') {
    _phase = 'starting';
    _phaseSince = DateTime.now().toUtc();
    return _send(req, 200, {'ok': true});
  }
  if (m == 'POST' && path == '/api/accounts/order') {
    final ids = (input['ids'] as List).cast<String>();
    _accounts.sort(
      (a, b) => ids
          .indexOf(a['id'] as String)
          .compareTo(ids.indexOf(b['id'] as String)),
    );
    return _send(req, 200, {'ok': true});
  }
  if (seg.length >= 3 && seg[1] == 'accounts') {
    final acc = _accounts.where((a) => a['id'] == seg[2]).firstOrNull;
    if (acc == null) return _send(req, 404, {'error': 'unknown account'});
    final action = seg.length > 3 ? seg[3] : '';
    switch ((m, action)) {
      case ('DELETE', ''):
        _accounts.remove(acc);
      case ('POST', 'activate'):
        for (final a in _accounts) {
          a['active'] = a == acc;
        }
      case ('POST', 'enabled'):
        acc['enabled'] = input['enabled'] == true;
      case ('POST', 'refresh'):
        await Future<void>.delayed(const Duration(milliseconds: 600));
      default:
        return _send(req, 404, {'error': 'not found'});
    }
    return _send(req, 200, {'ok': true});
  }
  if (m == 'POST' && path == '/api/signin') {
    final id = 's${_signIns.length + 1}';
    var email = input['email'] as String? ?? '';
    if (input['account_id'] case final String accountId) {
      email =
          _accounts.firstWhere((a) => a['id'] == accountId)['email'] as String;
    }
    final s = _signIns[id] = {
      'id': id,
      'email': email,
      'step': 'need_email_code',
      'message': 'Mozilla sent a code to $email. Enter it here.',
    };
    return _send(req, 202, s);
  }
  if (seg.length == 3 && seg[1] == 'signin') {
    final s = _signIns[seg[2]];
    if (s == null) return _send(req, 404, {'error': 'unknown sign-in'});
    if (m == 'DELETE') {
      s['step'] = 'cancelled';
      return _send(req, 200, {'cancelled': true});
    }
    if (m == 'POST') {
      if (input['value'] != '123456') {
        s['error'] =
            'Wrong or expired code. Check the newest email and try again.';
      } else {
        s.remove('error');
        s['step'] = 'done';
        s['message'] = 'Signed in';
        final email = s['email'] as String;
        final existing = _accounts
            .where((a) => a['email'] == email)
            .firstOrNull;
        if (existing != null) {
          existing['status'] = 'ready';
          existing['reason'] = '';
        } else {
          _accounts.add(_account('a${_accounts.length + 10}', email, 0));
        }
      }
    }
    return _send(req, 200, s);
  }
  return _send(req, 404, {'error': 'not found'});
}

void _send(HttpRequest req, int status, Object body) {
  req.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  req.response.close();
}

extension on Map<String, Object?> {
  String get code => this['code'] as String;
}
