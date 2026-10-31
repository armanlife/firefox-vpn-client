import 'package:firefox_vpn/ui/focus_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the ring shows while keys move the focus, not after a touch', (
    tester,
  ) async {
    final ring = find.byKey(const ValueKey('focus-ring'));
    await tester.pumpWidget(
      MaterialApp(
        home: FocusRing(
          child: Scaffold(
            body: Column(
              children: [
                FilledButton(onPressed: () {}, child: const Text('One')),
                FilledButton(onPressed: () {}, child: const Text('Two')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(ring, findsNothing);

    // A remote's arrow: the focus moves, and the ring shows.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNotNull);
    expect(ring, findsOneWidget);

    // A touch hides it.
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(ring, findsNothing);

    // Typing letters does not bring it back.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pumpAndSettle();
    expect(ring, findsNothing);
  });
}
