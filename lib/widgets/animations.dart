import 'dart:math';

import 'package:flutter/material.dart';

const motionFast = Duration(milliseconds: 150);
const motionMedium = Duration(milliseconds: 300);
const motionSlow = Duration(milliseconds: 700);

/// IndexedStack that fades/slides the newly selected child in. Every child
/// keeps the same wrapper so switching tabs never loses their state.
class FadeIndexedStack extends StatefulWidget {
  const FadeIndexedStack({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 550), value: 1);
  late final _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
  late final _slide = Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(_curve);

  @override
  void didUpdateWidget(FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          FadeTransition(
            opacity: i == widget.index ? _curve : kAlwaysCompleteAnimation,
            child: SlideTransition(
              position: i == widget.index ? _slide : const AlwaysStoppedAnimation(Offset.zero),
              child: widget.children[i],
            ),
          ),
      ],
    );
  }
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
