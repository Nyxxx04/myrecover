import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/theme_reveal.dart';

const brandGreen = Color(0xFF1D4E3E);
const brandGreenLight = Color(0xFF7DD3AE);
const lostColor = Color(0xFFD97706);
const foundColor = Color(0xFF059669);
const pendingColor = Color(0xFF2563EB);

/// Colors that differ between light and dark mode.
extension ThemeColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Brand green that stays readable as text on the current background.
  Color get brandText => isDark ? brandGreenLight : brandGreen;
  Color get mutedText => isDark ? const Color(0xFFB4BDB8) : const Color(0xFF4B5563);
  Color get aiText => isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED);
  Color get returnedText => isDark ? const Color(0xFF93C5FD) : pendingColor;
}

/// Stored only when the user overrides the phone's setting: true = dark, false = light.
/// (A new key: the old 'dark_mode' was saved on every switch, even back to light.)
const _darkModeKey = 'theme_override';

/// Follows the phone's light/dark setting until the user picks one.
final themeMode = ValueNotifier(ThemeMode.system);

Future<void> loadThemeMode() async {
  try {
    final dark = (await SharedPreferences.getInstance()).getBool(_darkModeKey);
    if (dark != null) themeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
  } catch (_) {
    // Storage unavailable: follow the phone.
  }
}

/// Switches to the opposite of what is on screen, revealed as a circle that
/// grows from [context]'s widget. Landing back on the phone's own setting
/// returns to following the phone.
Future<void> toggleThemeMode(BuildContext context) async {
  final dark = !context.isDark;
  final phoneDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  final mode = dark == phoneDark ? ThemeMode.system : (dark ? ThemeMode.dark : ThemeMode.light);
  final box = context.findRenderObject() as RenderBox?;
  final center = box != null && box.hasSize
      ? box.localToGlobal(box.size.center(Offset.zero))
      : Offset(MediaQuery.sizeOf(context).width, 0);
  final save = SharedPreferences.getInstance().then(
    (prefs) => dark == phoneDark ? prefs.remove(_darkModeKey) : prefs.setBool(_darkModeKey, dark),
  );
  await ThemeReveal.run(center, () => themeMode.value = mode);
  try {
    await save;
  } catch (_) {
    // The switch still applies for this session.
  }
}

/// Sun/moon button that switches between light and dark mode.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: themeMode,
    builder: (context, mode, _) {
      final dark = context.isDark;
      return IconButton(
        tooltip: dark ? 'Switch to light mode' : 'Switch to dark mode',
        onPressed: () => toggleThemeMode(context),
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, anim) => RotationTransition(
            turns: Tween(begin: 0.75, end: 1.0).animate(anim),
            child: FadeTransition(opacity: anim, child: child),
          ),
          child: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, key: ValueKey(dark)),
        ),
      );
    },
  );
}

/// Thin light edge on glass surfaces.
Color glassEdge(bool dark) => dark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.9);

/// Translucent card fill that lets the background glow through.
Color glassFill(bool dark) => dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.72);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF1C2320) : Colors.white;
  final scheme = ColorScheme.fromSeed(
    seedColor: brandGreen,
    brightness: brightness,
    primary: dark ? brandGreenLight : brandGreen,
  );
  final brand = dark ? brandGreenLight : brandGreen;
  const pill = StadiumBorder();
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    // iOS-style feedback: no ripple; buttons dim/shrink instead (see PressScale).
    splashFactory: NoSplash.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        // iOS slide-in with parallax and swipe-from-left-edge to go back.
        TargetPlatform.android: SmoothPageTransitionsBuilder(),
        TargetPlatform.iOS: SmoothPageTransitionsBuilder(),
      },
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    scaffoldBackgroundColor: dark ? const Color(0xFF0C1310) : const Color(0xFFEFF4F1),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      foregroundColor: brand,
      // Dark status bar icons on the light background, light ones in dark mode.
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: brand, letterSpacing: -0.3),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      filled: true,
      fillColor: dark ? Colors.white.withValues(alpha: 0.06) : surface.withValues(alpha: 0.8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), shape: pill),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(shape: pill)),
    elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(shape: pill)),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: pill)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(shape: pill),
    chipTheme: ChipThemeData(
      shape: pill,
      side: BorderSide(color: dark ? Colors.white12 : Colors.black12),
    ),
    cardTheme: CardThemeData(
      color: glassFill(dark),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: glassEdge(dark)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? const Color(0xFF1A221F) : const Color(0xFFF9FBFA),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    popupMenuTheme: PopupMenuThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
  );
}

/// The iOS page slide, slowed down a little (Flutter's default is 500ms) so
/// navigating between pages feels calmer.
class SmoothPageTransitionsBuilder extends CupertinoPageTransitionsBuilder {
  const SmoothPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 700);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 600);
}
