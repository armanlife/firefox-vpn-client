import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A ring around the focused control while the focus moves by keys: a TV's
/// remote, or Tab and the arrows on a computer. Material's own focus shade
/// is too faint to see across a room, and on the home page's switch it is
/// all but invisible. A touch or a click hides the ring until the next
/// key; typing in a field does not show it.
class FocusRing extends StatefulWidget {
  const FocusRing({super.key, this.atStart = false, required this.child});

  /// Shown from the start: a TV, where the remote is all there is (Android
  /// keeps its first key to give the app the focus).
  final bool atStart;
  final Widget child;

  @override
  State<FocusRing> createState() => _FocusRingState();
}

class _FocusRingState extends State<FocusRing> {
  /// The keys that move the focus or press the focused control.
  static final _moves = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.select,
  };

  late bool _keys = widget.atStart;
  Timer? _settle;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    FocusManager.instance.addListener(_moved);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    FocusManager.instance.removeListener(_moved);
    _settle?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent && _moves.contains(event.logicalKey) && !_keys) {
      setState(() => _keys = true);
    }
    return false;
  }

  /// The focus moved, or what it is on moved (a scroll): drawn again, and
  /// once more when a page's slide in has ended.
  void _moved() {
    if (!_keys || !mounted) return;
    setState(() {});
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        if (_keys) setState(() => _keys = false);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          _moved();
          return false;
        },
        child: Stack(
          children: [
            widget.child,
            if (_keys)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    key: const ValueKey('focus-ring'),
                    painter: _RingPainter(
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final node = FocusManager.instance.primaryFocus;
    // A scope (a page with nothing chosen yet) is the whole screen.
    if (node == null || node is FocusScopeNode || node.context == null) return;
    // Inside the screen: a tab at its edge keeps its ring whole.
    final rect = node.rect
        .inflate(4)
        .intersect((Offset.zero & size).deflate(2));
    if (rect.isEmpty) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = color;
    // Round for a round control (the home page's switch), else its corners.
    final round = (rect.width - rect.height).abs() < 6;
    final radius = round ? rect.shortestSide / 2 : 14.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}
