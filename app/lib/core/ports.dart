import 'dart:io';

/// Ports the user may choose: above the privileged range.
bool validPort(int port) => port >= 1024 && port <= 65535;

/// The port of a listen address such as `127.0.0.1:10810`; null without one.
int? portOf(String listen) {
  final colon = listen.lastIndexOf(':');
  return colon < 0 ? null : int.tryParse(listen.substring(colon + 1));
}

/// [listen] with its port replaced; the host stays.
String withPort(String listen, int port) {
  final colon = listen.lastIndexOf(':');
  final host = colon < 0 ? '127.0.0.1' : listen.substring(0, colon);
  return '${host.isEmpty ? '127.0.0.1' : host}:$port';
}

/// The host and port of an address as typed or pasted: without spaces and a
/// scheme (socks5://), IPv6 without its brackets. No port is an empty one.
(String, String) splitAddress(String address) {
  var s = address.replaceAll(RegExp(r'\s'), '');
  final scheme = s.indexOf('://');
  if (scheme >= 0) s = s.substring(scheme + 3);
  if (s.endsWith('/')) s = s.substring(0, s.length - 1);
  if (s.startsWith('[')) {
    final end = s.indexOf(']');
    if (end < 0) return (s.substring(1), '');
    final rest = s.substring(end + 1);
    return (s.substring(1, end), rest.startsWith(':') ? rest.substring(1) : '');
  }
  final colon = s.indexOf(':');
  // More than one colon: IPv6, without a port.
  if (colon < 0 || colon != s.lastIndexOf(':')) return (s, '');
  return (s.substring(0, colon), s.substring(colon + 1));
}

/// The address the core takes (config.ValidateUpstreamProxy) of a host and a
/// port; empty for neither.
String joinAddress(String host, String port) {
  final h = host.replaceAll(RegExp(r'\s'), '');
  final p = port.replaceAll(RegExp(r'\s'), '');
  if (h.isEmpty && p.isEmpty) return '';
  return h.contains(':') ? '[$h]:$p' : '$h:$p';
}

/// A loopback port nothing listens on, near [after] so it is easy to
/// remember; a port from the system when none of those is free.
Future<int> findFreePort(int after) async {
  for (var port = after + 1; port <= after + 200 && port <= 65535; port++) {
    if (await isFree(port)) return port;
  }
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

/// Whether a loopback listener could take [port] now.
Future<bool> isFree(int port) async {
  try {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
    return true;
  } on SocketException {
    return false;
  }
}
