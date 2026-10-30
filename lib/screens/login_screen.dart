import 'package:flutter/material.dart';

import '../app_config.dart';
import '../services/auth_service.dart';
import '../services/update_service.dart';
import '../theme.dart';
import '../widgets/animations.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _adminMode = false;
  bool _toAdmin = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    AuthService.instance.warmUp();
    WidgetsBinding.instance.addPostFrameCallback((_) => UpdateService.checkAndPrompt(context));
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Login failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _google() => _run(AuthService.instance.signInWithGoogle);

  void _admin() {
    if (!_form.currentState!.validate()) return;
    _run(() => AuthService.instance.adminLogin(_username.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: _adminMode ? 'Admin login' : 'Welcome',
      subtitle: _adminMode ? '' : (studentsOnly ? 'Sign in with your UiTM student Google account' : 'Sign in with your Google account'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: motionMedium,
            curve: Curves.easeOutCubic,
            child: _error != null ? ErrorBanner(_error!) : const SizedBox(width: double.infinity),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              // Slide down→up when opening admin, up→down when closing
              final dir = _toAdmin ? 1.0 : -1.0;
              final slide = Tween<Offset>(
                begin: Offset(0, 0.07 * dir),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _adminMode ? _adminForm() : _studentButton(),
          ),
          const SizedBox(height: 8),
          PressScale(
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                      _toAdmin = !_adminMode;
                      _adminMode = !_adminMode;
                      _error = null;
                    }),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _adminMode ? 'Student sign-in' : 'Admin login',
                  key: ValueKey(_adminMode),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentButton() => Column(
    key: const ValueKey('student'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PressScale(
        child: ElevatedButton(
          onPressed: _loading ? null : _google,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: brandGreen,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          child: _loading
              ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'G',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Sign in with Google',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
        ),
      ),
      const SizedBox(height: 10),
      if (studentsOnly)
        const Text(
          'For UiTM students only. Log in using your official student Google account.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
    ],
  );

  Widget _adminForm() => Form(
    key: _form,
    child: Column(
      key: const ValueKey('admin'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _username,
          decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
          textInputAction: TextInputAction.next,
          autocorrect: false,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your username.' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
          onFieldSubmitted: (_) => _admin(),
          validator: (v) => (v == null || v.isEmpty) ? 'Please enter your password.' : null,
        ),
        const SizedBox(height: 20),
        PressScale(
          child: FilledButton(
            onPressed: _loading ? null : _admin,
            child: ButtonLabel('Log in', loading: _loading),
          ),
        ),
      ],
    ),
  );
}

class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandGreen,
      appBar: AppBar(elevation: 0, scrolledUnderElevation: 0, actions: const [ThemeToggle()]),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Hero(
                  tag: 'brand',
                  child: Material(
                    type: MaterialType.transparency,
                    // Title and subtitle fly together so they never overlap mid-transition.
                    child: Column(
                      children: [
                        Text(
                          '📦 MyRecover',
                          style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text('Lost & Found', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold, color: context.brandText),
                        ),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: subtitle.isEmpty
                              ? const SizedBox(width: double.infinity)
                              : Text(
                                  subtitle,
                                  key: ValueKey(subtitle),
                                  style: const TextStyle(color: Colors.grey),
                                ),
                        ),
                        const SizedBox(height: 20),
                        child,
                      ],
                    ),
                  ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner(this.message, {super.key});
  final String message;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF3B1414) : const Color(0xFFFEF2F2),
        border: Border.all(color: dark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(message, style: TextStyle(color: dark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C))),
    );
  }
}
