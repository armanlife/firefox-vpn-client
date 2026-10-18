import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:firefox_vpn/core/core_api.dart';
import 'package:firefox_vpn/core/ports.dart';

void main() {
  test('reads and replaces ports', () {
    expect(portOf('127.0.0.1:10810'), 10810);
    expect(portOf('[::1]:10820'), 10820);
    expect(portOf('localhost'), isNull);
    expect(withPort('127.0.0.1:10810', 20000), '127.0.0.1:20000');
    expect(withPort('0.0.0.0:10810', 20000), '0.0.0.0:20000');
    expect(withPort('', 20000), '127.0.0.1:20000');
    expect(validPort(80), isFalse);
    expect(validPort(10810), isTrue);
    expect(validPort(70000), isFalse);
  });

  test('suggests a free port after a taken one', () async {
    final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(taken.close);
    expect(await isFree(taken.port), isFalse);
    final port = await findFreePort(taken.port - 1);
    expect(port, isNot(taken.port));
    expect(await isFree(port), isTrue);
  });

  group('config.json', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('ports_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('moves the API and keeps every other field', () async {
      final file = File('${dir.path}/config.json')
        ..writeAsStringSync(
          jsonEncode({
            'proxy': {'listen': '127.0.0.1:10810'},
            'dashboard': {'listen': '127.0.0.1:10820', 'enabled': true},
          }),
        );
      await CoreLocator.setDashboardListen(dir.path, '127.0.0.1:10821');
      final config = jsonDecode(file.readAsStringSync());
      expect(config['dashboard'], {
        'listen': '127.0.0.1:10821',
        'enabled': true,
      });
      expect(config['proxy'], {'listen': '127.0.0.1:10810'});
      expect(await CoreLocator.dashboardListen(dir.path), '127.0.0.1:10821');
    });

    test('creates a config when there is none', () async {
      await CoreLocator.setDashboardListen(dir.path, '127.0.0.1:10830');
      expect(await CoreLocator.dashboardListen(dir.path), '127.0.0.1:10830');
    });
  });
}
