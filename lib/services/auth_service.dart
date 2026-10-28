import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_config.dart';
import '../models/app_user.dart';

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Students sign in with their UiTM student Google account
/// (`<studentId>@student.uitm.edu.my`); the student ID comes from that
/// account, so it is always the official one. Admins sign in with a username
/// and password, mapped to their email through `usernames/{lowercase username}`.
class AuthService {
  AuthService._();
  static final instance = AuthService._();

  static const studentDomain = 'student.uitm.edu.my';
  static bool isStudentEmail(String? email) => email != null && email.toLowerCase().endsWith('@$studentDomain');

  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;
  bool _googleReady = false;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Stream<AppUser?> profile(String uid) =>
      _db.collection('users').doc(uid).snapshots().map((doc) => doc.exists ? AppUser.fromDoc(doc) : null);

  /// Opens the Firestore connection early (e.g. while the login screen is
  /// shown) so the first real request doesn't pay the connection setup cost.
  void warmUp() {
    _db.collection('usernames').doc('~warmup').get().ignore();
  }

  /// Student sign-in. Only UiTM student Google accounts are accepted; the
  /// profile is created on first sign-in with the student ID from the email.
  /// Returns false if the student closed the account picker.
  Future<bool> signInWithGoogle() async {
    final google = GoogleSignIn.instance;
    if (!_googleReady) {
      if (googleWebClientId.isEmpty) {
        throw AuthFailure('Google sign-in is not set up yet (googleWebClientId in app_config.dart).');
      }
      await google.initialize(serverClientId: googleWebClientId, hostedDomain: studentDomain);
      _googleReady = true;
    }

    final GoogleSignInAccount account;
    try {
      account = await google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw AuthFailure('Google sign-in failed: ${e.description ?? e.code.name}');
    }

    final email = account.email.toLowerCase();
    if (!isStudentEmail(email)) {
      await google.signOut();
      throw AuthFailure('Please use your UiTM student Google account (…@$studentDomain).');
    }

    final cred = await _auth.signInWithCredential(
      GoogleAuthProvider.credential(idToken: account.authentication.idToken),
    );
    final user = cred.user!;
    final profile = _db.collection('users').doc(user.uid);
    if (!(await profile.get()).exists) {
      final studentId = email.split('@').first;
      await profile.set({
        'name': account.displayName ?? studentId,
        'username': studentId,
        'email': email,
        'role': 'user',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return true;
  }

  /// Admin sign-in with username (or email) and password.
  Future<void> adminLogin(String login, String password) async {
    const failed = 'Username or password is incorrect.';
    final input = login.trim().toLowerCase();
    final email = input.contains('@') ? input : await _emailForUsername(input);
    if (email == null) throw AuthFailure(failed);

    final User user;
    try {
      user = (await _auth.signInWithEmailAndPassword(email: email, password: password)).user!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(e.code == 'too-many-requests' ? 'Too many login attempts. Please try again later.' : failed);
    }
    if ((await _db.collection('users').doc(user.uid).get()).data()?['role'] != 'admin') {
      await _auth.signOut();
      throw AuthFailure('This login is for admins. Students: use "Sign in with Google".');
    }
  }

  Future<String?> _emailForUsername(String username) async {
    // The username→email cache only speeds login up; never let it block login.
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}
    final cacheKey = 'login_email_$username';
    final cached = prefs?.getString(cacheKey);
    if (cached != null) return cached;
    final email = (await _db.collection('usernames').doc(username).get()).data()?['email'] as String?;
    if (email != null) await prefs?.setString(cacheKey, email);
    return email;
  }

  Future<void> logout() async {
    // Also forget the Google account so a different student can sign in next.
    if (_googleReady) await GoogleSignIn.instance.signOut().catchError((_) {});
    await _auth.signOut();
  }
}
