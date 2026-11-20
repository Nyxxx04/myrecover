import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

final _revealKey = GlobalKey<_ThemeRevealState>();

/// Wraps the whole app so a theme change can be revealed as a circle that
/// grows from the button that was tapped: the old look is snapshotted, the
/// theme switches underneath, and the snapshot is cut away from [center] out.
class ThemeReveal extends StatefulWidget {
  ThemeReveal({required this.child}) : super(key: _revealKey);
  final Widget child;

  /// Runs [change] behind a circular reveal centred on [center] (global
  /// coordinates). Without a ThemeReveal on screen it just runs [change].
  static Future<void> run(Offset center, VoidCallback change) async {
    final state = _revealKey.currentState;
    if (state == null) return change();
    return state._reveal(center, change);
  }

  @override
  State<ThemeReveal> createState() => _ThemeRevealState();
}

class _ThemeRevealState extends State<ThemeReveal> with SingleTickerProviderStateMixin {
  final _boundary = GlobalKey();
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 850));
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
  ui.Image? _snapshot;
  Offset _center = Offset.zero;

  Future<void> _reveal(Offset center, VoidCallback change) async {
    final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (_controller.isAnimating || boundary == null) return change();
    final ui.Image image;
    try {
      image = await boundary.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
    } catch (_) {
      return change(); // snapshot failed: switch without the effect
    }
    if (!mounted) return change();
    setState(() {
      _snapshot = image;
      _center = center;
    });
    change();
    await _controller.forward(from: 0);
    if (mounted) setState(() => _snapshot = null);
    image.dispose();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        RepaintBoundary(key: _boundary, child: widget.child),
        if (snapshot != null)
          Positioned.fill(
            // Swallow taps until the reveal finishes.
            child: AbsorbPointer(
              child: LayoutBuilder(
                builder: (context, box) {
                  // Far enough to reach the furthest corner.
                  final corners = [
                    Offset.zero,
                    Offset(box.maxWidth, 0),
                    Offset(0, box.maxHeight),
                    Offset(box.maxWidth, box.maxHeight),
                  ];
                  final maxRadius = corners.map((c) => (c - _center).distance).reduce(max);
                  return AnimatedBuilder(
                    animation: _curve,
                    builder: (context, child) =>
                        ClipPath(clipper: _HoleClipper(_center, maxRadius * _curve.value), child: child),
                    child: RawImage(image: snapshot, fit: BoxFit.fill),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

/// Everything except a circle: the old snapshot with a growing hole in it.
class _HoleClipper extends CustomClipper<Path> {
  _HoleClipper(this.center, this.radius);
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) => Path()
    ..fillType = PathFillType.evenOdd
    ..addRect(Offset.zero & size)
    ..addOval(Rect.fromCircle(center: center, radius: radius));

  @override
  bool shouldReclip(_HoleClipper old) => old.radius != radius || old.center != center;
}
