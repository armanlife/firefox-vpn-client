import 'dart:convert';
import 'dart:io';

/// The app's version, "major.minor.patch": `version` in pubspec.yaml, which
/// the build passes (scripts/build-*.ps1: --dart-define=APP_VERSION=1.1.0).
/// "0.0.0" is a development build.
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0');

/// The GitHub repository, "owner/name", for the source link and the update
/// check.
const githubRepo = 'armanlife/arman-vpn-client';

/// A newer release on GitHub.
class Release {
  const Release(this.version, this.url);

  final String version;
  final String url;
}

/// Whether "major.minor.patch" [a] is newer than [b].
bool newerVersion(String a, String b) {
  List<int> parts(String v) => [
    for (final p in v.replaceFirst(RegExp('^[vV]'), '').split('.'))
      int.tryParse(p) ?? 0,
  ];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final xi = i < x.length ? x[i] : 0, yi = i < y.length ? y[i] : 0;
    if (xi != yi) return xi > yi;
  }
  return false;
}

/// A release server used instead of GitHub, to try updates with a local
/// test release: it serves [updatesFile] at `<server>/updates.json`, answers
/// `<server>/releases/latest` as GitHub's API does, and serves the releases'
/// files, which the core downloads from it too (core/internal/update,
/// ServerEnv).
String get updateServer =>
    (Platform.environment['ARMAN_VPN_UPDATE_SERVER'] ?? '').replaceFirst(
      RegExp(r'/+$'),
      '',
    );

/// The Linux archive's name part for the processor in Dart's
/// [platformVersion] ("... on "linux_arm64"").
String linuxName(String platformVersion) =>
    'Linux-${platformVersion.contains('arm64') ? 'arm64' : 'amd64'}.tar.gz';

/// The name part of the release file that [os]'s app installs or downloads
/// (`Arman-VPN-<version>-<part>`); a release that has it was built for
/// [os]. null for another system.
String? releaseFilePart(String os) => switch (os) {
  'windows' => 'Windows-x64.zip',
  'linux' => linuxName(Platform.version),
  'macos' => 'macOS.tar.gz',
  'android' => 'Android-universal.apk',
  _ => null,
};

/// The file (`.github/updates.json` in the repository) that names, for each
/// system (`windows`, `linux`, `macos`, `android`, as
/// [Platform.operatingSystem] says), the version its app offers: a release
/// gives its version to the systems whose users should update, and the
/// others keep theirs, so a release that changes nothing for a phone is not
/// offered there.
const updatesFile = 'updates.json';

/// Reads which release this app should update to: the version that
/// [updatesFile] (GitHub's raw file of [repo]) names for [os], once that
/// release is published with [os]'s file ([releaseFilePart]); when the file
/// cannot be read (some networks block GitHub's raw files) or does not name
/// [os], the latest release on GitHub.
/// null when [current] is the newest, or when there is no release yet; an
/// error while the named release is not published yet, so the next look
/// comes soon. [proxy] ("host:port"), when set, carries the requests (the
/// VPN's own proxy, for networks where GitHub is blocked); they fall back
/// to a direct connection. [server], [os], and [current] are for tests.
Future<Release?> checkForUpdate({
  String? proxy,
  String repo = githubRepo,
  String? server,
  String? os,
  String current = appVersion,
}) async {
  final srv = server ?? updateServer;
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..findProxy = (_) =>
        proxy == null || srv.isNotEmpty ? 'DIRECT' : 'PROXY $proxy; DIRECT';
  try {
    final system = os ?? Platform.operatingSystem;
    final wanted = await _namedVersion(
      client,
      srv.isEmpty
          ? 'https://raw.githubusercontent.com/$repo/HEAD/.github/$updatesFile'
          : '$srv/$updatesFile',
      system,
    );
    if (wanted == null) return await _latestRelease(client, srv, repo, current);
    if (!newerVersion(wanted, current)) return null;
    final releases = srv.isEmpty
        ? 'https://github.com/$repo/releases'
        : '$srv/releases';
    final part = releaseFilePart(system);
    final file = part == null ? 'SHA256SUMS.txt' : 'Arman-VPN-$wanted-$part';
    if (!await _published(client, '$releases/download/v$wanted/$file')) {
      throw HttpException('version $wanted is not published yet');
    }
    return Release(wanted, '$releases/tag/v$wanted');
  } finally {
    client.close(force: true);
  }
}

/// [os]'s version in [updates], the decoded [updatesFile]:
/// "major.minor.patch", else null.
String? versionFor(Object? updates, String os) {
  final v = updates is Map<String, Object?> ? updates[os] : null;
  return v is String && RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v) ? v : null;
}

/// The version that the [updatesFile] at [url] names for [os]; null when it
/// cannot be read, is not JSON, or does not name one (whatever went wrong:
/// the latest release then decides).
Future<String?> _namedVersion(HttpClient client, String url, String os) async {
  try {
    final (status, body) = await _get(client, url);
    return status == 200 ? versionFor(jsonDecode(body), os) : null;
  } catch (_) {
    return null;
  }
}

/// The latest release on GitHub (GitHub's API), when newer than [current].
Future<Release?> _latestRelease(
  HttpClient client,
  String server,
  String repo,
  String current,
) async {
  final (status, body) = await _get(
    client,
    server.isEmpty
        ? 'https://api.github.com/repos/$repo/releases/latest'
        : '$server/releases/latest',
    accept: 'application/vnd.github+json',
  );
  // GitHub's answer for a repository without releases.
  if (status == 404) return null;
  if (status != 200) throw HttpException('HTTP $status');
  final j = jsonDecode(body);
  final tag = j is Map<String, Object?> ? j['tag_name'] as String? ?? '' : '';
  final url = j is Map<String, Object?> ? j['html_url'] as String? ?? '' : '';
  final version = tag.replaceFirst(RegExp('^[vV]'), '');
  return newerVersion(version, current) ? Release(version, url) : null;
}

/// Whether the release file at [url] is there: GitHub answers a published
/// release's file with a redirect to where it is stored, and 404 before.
Future<bool> _published(HttpClient client, String url) async {
  final req = await client
      .headUrl(Uri.parse(url))
      .timeout(const Duration(seconds: 20));
  req
    ..followRedirects = false
    ..headers.set(HttpHeaders.userAgentHeader, 'arman-vpn/$appVersion');
  final res = await req.close().timeout(const Duration(seconds: 20));
  await res.drain<void>();
  if (res.statusCode == 404) return false;
  if (res.statusCode >= 400) throw HttpException('HTTP ${res.statusCode}');
  return true;
}

/// GETs [url] with the app's headers: the status and the body.
Future<(int, String)> _get(
  HttpClient client,
  String url, {
  String accept = 'application/json',
}) async {
  final req = await client
      .getUrl(Uri.parse(url))
      .timeout(const Duration(seconds: 20));
  req.headers
    ..set(HttpHeaders.acceptHeader, accept)
    ..set(HttpHeaders.userAgentHeader, 'arman-vpn/$appVersion');
  final res = await req.close().timeout(const Duration(seconds: 20));
  final body = await res
      .transform(utf8.decoder)
      .join()
      .timeout(const Duration(seconds: 20));
  return (res.statusCode, body);
}
