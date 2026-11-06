import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart' as wf;
import 'package:webview_windows/webview_windows.dart' as ww;

import '../app_settings.dart';
import '../core/android_core.dart';
import '../core/core_api.dart';
import '../core/core_controller.dart';
import '../desktop/desktop_bridge.dart';
import '../l10n/app_localizations.dart';
import 'signin_dialog.dart';
import 'widgets.dart';

/// Whether this platform has the in-app browser for the browser sign-in
/// (WebView2 on Windows, the system WebView on Android, WKWebView on
/// macOS).
bool get browserSignInSupported =>
    Platform.isWindows || Platform.isAndroid || Platform.isMacOS;

/// The Windows browser views share one WebView2 environment, made once per
/// run of the app with the sign-in proxy it is given then; the core is
/// asked for that proxy's port again each time ([CoreApi.openSignInProxy]).
bool _windowsEnvironmentReady = false;
int _windowsProxyPort = 0;

/// Adds an account the way the settings say: through the browser page
/// where that works, else with the email and password form.
Future<void> startAddAccount(
  BuildContext context,
  CoreController core,
  AppSettings settings, {
  String email = '',
}) async {
  if (settings.signInMethod == SignInMethod.browser && browserSignInSupported) {
    await _openBrowserSignIn(
      Navigator.of(context, rootNavigator: true),
      core,
      email,
    );
  } else {
    await showSignInDialog(context, core, email: email);
  }
}

Future<void> _openBrowserSignIn(
  NavigatorState navigator,
  CoreController core,
  String email,
) => navigator.push<void>(
  MaterialPageRoute(
    builder: (_) => BrowserSignInPage(core: core, email: email),
  ),
);

/// The sign-in page Firefox desktop opens for sync: with these parameters
/// accounts.firefox.com reports the signed-in session over its WebChannel
/// (the fxaccounts:login message), which carries the session token the
/// core exchanges for the account's tokens.
String _loginUrl(String email) => Uri.https('accounts.firefox.com', '/', {
  'context': 'fx_desktop_v3',
  'service': 'sync',
  'action': 'email',
  if (email.isNotEmpty) 'email': email,
}).toString();

/// A Firefox user agent: accounts.firefox.com only speaks its WebChannel
/// to what looks like Firefox.
String get _userAgent => Platform.isAndroid
    ? 'Mozilla/5.0 (Android 14; Mobile; rv:145.0) Gecko/145.0 Firefox/145.0'
    : Platform.isMacOS
    ? 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:145.0) '
          'Gecko/20100101 Firefox/145.0'
    : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:145.0) '
          'Gecko/20100101 Firefox/145.0';

/// Sends this app's web views (Android's WebView, macOS's WKWebView)
/// through the proxy at [address], or straight out again when it is null.
/// False when the system's web view cannot take a proxy: the view then
/// connects by itself.
Future<bool> _setViewProxy(String? address) async {
  try {
    return Platform.isAndroid
        ? await AndroidCore.setWebViewProxy(address)
        : await DesktopBridge.setWebViewProxy(address);
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

/// Follows the WebChannel of accounts.firefox.com, as Firefox desktop
/// would: answers the page's status questions, and reports the session the
/// page signs in with.
///
/// [reply] runs JavaScript in the page; [onSession] gets the account's
/// email and session token from the page's `fxaccounts:login` message. The
/// page sends it right after the password, before any code the sign-in
/// asks for (by email, or from an authenticator) is entered there: the
/// core waits until Mozilla reports the session confirmed, and the page
/// stays open for the code meanwhile.
class FxaWebChannel {
  FxaWebChannel({required this.reply, required this.onSession});

  final void Function(String js) reply;
  final void Function(String email, String sessionToken) onSession;

  String _token = '';

  static final _tokenPattern = RegExp(r'^[0-9a-f]{64}$');

  /// The JavaScript injected into every page of the sign-in. It forwards
  /// the page's WebChannel messages to [handle]; [post] is a statement
  /// sending its argument `o` (an object) to Dart. It defines
  /// `window.__armanReply` for [reply].
  static String hookJs(String post) =>
      '''
(function () {
  if (window.__armanHooked) return;
  window.__armanHooked = true;
  var send = function (o) { try { $post } catch (e) {} };
  var onChannel = function (e) {
    var d = e.detail;
    if (typeof d === 'string') { try { d = JSON.parse(d); } catch (e) { return; } }
    if (d && d.message) send({ kind: 'webchannel', detail: d });
  };
  window.addEventListener('WebChannelMessageToChrome', onChannel);
  document.addEventListener('WebChannelMessageToChrome', onChannel);
  window.__armanReply = function (id, messageId, command, data) {
    var detail = { id: id, message: { messageId: messageId, command: command, data: data } };
    window.dispatchEvent(new CustomEvent('WebChannelMessageToContent', { detail: detail }));
    document.dispatchEvent(new CustomEvent('WebChannelMessageToContent', { detail: detail }));
  };
})();
''';

  /// A message from the injected JavaScript: a JSON string (webview_flutter's
  /// channel) or an already decoded map (WebView2's web messages).
  void handle(Object? raw) {
    Object? m = raw;
    if (m is String) {
      try {
        m = jsonDecode(m);
      } on FormatException {
        return;
      }
    }
    if (m is! Map || m['kind'] != 'webchannel') return;
    _webchannel(m['detail']);
  }

  void _webchannel(Object? detail) {
    if (detail is! Map) return;
    final id = detail['id'];
    final message = detail['message'];
    if (id is! String || message is! Map) return;
    final command = message['command'];
    final messageId = message['messageId'];
    switch (command) {
      // What the page asks its browser before the sign-in: no user is
      // signed in, and linking this account is fine.
      case 'fxaccounts:fxa_status':
        _reply(id, messageId, command as String, {
          'capabilities': <String, Object?>{},
          'signedInUser': null,
        });
      case 'fxaccounts:can_link_account':
        _reply(id, messageId, command as String, {'ok': true});
      case 'fxaccounts:login' || 'fxaccounts:oauth_login':
        _login(message['data']);
    }
  }

  void _reply(String id, Object? messageId, String command, Object data) =>
      reply(
        'window.__armanReply(${jsonEncode(id)}, ${jsonEncode(messageId)}, '
        '${jsonEncode(command)}, ${jsonEncode(data)})',
      );

  /// A session, once: the page may repeat its message (once confirmed, for
  /// one). A different session means the person signed in again in the
  /// page, and replaces the first.
  void _login(Object? data) {
    if (data is! Map) return;
    final token = data['sessionToken'] ?? data['token'];
    if (token is! String || !_tokenPattern.hasMatch(token)) return;
    if (token == _token) return;
    _token = token;
    final email = data['email'];
    onSession(email is String ? email : '', token);
  }
}

/// Signs an account in inside the app's browser view: the person uses
/// Mozilla's own page, and the captured session goes to the core.
class BrowserSignInPage extends StatefulWidget {
  const BrowserSignInPage({super.key, required this.core, this.email = ''});

  final CoreController core;
  final String email;

  @override
  State<BrowserSignInPage> createState() => _BrowserSignInPageState();
}

class _BrowserSignInPageState extends State<BrowserSignInPage> {
  late final FxaWebChannel _channel = FxaWebChannel(
    reply: _runJs,
    onSession: _gotSession,
  );

  ww.WebviewController? _windows;
  StreamSubscription<Object?>? _messages;
  // Android and macOS: webview_flutter's view.
  wf.WebViewController? _view;
  String? _error;
  bool _loading = true;
  // The core's sign-in that follows the page's session, and the timer
  // asking for its state.
  String? _signIn;
  Timer? _follow;
  bool _reading = false;
  // Whether this page opened the core's sign-in proxy, and set it as the
  // web view's proxy (Android, macOS): both are undone when it closes.
  bool _proxyOpen = false;
  bool _viewProxySet = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    // Closed before the core finished: that sign-in ends too.
    _stopFollowing(cancel: true);
    _messages?.cancel();
    _windows?.dispose();
    if (_viewProxySet) _setViewProxy(null).ignore();
    if (_proxyOpen) widget.core.api?.closeSignInProxy().ignore();
    super.dispose();
  }

  Future<void> _init() async {
    final proxy = await _openProxy();
    try {
      if (Platform.isWindows) {
        await _initWindows(proxy);
      } else {
        await _initView(proxy);
      }
    } on Exception catch (e) {
      // No WebView2 runtime, or the webview failed to start.
      if (mounted) setState(() => _error = '$e');
    }
  }

  /// The core's sign-in proxy: the view reaches Mozilla's pages through
  /// it, which connects the way the core's own account requests do (every
  /// address of a name, its DNS servers), with no account and the VPN off.
  /// Alone, the view takes the one address the system's DNS gives, which
  /// some networks do not let through. Null when the core cannot open it:
  /// the view then connects by itself.
  Future<String?> _openProxy() async {
    final api = widget.core.api;
    if (api == null) return null;
    try {
      final address = await api.openSignInProxy(port: _windowsProxyPort);
      if (!mounted) {
        // Closed meanwhile: dispose did not know to close it.
        api.closeSignInProxy().ignore();
        return null;
      }
      _proxyOpen = true;
      return address;
    } on Exception {
      return null;
    }
  }

  Future<void> _initWindows(String? proxy) async {
    if (!_windowsEnvironmentReady) {
      _windowsEnvironmentReady = true;
      try {
        await ww.WebviewController.initializeEnvironment(
          additionalArguments: proxy == null ? null : '--proxy-server=$proxy',
        );
        if (proxy != null) {
          _windowsProxyPort =
              int.tryParse(proxy.substring(proxy.lastIndexOf(':') + 1)) ?? 0;
        }
      } on PlatformException {
        // Made already (a hot restart): it keeps what it was made with.
      }
    }
    final c = ww.WebviewController();
    await c.initialize();
    await c.setBackgroundColor(Colors.white);
    await c.setPopupWindowPolicy(ww.WebviewPopupWindowPolicy.sameWindow);
    await c.setUserAgent(_userAgent);
    await c.addScriptToExecuteOnDocumentCreated(
      FxaWebChannel.hookJs('window.chrome.webview.postMessage(o);'),
    );
    _messages = c.webMessage.listen(_channel.handle);
    c.loadingState.listen((s) {
      if (mounted && s == ww.LoadingState.navigationCompleted) {
        setState(() => _loading = false);
      }
    });
    await c.loadUrl(_loginUrl(widget.email));
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _windows = c);
  }

  Future<void> _initView(String? proxy) async {
    // Set before the first page loads: the override applies to the
    // requests that start after it.
    if (proxy != null) {
      final set = await _setViewProxy(proxy);
      if (!mounted) {
        if (set) _setViewProxy(null).ignore();
        return;
      }
      _viewProxySet = set;
    }
    final hook = FxaWebChannel.hookJs(
      'ArmanFxa.postMessage(JSON.stringify(o));',
    );
    late final wf.WebViewController c;
    c = wf.WebViewController()
      ..setJavaScriptMode(wf.JavaScriptMode.unrestricted)
      ..setUserAgent(_userAgent)
      ..addJavaScriptChannel(
        'ArmanFxa',
        onMessageReceived: (m) => _channel.handle(m.message),
      )
      ..setNavigationDelegate(
        wf.NavigationDelegate(
          // Injected twice: early, and again for pages whose start was
          // missed; the hook installs itself only once.
          onPageStarted: (_) => c.runJavaScript(hook),
          onPageFinished: (_) {
            c.runJavaScript(hook);
            if (mounted) setState(() => _loading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(_loginUrl(widget.email)));
    setState(() => _view = c);
  }

  void _runJs(String js) {
    _windows?.executeScript(js);
    _view?.runJavaScript(js);
  }

  /// The page signed in with a session: the core follows it from here. It
  /// waits until Mozilla reports the session confirmed, while the page
  /// stays open for any code the sign-in asks for, then adds the account.
  /// The page closes once the core is done, into the dialog the form uses
  /// for its result.
  Future<void> _gotSession(String email, String sessionToken) async {
    final api = widget.core.api;
    final address = email.isNotEmpty ? email : widget.email;
    if (api == null || address.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).signInFailed);
      return;
    }
    // Signed in again in the page: the earlier session is not followed.
    _stopFollowing(cancel: true);
    try {
      final started = await api.startBrowserSignIn(address, sessionToken);
      if (!mounted) {
        api.cancelSignIn(started.id).ignore();
        return;
      }
      _signIn = started.id;
      _follow = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _read(api, started.id),
      );
    } on CoreApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on CoreUnavailable catch (e) {
      if (mounted) {
        setState(
          () => _error = describeProblem(AppLocalizations.of(context), e),
        );
      }
    }
  }

  Future<void> _read(CoreApi api, String id) async {
    if (_reading) return;
    _reading = true;
    try {
      final state = await api.signInState(id);
      if (!mounted || id != _signIn || !state.finished) return;
      _stopFollowing(cancel: false);
      final navigator = Navigator.of(context);
      final page = ModalRoute.of(context);
      final core = widget.core;
      // The dialog opens over the page below this one.
      navigator.pop();
      await showSignInDialog(
        navigator.context,
        core,
        started: state,
        onBrowserRetry: () async {
          // Let the previous page release its WebView and proxy first.
          await page?.completed;
          if (navigator.mounted) {
            await _openBrowserSignIn(navigator, core, state.email);
          }
        },
      );
    } on Exception {
      // Asked again on the next tick.
    } finally {
      _reading = false;
    }
  }

  void _stopFollowing({required bool cancel}) {
    _follow?.cancel();
    _follow = null;
    final id = _signIn;
    _signIn = null;
    if (cancel && id != null) widget.core.api?.cancelSignIn(id).ignore();
  }

  /// Falls back to the email and password form.
  void _useForm() {
    final core = widget.core;
    final email = widget.email;
    final navigator = Navigator.of(context);
    navigator.pop();
    showSignInDialog(navigator.context, core, email: email);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final view = _windows != null
        ? ww.Webview(_windows!)
        : _view != null
        ? wf.WebViewWidget(controller: _view!)
        : null;
    return Scaffold(
      // No way to the form up here: two sign-in offers at once mislead.
      // The form stays only on the error screen, for when the browser
      // view itself cannot run.
      appBar: AppBar(title: Text(l.signInMethodBrowser)),
      body: _error != null
          ? _Problem(message: _error!, onUseForm: _useForm)
          : Stack(
              children: [
                if (view != null) Positioned.fill(child: view),
                if (_loading || view == null)
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(),
                  ),
              ],
            ),
    );
  }
}

/// The browser view failed: what went wrong, and the form as the way out.
class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onUseForm});

  final String message;
  final VoidCallback onUseForm;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.public_off_rounded,
                size: 40,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(l.browserSignInBroken, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onUseForm,
                child: Text(l.browserSignInFallback),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
