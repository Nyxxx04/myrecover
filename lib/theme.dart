import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

const brandGreen = Color(0xFF1D4E3E);
const lostColor = Color(0xFFD97706);
const foundColor = Color(0xFF059669);
const pendingColor = Color(0xFF2563EB);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: brandGreen, primary: brandGreen);
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
    scaffoldBackgroundColor: const Color(0xFFF3F4F6),
    appBarTheme: const AppBarTheme(backgroundColor: brandGreen, foregroundColor: Colors.white),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      filled: true,
      fillColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    cardTheme: const CardThemeData(color: Colors.white, elevation: 1),
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
