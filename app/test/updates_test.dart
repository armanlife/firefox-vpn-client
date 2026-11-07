import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:arman_vpn/app_info.dart';
import 'package:arman_vpn/core/updates.dart';

/// A release server on loopback in GitHub's place: [routes] maps
/// "METHOD /path" to a status and a body; anything else is 404.
Future<String> serve(
  Map<String, (int, String)> routes, {
  List<String>? requests,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((req) {
    requests?.add('${req.method} ${req.uri.path}');
    final (status, body) = routes['${req.method} ${req.uri.path}'] ?? (404, '');
    req.response.statusCode = status;
    if (req.method != 'HEAD') req.response.write(body);
    req.response.close();
  });
  return 'http://127.0.0.1:${server.port}';
}

void main() {
  const page = 'https://github.com/o/r/releases/tag/v1.2.3';

  test('a phone downloads the APK for its processor', () {
    expect(
      apkUrl(page, 'arm64-v8a'),
      'https://github.com/o/r/releases/download/v1.2.3/Arman-VPN-1.2.3-Android-arm64-v8a.apk',
    );
    expect(
      apkUrl(page, 'armeabi-v7a'),
      endsWith('/v1.2.3/Arman-VPN-1.2.3-Android-armeabi-v7a.apk'),
    );
    expect(apkUrl(page, 'x86_64'), endsWith('-x86_64.apk'));
  });

  test('another processor gets the universal APK', () {
    expect(
      apkUrl(page, 'x86'),
      endsWith('/Arman-VPN-1.2.3-Android-universal.apk'),
    );
    expect(
      apkUrl(page, ''),
      endsWith('/Arman-VPN-1.2.3-Android-universal.apk'),
    );
  });

  test('a computer downloads the file for its kind of copy', () {
    expect(
      releaseFileUrl(page, windowsName(installed: true)),
      'https://github.com/o/r/releases/download/v1.2.3/Arman-VPN-1.2.3-Windows-Setup-x64.exe',
    );
    expect(
      releaseFileUrl(page, windowsName(installed: false)),
      endsWith('/Arman-VPN-1.2.3-Windows-x64.zip'),
    );
    expect(linuxName('3.10.0 (stable) on "linux_arm64"'), 'Linux-arm64.tar.gz');
    expect(linuxName('3.10.0 (stable) on "linux_x64"'), 'Linux-amd64.tar.gz');
  });

  group('the update check', () {
    // 1.0.6 changed nothing for the phone, which stays at 1.0.4.
    const updates =
        '{"android": "1.0.4", "linux": "1.0.6", "windows": "1.0.6"}';
    const latest =
        '{"tag_name": "v1.0.6", "html_url": "https://example.invalid/releases/tag/v1.0.6"}';

    test('offers the version that updates.json names for the system', () async {
      final url = await serve({
        'GET /updates.json': (200, updates),
        // GitHub sends a published release's file on to its storage.
        'HEAD /releases/download/v1.0.6/Arman-VPN-1.0.6-Windows-x64.zip': (
          302,
          '',
        ),
        'HEAD /releases/download/v1.0.4/Arman-VPN-1.0.4-Android-universal.apk':
            (302, ''),
      });
      final release = await checkForUpdate(
        server: url,
        os: 'windows',
        current: '1.0.5',
      );
      expect(release?.version, '1.0.6');
      expect(release?.url, '$url/releases/tag/v1.0.6');
      final phone = await checkForUpdate(
        server: url,
        os: 'android',
        current: '1.0.3',
      );
      expect(phone?.version, '1.0.4');
    });

    test('a valid primary file takes precedence over the mirror', () async {
      final mirrorRequests = <String>[];
      final mirror = await serve({
        'GET /updates.json': (200, '{"android":"9.9.9"}'),
      }, requests: mirrorRequests);
      final primary = await serve({'GET /updates.json': (200, updates)});
      expect(
        await checkForUpdate(
          server: primary,
          updatesMirror: '$mirror/updates.json',
          os: 'android',
          current: '1.0.4',
        ),
        isNull,
      );
      expect(mirrorRequests, isEmpty);
    });

    test('the mirror supplies metadata when the primary is unusable', () async {
      for (final response in [
        (503, ''),
        (200, 'not JSON'),
        (200, '{"windows":"invalid"}'),
        (200, '{"android":"1.0.4"}'),
      ]) {
        final primaryRequests = <String>[];
        final mirrorRequests = <String>[];
        final primary = await serve({
          'GET /updates.json': response,
          'HEAD /releases/download/v1.0.6/Arman-VPN-1.0.6-Windows-x64.zip': (
            302,
            '',
          ),
        }, requests: primaryRequests);
        final mirror = await serve({
          'GET /updates.json': (200, updates),
        }, requests: mirrorRequests);
        final release = await checkForUpdate(
          server: primary,
          updatesMirror: '$mirror/updates.json',
          os: 'windows',
          current: '1.0.5',
        );
        expect(release?.version, '1.0.6', reason: '$response');
        expect(release?.url, '$primary/releases/tag/v1.0.6');
        expect(primaryRequests, [
          'GET /updates.json',
          'HEAD /releases/download/v1.0.6/Arman-VPN-1.0.6-Windows-x64.zip',
        ]);
        expect(mirrorRequests, ['GET /updates.json']);
      }
    });

    test('an unreachable primary uses the mirror', () async {
      final mirror = await serve({'GET /updates.json': (200, updates)});
      final unavailable = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final primary = 'http://127.0.0.1:${unavailable.port}';
      await unavailable.close(force: true);
      expect(
        await checkForUpdate(
          server: primary,
          updatesMirror: '$mirror/updates.json',
          os: 'android',
          current: '1.0.4',
        ),
        isNull,
      );
    });

    test(
      'an unusable primary and mirror fall back to the release API',
      () async {
        final requests = <String>[];
        final primary = await serve({
          'GET /updates.json': (503, ''),
          'GET /releases/latest': (200, latest),
        }, requests: requests);
        final mirror = await serve({'GET /updates.json': (200, 'not JSON')});
        final release = await checkForUpdate(
          server: primary,
          updatesMirror: '$mirror/updates.json',
          os: 'macos',
          current: '1.0.4',
        );
        expect(release?.version, '1.0.6');
        expect(requests, ['GET /updates.json', 'GET /releases/latest']);
      },
    );

    test(
      'a mirrored version still requires its published release file',
      () async {
        final primary = await serve({'GET /updates.json': (503, '')});
        final mirror = await serve({'GET /updates.json': (200, updates)});
        await expectLater(
          checkForUpdate(
            server: primary,
            updatesMirror: '$mirror/updates.json',
            os: 'windows',
            current: '1.0.5',
          ),
          throwsA(isA<HttpException>()),
        );
      },
    );

    test('a phone is not offered a release made for the computers', () async {
      final url = await serve({
        'GET /updates.json': (200, updates),
        // The latest release, which must not be asked for.
        'GET /releases/latest': (200, latest),
      });
      expect(
        await checkForUpdate(server: url, os: 'android', current: '1.0.4'),
        isNull,
      );
    });

    test('a version not published yet is an error, so the app looks again '
        'soon', () async {
      final url = await serve({'GET /updates.json': (200, updates)});
      await expectLater(
        checkForUpdate(server: url, os: 'linux', current: '1.0.5'),
        throwsA(isA<HttpException>()),
      );
    });

    test('a release without the system\'s file is not offered', () async {
      final url = await serve({
        'GET /updates.json': (200, updates),
        // Published, but built without Windows (PLATFORMS).
        'HEAD /releases/download/v1.0.6/SHA256SUMS.txt': (302, ''),
      });
      await expectLater(
        checkForUpdate(server: url, os: 'windows', current: '1.0.5'),
        throwsA(isA<HttpException>()),
      );
    });

    test('without updates.json, or without the system in it, the latest '
        'release decides', () async {
      for (final file in [
        null,
        'not JSON',
        '{"windows": "1.0.6"}',
        '{"macos": "v1.0.6"}',
      ]) {
        final url = await serve({
          if (file != null) 'GET /updates.json': (200, file),
          'GET /releases/latest': (200, latest),
        });
        final release = await checkForUpdate(
          server: url,
          os: 'macos',
          current: '1.0.4',
        );
        expect(release?.version, '1.0.6', reason: '$file');
        expect(release?.url, 'https://example.invalid/releases/tag/v1.0.6');
      }
    });

    test('updates.json names versions only', () {
      expect(versionFor({'linux': '1.2.3'}, 'linux'), '1.2.3');
      expect(versionFor({'linux': 'v1.2.3'}, 'linux'), isNull);
      expect(versionFor({'linux': 123}, 'linux'), isNull);
      expect(versionFor({'linux': '1.2.3'}, 'android'), isNull);
      expect(versionFor(['1.2.3'], 'linux'), isNull);
    });
  });
}
