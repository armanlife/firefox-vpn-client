import 'dart:convert';
import 'dart:io';

/// What installing or removing the TUN service came to.
sealed class TunServiceResult {
  const TunServiceResult();
}

class TunServiceDone extends TunServiceResult {
  const TunServiceDone();
}

/// The user declined the administrator prompt.
class TunServiceCancelled extends TunServiceResult {
  const TunServiceCancelled();
}

class TunServiceFailed extends TunServiceResult {
  const TunServiceFailed(this.error);

  /// Why, in the program's English.
  final String error;
}

/// The TUN mode's service (core/cmd/arman-vpn-tun), beside the core: its
/// install command asks for administrator rights itself (one prompt:
/// Windows', polkit's on Linux, the administrator password on macOS),
/// installs the service, and starts it; its uninstall command removes it,
/// through the running service without a prompt. The core then uses the
/// service; the app only installs it.
class TunService {
  TunService(this.executable);

  /// From the core's executable: the service is in the same folder.
  factory TunService.besideCore(String coreExecutable) => TunService(
    '${File(coreExecutable).parent.path}${Platform.pathSeparator}'
    'arman-vpn-tun${Platform.isWindows ? '.exe' : ''}',
  );

  final String executable;

  /// [prompt] is the reason macOS' administrator prompt shows, in the
  /// user's language; Windows and polkit name the program themselves.
  Future<TunServiceResult> install({String? prompt}) => _run('install', prompt);

  Future<TunServiceResult> uninstall({String? prompt}) =>
      _run('uninstall', prompt);

  /// Exit status 0 done, 3 the prompt declined, anything else failed with
  /// the reason on the standard error (core/cmd/arman-vpn-tun).
  Future<TunServiceResult> _run(String command, String? prompt) async {
    if (!File(executable).existsSync()) {
      return TunServiceFailed('$executable is missing');
    }
    try {
      final r = await Process.run(
        executable,
        [
          command,
          if (Platform.isMacOS && prompt != null) ...['-prompt', prompt],
        ],
        stderrEncoding: utf8,
        stdoutEncoding: utf8,
      );
      return switch (r.exitCode) {
        0 => const TunServiceDone(),
        3 => const TunServiceCancelled(),
        _ => TunServiceFailed(
          _firstLine(r.stderr as String? ?? '', 'exit code ${r.exitCode}'),
        ),
      };
    } on ProcessException catch (e) {
      return TunServiceFailed(e.message);
    }
  }

  static String _firstLine(String text, String fallback) {
    final line = text.trim().split('\n').first.trim();
    return line.replaceFirst(RegExp(r'^arman-vpn-tun:\s*'), '').isEmpty
        ? fallback
        : line.replaceFirst(RegExp(r'^arman-vpn-tun:\s*'), '');
  }
}
