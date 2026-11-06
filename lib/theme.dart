import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Switches to the opposite of what is on screen. Landing back on the phone's
/// own setting returns to following the phone.
Future<void> toggleThemeMode(BuildContext context) async {
  final dark = !context.isDark;
  final phoneDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  themeMode.value = dark == phoneDark ? ThemeMode.system : (dark ? ThemeMode.dark : ThemeMode.light);
  try {
    final prefs = await SharedPreferences.getInstance();
    dark == phoneDark ? await prefs.remove(_darkModeKey) : await prefs.setBool(_darkModeKey, dark);
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

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final surface = dark ? const Color(0xFF1C2320) : Colors.white;
  final scheme = ColorScheme.fromSeed(
    seedColor: brandGreen,
    brightness: brightness,
    primary: dark ? brandGreenLight : brandGreen,
  );
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    scaffoldBackgroundColor: dark ? const Color(0xFF111614) : const Color(0xFFF3F4F6),
    appBarTheme: const AppBarTheme(backgroundColor: brandGreen, foregroundColor: Colors.white),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: surface,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    cardTheme: CardThemeData(color: surface, elevation: 1),
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
