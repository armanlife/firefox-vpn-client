import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:arman_vpn/ui/browser_signin.dart';

void main() {
  group('FxaWebChannel', () {
    late List<String> replies;
    late List<(String, String)> sessions;
    late FxaWebChannel channel;

    // A message as the injected script posts it: WebView2 hands over a
    // map, Android's channel a JSON string.
    Map<String, Object?> message(String command, [Object? data]) => {
      'kind': 'webchannel',
      'detail': {
        'id': 'account_updates',
        'message': {'messageId': 'm1', 'command': command, 'data': data},
      },
    };

    final first = 'ab' * 32;
    final second = 'cd' * 32;

    setUp(() {
      replies = [];
      sessions = [];
      channel = FxaWebChannel(
        reply: replies.add,
        onSession: (email, token) => sessions.add((email, token)),
      );
    });

    test('answers that no one is signed in, and that linking is fine', () {
      channel.handle(message('fxaccounts:fxa_status'));
      channel.handle(jsonEncode(message('fxaccounts:can_link_account')));
      expect(replies, hasLength(2));
      expect(replies[0], contains('"signedInUser":null'));
      expect(replies[1], contains('{"ok":true}'));
      expect(sessions, isEmpty);
    });

    test('reports the session at once, before any code is entered', () {
      channel.handle(
        message('fxaccounts:login', {
          'email': 'new@example.com',
          'sessionToken': first,
          'verified': false,
          'verificationMethod': 'email-otp',
        }),
      );
      expect(sessions, [('new@example.com', first)]);
    });

    test('reports a session once, and a new one again', () {
      final login = message('fxaccounts:login', {
        'email': 'new@example.com',
        'sessionToken': first,
      });
      channel.handle(login);
      channel.handle(jsonEncode(login));
      expect(sessions, hasLength(1));
      channel.handle(
        message('fxaccounts:login', {
          'email': 'new@example.com',
          'sessionToken': second,
          'verified': true,
        }),
      );
      expect(sessions.map((s) => s.$2), [first, second]);
    });

    test('ignores what is no session', () {
      channel.handle(message('fxaccounts:login', {'sessionToken': 'short'}));
      channel.handle(message('fxaccounts:login', 'not a map'));
      channel.handle('not json');
      channel.handle({'kind': 'other'});
      expect(sessions, isEmpty);
    });
  });
}
