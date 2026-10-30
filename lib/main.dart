import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'background.dart';
import 'firebase_options.dart';
import 'models/app_user.dart';
import 'screens/admin_home.dart';
import 'screens/login_screen.dart';
import 'screens/user_home.dart';
import 'services/auth_service.dart';
import 'services/notifier.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadThemeMode();
  Object? setupError;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    setupError = e;
  }
  if (setupError == null) {
    try {
      await initBackgroundChecks();
      await Notifier.init();
    } catch (_) {
      // Background matching is optional; the app works without it.
    }
  }
  runApp(MyRecoverApp(setupError: setupError));
}

class MyRecoverApp extends StatelessWidget {
  const MyRecoverApp({super.key, this.setupError});
  final Object? setupError;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'MyRecover',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        themeAnimationDuration: const Duration(milliseconds: 350),
        // iOS rubber-band overscroll everywhere.
        scrollBehavior: const MaterialScrollBehavior().copyWith(physics: const BouncingScrollPhysics()),
        home: setupError != null ? _SetupErrorScreen(error: setupError!) : const AuthGate(),
      ),
    );
  }
}

/// Shows login when signed out, otherwise the user or admin home based on
/// the role stored in `users/{uid}`.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges(),
      builder: (context, authSnap) {
        final firebaseUser = authSnap.data;
        final Widget child;
        if (authSnap.connectionState == ConnectionState.waiting) {
          child = const _Loading(key: ValueKey('loading'));
        } else if (firebaseUser == null) {
          child = const LoginScreen(key: ValueKey('login'));
        } else {
          child = StreamBuilder<AppUser?>(
            key: ValueKey(firebaseUser.uid),
            stream: AuthService.instance.profile(firebaseUser.uid),
            builder: (context, snap) {
              // The profile doc may not exist yet right after registering.
              final user = snap.data;
              // Only UiTM student Google accounts (and admins) get in, including
              // sessions saved from before this rule existed.
              if (user != null && !user.isAdmin && !AuthService.isAllowedEmail(firebaseUser.email)) {
                AuthService.instance.logout();
                return _fade(const LoginScreen(key: ValueKey('login')));
              }
              return _fade(
                user == null
                    ? const _Loading(key: ValueKey('profile-loading'))
                    : user.isAdmin
                    ? AdminHome(key: ValueKey('admin-${user.uid}'), user: user)
                    : UserHome(key: ValueKey('user-${user.uid}'), user: user),
              );
            },
          );
        }
        return _fade(child);
      },
    );
  }
}

Widget _fade(Widget child) => AnimatedSwitcher(
  duration: const Duration(milliseconds: 450),
  switchInCurve: Curves.easeOutQuart,
  switchOutCurve: Curves.easeInOutCubic,
  transitionBuilder: (child, anim) => FadeTransition(
    opacity: anim,
    child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(anim), child: child),
  ),
  child: child,
);

class _Loading extends StatelessWidget {
  const _Loading({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          TextButton(onPressed: AuthService.instance.logout, child: const Text('Cancel')),
        ],
      ),
    ),
  );
}

class _SetupErrorScreen extends StatelessWidget {
  const _SetupErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Firebase setup needed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
