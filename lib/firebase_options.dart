// Generated from android/app/google-services.json (Firebase project myrecover-57a3d).
// Re-run `flutterfire configure` to regenerate, e.g. when adding iOS.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (defaultTargetPlatform == TargetPlatform.android) return android;
    throw UnsupportedError(
      'Firebase is only configured for Android. Run `flutterfire configure` to add other platforms.',
    );
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCVC6bPcyeamvaANA8LGwFfVhZ1SI2wMDo',
    appId: '1:765851912354:android:eef6bbf60869a818ae2ffb',
    messagingSenderId: '765851912354',
    projectId: 'myrecover-57a3d',
    storageBucket: 'myrecover-57a3d.firebasestorage.app',
  );
}
