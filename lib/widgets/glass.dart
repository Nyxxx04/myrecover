import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Frosted glass panel: blurs what is behind it, with a translucent tint and a
/// thin light edge. Blur is costly, so use it for bars and sheets, not list items.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 28, this.blur = 24, this.shadow = true});

  final Widget child;
  final double radius;
  final double blur;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final shape = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              border: Border.all(color: glassEdge(dark), width: 1),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: dark
                    ? [Colors.white.withValues(alpha: 0.14), Colors.white.withValues(alpha: 0.05)]
                    : [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0.55)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Soft green gradient with two glowing colour blobs, so glass on top of it
/// has something to blur.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    Widget blob(Color color, double size) => IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF0E1A16), Color(0xFF0A0F0D)] : const [Color(0xFFE6F2EC), Color(0xFFF4F6F5)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -120, right: -90, child: blob(brandGreenLight.withValues(alpha: dark ? 0.22 : 0.45), 380)),
          Positioned(
            bottom: 60,
            left: -140,
            child: blob(const Color(0xFF60A5FA).withValues(alpha: dark ? 0.14 : 0.22), 420),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class GlassNavItem {
  const GlassNavItem({required this.icon, required this.label});

  /// Usually an [Icon]; may be wrapped in a [Badge].
  final Widget icon;
  final String label;
}

/// Floating pill-shaped bottom bar of frosted glass. The highlight slides
/// between tabs with a little spring.
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({super.key, required this.index, required this.onTap, required this.items});

  final int index;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  /// Height of the bar plus its gap, for bottom padding of lists behind it.
  static const clearance = 110.0;

  @override
  Widget build(BuildContext context) {
    final selected = context.brandText;
    final idle = context.mutedText;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Glass(
          radius: 34,
          child: SizedBox(
            height: 66,
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth / items.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 520),
                      curve: const ElasticOutCurve(0.85),
                      left: index * w + 6,
                      top: 6,
                      bottom: 6,
                      width: w - 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: selected.withValues(alpha: context.isDark ? 0.18 : 0.13),
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final (i, item) in items.indexed)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (i != index) HapticFeedback.selectionClick();
                                onTap(i);
                              },
                              child: _NavButton(item: item, active: i == index, color: i == index ? selected : idle),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.active, required this.color});
  final GlassNavItem item;
  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    const duration = Duration(milliseconds: 300);
    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: active ? 1.12 : 1,
            duration: duration,
            curve: Curves.easeOutBack,
            child: IconTheme(
              data: IconThemeData(color: color, size: 24),
              child: item.icon,
            ),
          ),
          const SizedBox(height: 3),
          AnimatedDefaultTextStyle(
            duration: duration,
            style: TextStyle(fontSize: 11.5, color: color, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
            child: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
