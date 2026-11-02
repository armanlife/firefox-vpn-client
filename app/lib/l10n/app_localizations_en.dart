// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Firefox VPN';

  @override
  String get navOverview => 'Overview';

  @override
  String get navAccounts => 'Accounts';

  @override
  String get navSettings => 'Settings';

  @override
  String get stateConnected => 'Connected';

  @override
  String get stateConnecting => 'Connecting…';

  @override
  String get stateWaiting => 'Waiting';

  @override
  String get waitingForAccount =>
      'Add a Firefox Account on the Accounts page to connect.';

  @override
  String get waitingForEnabledAccount =>
      'All accounts are turned off. Turn one on in Accounts.';

  @override
  String get stateError => 'Error';

  @override
  String get stateUnknown => 'Unknown';

  @override
  String get restartProxy => 'Restart the proxy';

  @override
  String copied(String value) {
    return 'Copied $value';
  }

  @override
  String get activeAccount => 'Active account';

  @override
  String get noActiveAccount => 'No active account';

  @override
  String get quotaNotRead => 'Quota not read yet';

  @override
  String get unlimited => 'Unlimited';

  @override
  String usedOf(String used, String limit) {
    return '$used of $limit used';
  }

  @override
  String resets(String date) {
    return 'resets $date';
  }

  @override
  String switchAt(int percent) {
    return 'Switches account at $percent%';
  }

  @override
  String get publicIp => 'Public IP';

  @override
  String get testConnection => 'Test connection';

  @override
  String get testing => 'Testing…';

  @override
  String get testFailed => 'Failed';

  @override
  String milliseconds(int value) {
    return '$value ms';
  }

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String hoursAgo(int n) {
    return '$n h ago';
  }

  @override
  String daysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String atTime(String time) {
    return 'at $time';
  }

  @override
  String durationDays(int d, int h) {
    return '${d}d ${h}h';
  }

  @override
  String durationHours(int h, int m) {
    return '${h}h ${m}m';
  }

  @override
  String durationMinutes(int m, int s) {
    return '${m}m ${s}s';
  }

  @override
  String durationSeconds(int s) {
    return '${s}s';
  }

  @override
  String accountsGuide(String size) {
    return 'Each Firefox Account has $size of data a month. You can add several: when one runs out, the app moves to the next one by itself.';
  }

  @override
  String accountsOrderNote(int percent) {
    return 'In the order of this list: each up to $percent%, the last one until its data runs out.';
  }

  @override
  String get addAccount => 'Add account';

  @override
  String lowQuotaNotice(String size) {
    return 'This account is running out of data. Add another account to get $size more.';
  }

  @override
  String get noAccounts => 'No accounts yet';

  @override
  String get noAccountsHint => 'Add a Firefox Account to connect.';

  @override
  String get delayTestFailed =>
      'Couldn\'t measure the servers\' delay. Check your internet.';

  @override
  String get createAccountTitle => 'Don\'t have a Firefox Account?';

  @override
  String get createAccountHint =>
      'Create one for free at accounts.firefox.com, then come back and press Add account.';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get statusActive => 'Active';

  @override
  String get statusReady => 'Ready';

  @override
  String get statusNeedsSignIn => 'Needs sign-in';

  @override
  String get statusReserved => 'Reserved';

  @override
  String get statusUnavailable => 'Unavailable';

  @override
  String statusUnavailableUntil(String date) {
    return 'Unavailable until $date';
  }

  @override
  String get statusDisabled => 'Disabled';

  @override
  String get statusEnabled => 'Enabled';

  @override
  String get useNow => 'Use now';

  @override
  String get signInAgain => 'Sign in again';

  @override
  String reasonQuotaThreshold(int percent) {
    return 'Used $percent% of its data, so the next account took over.';
  }

  @override
  String get reasonQuotaExhausted =>
      'This month\'s data is used up; it is used again after the monthly reset.';

  @override
  String get reasonSignInRequired => 'Sign in again to use this account.';

  @override
  String get reasonSignInConfirm =>
      'Mozilla asks to confirm the sign-in: press Sign in again (only the code is needed).';

  @override
  String reasonSignInFailed(String detail) {
    return 'Automatic sign-in failed ($detail). Sign in again.';
  }

  @override
  String reasonSignInWait(String time) {
    return 'The last automatic sign-in stopped working soon after; the next try is at $time.';
  }

  @override
  String reasonSignInRetry(String detail, String time) {
    return 'Automatic sign-in could not finish ($detail); trying again at $time.';
  }

  @override
  String get reasonNotEntitled =>
      'Mozilla refused this account; trying again later.';

  @override
  String get more => 'More';

  @override
  String get refreshQuota => 'Refresh quota';

  @override
  String get remove => 'Remove';

  @override
  String get removeTitle => 'Remove account?';

  @override
  String removeBody(String name) {
    return '$name and its saved sign-in will be removed from this computer. You can add it again later.';
  }

  @override
  String get unlimitedQuota => 'Unlimited quota';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signInIntro => 'Sign in with a Firefox Account.';

  @override
  String get email => 'Email';

  @override
  String get emailInvalid => 'Enter the account email';

  @override
  String get password => 'Password';

  @override
  String get passwordEmpty => 'Enter the password';

  @override
  String get show => 'Show';

  @override
  String get hide => 'Hide';

  @override
  String get signIn => 'Sign in';

  @override
  String get continueLabel => 'Continue';

  @override
  String get done => 'Done';

  @override
  String get close => 'Close';

  @override
  String get noBrowserTitle => 'No browser on this device';

  @override
  String get noBrowserText => 'Open this address on your phone or computer:';

  @override
  String get cancel => 'Cancel';

  @override
  String get tryAgain => 'Try again';

  @override
  String get signingIn => 'Signing in…';

  @override
  String get accountReady => 'Account ready';

  @override
  String get accountReadyHint => 'It joined the end of the account order.';

  @override
  String get captchaLabel => 'Characters in the image';

  @override
  String get codeLabel => 'Code';

  @override
  String get captchaBroken => 'The CAPTCHA image could not be shown.';

  @override
  String stepEmailCode(String email) {
    return 'Mozilla emailed a code to $email. Enter it here.';
  }

  @override
  String get stepTotp => 'Enter the code from your authenticator app.';

  @override
  String stepUnblockCode(String email) {
    return 'Mozilla finds this sign-in unusual and emailed an unblock code to $email. Enter it here.';
  }

  @override
  String get stepCaptcha => 'Type the characters in the image.';

  @override
  String stepEmailLink(String email) {
    return 'Open the confirmation link Mozilla emailed to $email. This continues by itself.';
  }

  @override
  String get signInFailed => 'The account was not added.';

  @override
  String get signInCancelled => 'Sign-in cancelled.';

  @override
  String get signInNoAccount => 'No Firefox Account exists for this email.';

  @override
  String get signInNoAccountHint =>
      'Check the email, or create a free Firefox Account with it on Mozilla\'s site, confirm it from your inbox, then add it here.';

  @override
  String get createAccountButton => 'Create a Firefox Account';

  @override
  String get signInWrongPassword => 'Incorrect password.';

  @override
  String get signInNoPassword =>
      'This account has no password: it was made with Google or Apple sign-in. Set a password, then sign in here with it.';

  @override
  String get setPasswordButton => 'Set a password';

  @override
  String get signInTooManyAttempts =>
      'Too many attempts. Wait a while and try again.';

  @override
  String get signInUnblockRejected =>
      'The unblock code was not accepted. Use the code from the latest email from Mozilla.';

  @override
  String get signInWrongCode =>
      'Wrong or expired code. Use the code from the latest email from Mozilla; an older code stops working when a new one is sent.';

  @override
  String get signInWrongTotp =>
      'Wrong code. Enter the code the authenticator app shows now.';

  @override
  String get signInTooManyCodes =>
      'Too many wrong codes. Start the sign-in again.';

  @override
  String get signInTimedOut => 'The sign-in took too long. Start it again.';

  @override
  String get signInNetwork =>
      'Mozilla could not be reached. Check your internet and try again.';

  @override
  String get coreConnecting => 'Connecting to the core…';

  @override
  String get coreLost => 'Lost the connection to the core. Retrying…';

  @override
  String get cantReachCore => 'Can\'t reach the core';

  @override
  String get startingCore => 'Starting the core…';

  @override
  String get retry => 'Retry';

  @override
  String errNoCore(String path) {
    return 'The core program was not found next to the app ($path).';
  }

  @override
  String errCoreExited(String detail) {
    return 'The core stopped: $detail';
  }

  @override
  String get errNotAnswering => 'The core is not answering.';

  @override
  String get errRefused =>
      'The core refused the app; it may belong to another copy.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionGeneral => 'General';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get closeBehavior => 'When closing the window';

  @override
  String get closeAsk => 'Ask every time';

  @override
  String get closeTray => 'Minimize to the tray';

  @override
  String get closeQuit => 'Quit the app';

  @override
  String get sectionConnection => 'Connection';

  @override
  String get localProxy => 'Local proxy';

  @override
  String get systemProxy => 'System proxy';

  @override
  String get sectionRouting => 'Routing';

  @override
  String get routingDirect => 'Direct connection for local sites';

  @override
  String get routingDirectHint =>
      'Sites and IPs of the chosen country skip the VPN: they open faster and save quota.';

  @override
  String get region => 'Country';

  @override
  String get regionIr => 'Iran';

  @override
  String get regionCn => 'China';

  @override
  String get regionRu => 'Russia';

  @override
  String get regionAf => 'Afghanistan';

  @override
  String get regionTr => 'Turkey';

  @override
  String get regionId => 'Indonesia';

  @override
  String get regionBr => 'Brazil';

  @override
  String get regionNone => 'None';

  @override
  String get saved => 'Saved';

  @override
  String get dataFolder => 'Data folder';

  @override
  String get openFolder => 'Open folder';

  @override
  String get unofficialNote =>
      'Unofficial client. Not affiliated with Mozilla.';

  @override
  String get closeTitle => 'Close the window?';

  @override
  String get closeBody =>
      'In the tray, the VPN stays connected. Quitting turns it off.';

  @override
  String get rememberChoice => 'Remember my choice';

  @override
  String get minimizeToTray => 'Minimize to tray';

  @override
  String get quit => 'Quit';

  @override
  String get trayOpen => 'Open';

  @override
  String get trayQuit => 'Quit';

  @override
  String get trayProxyOnly => 'Proxy service only';

  @override
  String get traySetSystemProxy => 'Set system proxy';

  @override
  String errPortInUse(String port) {
    return 'Port $port is used by another program, so the app cannot reach its core.';
  }

  @override
  String proxyPortInUse(String port) {
    return 'Port $port is used by another program, so the proxy cannot start.';
  }

  @override
  String get changePort => 'Change port';

  @override
  String get portDialogTitle => 'Choose a port';

  @override
  String portDialogBody(String port) {
    return 'Port $port is taken. A free port is suggested below; you can type another one.';
  }

  @override
  String get portChangeBody =>
      'Apps connect to this port. Choose one from 1024 to 65535.';

  @override
  String get portLabel => 'Port';

  @override
  String get portInvalid => 'Enter a port from 1024 to 65535';

  @override
  String get portBusy => 'This port is in use too';

  @override
  String get portInUse => 'Another program uses this port';

  @override
  String get save => 'Save';

  @override
  String get proxyPort => 'Proxy port';

  @override
  String get appPort => 'App port';

  @override
  String get welcomeTitle => 'Welcome';

  @override
  String get welcomeBody =>
      'Choose your language and your country. Sites of your country open directly, without the VPN, which is faster and saves quota.';

  @override
  String get start => 'Start';

  @override
  String routingSuggestTitle(String country) {
    return 'Route $country directly?';
  }

  @override
  String routingSuggestBody(String country) {
    return 'Sites and IPs of $country would open directly, without the VPN. You can change this in Routing.';
  }

  @override
  String get yes => 'Yes';

  @override
  String get notNow => 'Not now';

  @override
  String get navServers => 'Servers';

  @override
  String get navLogs => 'Logs';

  @override
  String get realDelay => 'Real delay';

  @override
  String noticePort(String port) {
    return 'Mozilla\'s proxy does not connect to port $port. Only ports 80, 443, 8080 and 8443 go through the VPN.';
  }

  @override
  String get noticeCommand =>
      'This type of connection isn\'t supported by the VPN.';

  @override
  String noticeTimes(int count, String time) {
    return '$count times, last $time';
  }

  @override
  String get dismiss => 'Dismiss';

  @override
  String get modeRecommended => 'Recommended';

  @override
  String get modeFastest => 'Fastest';

  @override
  String get modeRecommendedHint => 'Mozilla picks the location for you.';

  @override
  String get modeFastestHint =>
      'The location with the lowest delay at each connection.';

  @override
  String get testDelay => 'Test real delay';

  @override
  String get testingDelay => 'Testing… this can take a minute';

  @override
  String get search => 'Search';

  @override
  String get noAnswer => 'No answer';

  @override
  String testedAgo(String ago) {
    return 'Tested $ago';
  }

  @override
  String delaySummary(int answered, int total) {
    return '$answered of $total answered';
  }

  @override
  String get noServers =>
      'No servers yet. They appear once the core reaches Mozilla.';

  @override
  String get levelAll => 'All';

  @override
  String get filter => 'Filter';

  @override
  String get follow => 'Auto-scroll';

  @override
  String get clear => 'Clear';

  @override
  String get copyAll => 'Copy';

  @override
  String get logsCopied => 'Logs copied';

  @override
  String get noLogs => 'No log lines yet.';

  @override
  String get sectionAccounts => 'Account switching';

  @override
  String get switchThreshold => 'Switch account at';

  @override
  String get switchThresholdHint =>
      'The next account takes over when this share of the quota is used.';

  @override
  String get sectionDns => 'DNS';

  @override
  String get dnsPreset => 'DNS servers';

  @override
  String get dnsSystem => 'System';

  @override
  String get dnsAuto => 'Auto (Cloudflare, Google, Quad9)';

  @override
  String get dnsCustom => 'Custom';

  @override
  String get dnsCustomHint =>
      'One per line: https://…/dns-query, tls://…, or an IP address.';

  @override
  String get dnsFallback => 'Fall back to the system DNS';

  @override
  String get testDns => 'Test DNS';

  @override
  String get transport => 'Protocol';

  @override
  String get transportH3 => 'HTTP/3 (QUIC)';

  @override
  String get transportH2 => 'HTTP/2 (TCP)';

  @override
  String get directRules => 'Direct';

  @override
  String get directRulesHint =>
      'Sites and addresses in this list open without the VPN, straight through your own internet. The chosen country\'s rules are already here: add, change, or remove lines. Choosing another country replaces them with its own.';

  @override
  String get restoreRegionRules => 'Restore the region\'s rules';

  @override
  String get blockRules => 'Block';

  @override
  String get blockRulesHint =>
      'Sites and addresses in this list do not open at all, neither directly nor through the VPN: for ads, or sites you never want reached.';

  @override
  String get rulesTitle => 'Rules';

  @override
  String get ruleSyntaxTitle => 'How to write a rule';

  @override
  String get resolveDomains => 'Look up names for IP rules';

  @override
  String get routingLists => 'Geo files';

  @override
  String get listSource => 'List source';

  @override
  String get listSourceCustom => 'Set by hand';

  @override
  String listsUpdatedAgo(String ago) {
    return 'Updated $ago';
  }

  @override
  String get updateLists => 'Update the geo files';

  @override
  String get listsUpdated => 'The geo files were updated.';

  @override
  String get testDestination => 'Test a destination';

  @override
  String get destinationHint => 'A name, an address, or a URL';

  @override
  String get check => 'Check';

  @override
  String get routeDirect => 'Goes directly';

  @override
  String get routeProxy => 'Goes through the VPN';

  @override
  String get routeBlock => 'Blocked';

  @override
  String ruleMatched(String rule) {
    return 'Rule: $rule';
  }

  @override
  String get portRefusedNote =>
      'Mozilla\'s proxy does not connect to this port.';

  @override
  String get sectionAdvanced => 'Advanced';

  @override
  String get tlsFragment => 'TLS fragmentation';

  @override
  String get tlsFragmentOff => 'Off';

  @override
  String get tlsFragmentFirstByte => 'First byte';

  @override
  String get tlsFragmentSni => 'Server name (SNI)';

  @override
  String get tlsFragmentFirstByteHint =>
      'Splits the TLS header at the first byte (0x16)';

  @override
  String get tlsFragmentSniHint =>
      'Splits the server name (SNI) across TCP packets';

  @override
  String get tlsFragmentRecord => 'TLS record';

  @override
  String get tlsFragmentRecordHint =>
      'Splits the server name (SNI) across two TLS records';

  @override
  String get tlsFragmentOffHint => 'Normal TLS connection';

  @override
  String get sectionBypass => 'If Mozilla is blocked';

  @override
  String get apiRelay => 'Relay server';

  @override
  String get apiRelayHint =>
      'Your own Cloudflare Worker, or relay.php on your own host.\nUsed only when Mozilla doesn\'t answer directly: the sign-in, accounts, and server list go through it, not the VPN traffic.';

  @override
  String get upstreamProxy => 'Upstream proxy';

  @override
  String get upstreamProxyOn => 'Upstream proxy is on';

  @override
  String get upstreamProxyAddress => 'SOCKS5 proxy address';

  @override
  String get upstreamProxyPort => 'Port';

  @override
  String get upstreamProxyHint =>
      'The connection to Mozilla goes through this proxy, for networks that block or slow Mozilla.\nIf the proxy runs on this device, leave it out of the VPN.';

  @override
  String get upstreamProxyInvalid =>
      'Enter the proxy\'s address, such as 127.0.0.1.';

  @override
  String get upstreamProxyInvalidPort => 'Enter a port from 1 to 65535.';

  @override
  String get upstreamProxyOwn =>
      'That\'s this app\'s own proxy. Enter another one.';

  @override
  String get apiRelayInvalid => 'Must be an https:// address.';

  @override
  String get listenAddress => 'Listen on';

  @override
  String get listenLocal => '127.0.0.1 · this device only';

  @override
  String get listenAll => '0.0.0.0 · all networks (LAN)';

  @override
  String get proxyUsername => 'Proxy username';

  @override
  String get proxyPassword => 'Proxy password';

  @override
  String get proxyLoginHint =>
      'Apps must sign in with these. Leave both empty for no login.';

  @override
  String get loginBothOrNone => 'Fill in both, or leave both empty.';

  @override
  String get proxyLogin => 'Proxy login';

  @override
  String get idleSleep => 'Sleep when idle after';

  @override
  String get sleepNever => 'Never';

  @override
  String sleepMinutes(int count) {
    return '$count minutes';
  }

  @override
  String get sleepHour => '1 hour';

  @override
  String get showPublicIp => 'Show the public IP';

  @override
  String get speedInNotification => 'Show speed in the notification';

  @override
  String get liveTraffic => 'Live traffic';

  @override
  String get totalTraffic => 'Total traffic';

  @override
  String get verboseLogs => 'Detailed logs';

  @override
  String get webDashboard => 'Web dashboard';

  @override
  String get webDashboardOpen => 'Open';

  @override
  String get webDashboardHint => 'Advanced settings and more tools';

  @override
  String numberInvalid(int min, int max) {
    return 'Enter a number from $min to $max';
  }

  @override
  String get notifySwitchedTitle => 'Switched account';

  @override
  String notifySwitchedBody(String name) {
    return 'Now using $name.';
  }

  @override
  String get notifySignInTitle => 'Sign-in needed';

  @override
  String get notifySignInBody =>
      'An account must be signed in again on the Accounts page.';

  @override
  String get navAbout => 'About';

  @override
  String get appVersionLabel => 'App version';

  @override
  String get coreVersionLabel => 'Core version';

  @override
  String get checkUpdates => 'Check for updates';

  @override
  String get checkingUpdates => 'Checking…';

  @override
  String get upToDate => 'You have the latest version.';

  @override
  String updateAvailable(String version) {
    return 'Version $version is available.';
  }

  @override
  String get download => 'Download';

  @override
  String updateCheckFailed(String error) {
    return 'Could not check for updates: $error';
  }

  @override
  String get updateNow => 'Update';

  @override
  String updateDownloading(String version) {
    return 'Downloading version $version…';
  }

  @override
  String updateReady(String version) {
    return 'Version $version is ready to install.';
  }

  @override
  String updateInstalling(String version) {
    return 'Installing version $version. The app will close and open again.';
  }

  @override
  String updateFailed(String version) {
    return 'Couldn\'t update to version $version.';
  }

  @override
  String updateDone(String version) {
    return 'Updated to version $version.';
  }

  @override
  String updateRolledBack(String version) {
    return 'The update to version $version didn\'t finish, so the app went back to the previous version.';
  }

  @override
  String get repoNotSet => 'The GitHub repository is not set yet.';

  @override
  String get sourceCode => 'Source code';

  @override
  String get tapToConnect => 'Click to connect';

  @override
  String get tapToDisconnect => 'Click to disconnect';

  @override
  String get startOnBoot => 'Start on boot';

  @override
  String get connectOnStartup => 'Connect on startup';

  @override
  String get proxyServiceActive => 'Proxy service active';

  @override
  String get navHome => 'Home';

  @override
  String get groupApp => 'App';

  @override
  String get groupNetwork => 'Network';

  @override
  String get stateOff => 'Disconnected';

  @override
  String get tapToConnectPhone => 'Tap to connect';

  @override
  String get tapToDisconnectPhone => 'Tap to disconnect';

  @override
  String get tapToConnectTv => 'Press OK to connect';

  @override
  String get tapToDisconnectTv => 'Press OK to disconnect';

  @override
  String lanAddress(String address) {
    return 'LAN $address';
  }

  @override
  String get recommendedLocation => 'Recommended location';

  @override
  String dataLeftOf(String limit) {
    return 'of $limit';
  }

  @override
  String get homeLocation => 'Location';

  @override
  String get connectedTo => 'Connected to';

  @override
  String get vpnNotAllowed =>
      'The VPN needs your permission. Tap the button again and allow it.';

  @override
  String get dataUsedTitle => 'Data used';

  @override
  String get bypassApps => 'Per-app proxy';

  @override
  String get connectRetrying => 'Couldn\'t connect. Check your internet.';

  @override
  String get failUnreachable =>
      'Couldn\'t reach Mozilla\'s servers. Try another internet connection.';

  @override
  String get failUpstreamProxy =>
      'Couldn\'t reach Mozilla through your upstream proxy. Check that it\'s running.';

  @override
  String get failInsideVpn =>
      'This internet already goes through a VPN. Turn it off.';

  @override
  String get failRefused =>
      'Mozilla\'s server refused the connection. Try again in a few minutes.';

  @override
  String get failLocationRefused =>
      'This country isn\'t open to your account. Choose another country.';

  @override
  String get useRecommendedLocation => 'Use the recommended location';

  @override
  String exitMismatch(String exit, String chosen) {
    return 'You chose $chosen, but your IP is in $exit.';
  }

  @override
  String get failSignIn =>
      'This account\'s sign-in has expired. Sign in again on the Accounts page.';

  @override
  String get failQuota => 'This month\'s data is used up. Add another account.';

  @override
  String get failNotEntitled =>
      'Mozilla doesn\'t let this account use the VPN. Add another account.';

  @override
  String get failRegion =>
      'Mozilla doesn\'t offer its service in your country.';

  @override
  String get failServer =>
      'Mozilla\'s service has a temporary problem. The app tries again by itself.';

  @override
  String get failNoAccount => 'No account is ready. Open the Accounts page.';

  @override
  String get failTestSite =>
      'Connected to the server, but sites don\'t open. Try another country.';

  @override
  String get failOther => 'Couldn\'t connect. Try again.';

  @override
  String get failNoInternet => 'No internet. Check Wi-Fi or mobile data.';

  @override
  String get waitingForNetwork => 'Waiting for an internet connection…';

  @override
  String proxyStartFailed(String port) {
    return 'The proxy couldn\'t start on port $port. Choose another port.';
  }

  @override
  String get connectionSettings => 'Connection settings';

  @override
  String get appModeExclude => 'Bypass selected apps';

  @override
  String get appModeInclude => 'Proxy selected apps';

  @override
  String get appModeExcludeHint =>
      'Selected apps connect directly, not through the VPN: for example banking apps that refuse foreign addresses.';

  @override
  String get appModeIncludeHint =>
      'Only the selected apps go through the VPN; the others connect directly.';

  @override
  String fromRegionList(String region) {
    return 'Suggested: on the $region list';
  }

  @override
  String get modeProxy => 'Proxy';

  @override
  String get connectionMode => 'Connection mode';

  @override
  String get modeProxyHint =>
      'Only apps set up to use the proxy go through it.';

  @override
  String get modeSystemProxyHint =>
      'Windows and most apps go through the proxy.';

  @override
  String get modeSystemProxyHintOther =>
      'Browsers and most apps go through the proxy.';

  @override
  String get suggestedApps => 'Suggested apps';

  @override
  String get showSystemApps => 'Show system apps';

  @override
  String suggestedAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count suggested apps selected',
      one: '1 suggested app selected',
      zero: 'The suggested apps are already selected',
    );
    return '$_temp0';
  }

  @override
  String get autoSection => 'Automatic';

  @override
  String get locationsSection => 'Locations';

  @override
  String get dnsSummaryOk => 'Encrypted DNS works';

  @override
  String dnsSummaryFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count names did not resolve',
      one: '1 name did not resolve',
    );
    return '$_temp0';
  }

  @override
  String dnsVia(String server) {
    return 'via $server';
  }

  @override
  String dnsSummaryDiffers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Your network\'s DNS answered $count names with a filtering address. This app does not use it for them.',
      one: 'Your network\'s DNS answered 1 name with a filtering address. This app does not use it for them.',
    );
    return '$_temp0';
  }

  @override
  String get dnsAnswer => 'Answer:';

  @override
  String get dnsNetworkAnswer => 'Network DNS:';

  @override
  String get dnsFiltered => 'filtered';

  @override
  String get rulesSyntaxTitle => 'One rule per line';

  @override
  String get ruleDomain => 'The site and its subdomains';

  @override
  String get ruleFull => 'Exactly this name';

  @override
  String get ruleKeyword => 'Names that contain the word';

  @override
  String get ruleGeosite => 'Sites of a tag in the geo files';

  @override
  String get ruleGeoip => 'Addresses of a country in the geo files';

  @override
  String get ruleIp => 'An address or a network';

  @override
  String get modeVpn => 'VPN';

  @override
  String get modeProxyOnly => 'Proxy only';

  @override
  String get noNetwork =>
      'No internet connection. Turn on Wi-Fi or mobile data.';

  @override
  String get blockAds => 'Block ads';

  @override
  String systemProxyTakenBy(String address) {
    return 'Another program set the system proxy to $address, so traffic doesn\'t go through the VPN.';
  }

  @override
  String get systemProxyTakenOff =>
      'Another program turned the system proxy off, so traffic doesn\'t go through the VPN.';

  @override
  String get setSystemProxyAgain => 'Set it again';

  @override
  String get modeTun => 'TUN';

  @override
  String modeTunHint(String os) {
    return 'All $os traffic goes through the VPN.';
  }

  @override
  String get osWindows => 'Windows';

  @override
  String get osLinux => 'Linux';

  @override
  String get osMacos => 'macOS';

  @override
  String get tunInstallWaiting =>
      'Waiting for permission to install the TUN service…';

  @override
  String get tunInstallCancelled =>
      'TUN mode needs administrator permission once. It wasn\'t given, so the mode didn\'t change.';

  @override
  String tunInstallFailed(String error) {
    return 'Couldn\'t install the TUN service: $error';
  }

  @override
  String get tunStarting => 'Starting TUN mode…';

  @override
  String get tunFailed => 'TUN mode couldn\'t start. Trying again…';

  @override
  String get tunLost => 'TUN mode stopped unexpectedly. Trying again…';

  @override
  String get tunNotRunning => 'The TUN service isn\'t running. Trying again…';

  @override
  String get tunMissing => 'The TUN service isn\'t installed.';

  @override
  String get tunOutdated =>
      'The TUN service is older than this app. Install it again to use TUN mode.';

  @override
  String get tunAppOutdated =>
      'The TUN service is newer than this app. Update the app to use TUN mode.';

  @override
  String get tunBusy => 'Another copy of Firefox VPN is using TUN mode.';

  @override
  String get tunNoDriver =>
      'The system\'s TUN driver isn\'t available. Restart the computer and try again.';

  @override
  String get tunInstall => 'Install';

  @override
  String get tunInstallAgain => 'Install again';

  @override
  String get trayTunMode => 'TUN mode (all apps)';

  @override
  String get removeTunService => 'Remove the TUN service';

  @override
  String get removeTunServiceHint =>
      'Removes the system service that TUN mode uses. Choosing TUN again installs it again.';

  @override
  String get tunServiceRemoved => 'The TUN service was removed.';

  @override
  String get tunInstallPrompt =>
      'Firefox VPN wants to install the service for TUN mode.';

  @override
  String get tunRemovePrompt =>
      'Firefox VPN wants to remove the service for TUN mode.';

  @override
  String tunRemoveFailed(String error) {
    return 'Couldn\'t remove the TUN service: $error';
  }

  @override
  String get sectionTun => 'TUN settings';

  @override
  String get tunPrograms => 'Programs that bypass the VPN';

  @override
  String get tunProgramsHint =>
      'They connect directly, not through Mozilla. Only for programs that work without a VPN.';

  @override
  String get tunProgramsEmpty => 'No programs yet.';

  @override
  String get addProgram => 'Add program';

  @override
  String get programFiles => 'Programs';

  @override
  String get tunProgramAll => 'All traffic';

  @override
  String get tunProgramAllHint => 'The whole program connects directly.';

  @override
  String get tunProgramUdp => 'UDP only';

  @override
  String get tunProgramUdpHint =>
      'Only its UDP connects directly; the rest goes through the VPN.';

  @override
  String get udpNoticeSetting => 'Notice when UDP is blocked';

  @override
  String udpNoticeBody(String program) {
    return '$program\'s UDP traffic can\'t go through the VPN.';
  }

  @override
  String get dontShowAgain => 'Don\'t show again';

  @override
  String get addRunningProgram => 'From running programs';

  @override
  String get addProgramFile => 'Choose a file…';

  @override
  String get addProgramName => 'Type a name…';

  @override
  String get programNameHint =>
      'A program\'s file name, such as steam.exe; * stands for any text (steam* is every Steam program).';

  @override
  String get runningProgramsEmpty => 'No other programs are running.';

  @override
  String get tabLog => 'Log';

  @override
  String get tabConnections => 'Connections';

  @override
  String get connectionsEmpty => 'No connections yet.';

  @override
  String connectionsOpen(int count) {
    return '$count open';
  }

  @override
  String get connTime => 'Time';

  @override
  String get connRoute => 'Rule';

  @override
  String get connDestination => 'Destination';

  @override
  String get connInbound => 'Inbound';

  @override
  String get connProtocol => 'Protocol';

  @override
  String get connColumns => 'Columns';

  @override
  String get connTraffic => 'Traffic';

  @override
  String get connDuration => 'Duration';

  @override
  String get connRouteVpn => 'Proxy';

  @override
  String get connRouteDirect => 'Direct';

  @override
  String get connRouteBlocked => 'Blocked';

  @override
  String get connRoutePort => 'Port refused';

  @override
  String get connRouteFailed => 'Failed';
}
