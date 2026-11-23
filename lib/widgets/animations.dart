import 'dart:math';

import 'package:flutter/material.dart';

const motionFast = Duration(milliseconds: 150);
const motionMedium = Duration(milliseconds: 300);
const motionSlow = Duration(milliseconds: 700);

/// Tab pages that switch with a soft sideways drift ("shared axis"): the old
/// page fades out while drifting a little away, and the new one fades in while
/// drifting in from the side of the tab it is on (right when moving right).
/// Every child stays alive, so tabs keep their state.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  // `preserve`: many phones turn animations off in battery saver, which would
  // otherwise cut this short fade to 5% of its length and make it look instant.
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// How far the pages drift, in logical pixels.
  static const _drift = 36.0;
  late int _previous = widget.index;

  /// 1 when moving right, -1 when moving left.
  double _direction = 1;

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _previous = old.index;
      _direction = widget.index > old.index ? 1 : -1;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final sliding = _controller.isAnimating;
        final t = _controller.value;
        // The old page is gone in the first 40%; the new one fades in from 20%.
        final out = Curves.easeIn.transform((t / 0.4).clamp(0.0, 1.0));
        final inT = Curves.easeOutCubic.transform(((t - 0.2) / 0.8).clamp(0.0, 1.0));
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              if (i == widget.index)
                _page(i, visible: true, opacity: inT, dx: _direction * _drift * (1 - inT))
              else
                _page(i, visible: sliding && i == _previous, opacity: 1 - out, dx: -_direction * _drift * out),
          ],
        );
      },
    );
  }

  Widget _page(int i, {required bool visible, required double opacity, required double dx}) => Offstage(
    offstage: !visible,
    child: TickerMode(
      enabled: visible,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(offset: Offset(dx, 0), child: widget.children[i]),
      ),
    ),
  );
}

/// Fades and slides its child up the first time it appears. [index] staggers
/// the start so lists cascade in.
class AnimatedEntry extends StatefulWidget {
  const AnimatedEntry({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<AnimatedEntry> createState() => _AnimatedEntryState();
}

class _AnimatedEntryState extends State<AnimatedEntry> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 550));
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeOutQuint);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 40 * min(widget.index, 6)), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// Shrinks its child slightly while pressed, for tactile buttons.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _set(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1,
        duration: _pressed ? const Duration(milliseconds: 90) : const Duration(milliseconds: 350),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.8 : 1,
          duration: _pressed ? const Duration(milliseconds: 90) : const Duration(milliseconds: 250),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Button content that cross-fades between its label and a spinner.
class ButtonLabel extends StatelessWidget {
  const ButtonLabel(this.text, {super.key, this.loading = false});
  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motionFast,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(anim), child: child),
      ),
      child: loading
          ? const SizedBox.square(
              key: ValueKey('spinner'),
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(text, key: const ValueKey('label')),
    );
  }
}

/// Counts up to [value] whenever it changes.
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, this.style});
  final int value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: value.toDouble()),
      duration: motionSlow,
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}
