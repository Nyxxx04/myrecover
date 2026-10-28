import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';

import 'firebase_options.dart';
import 'services/match_watcher.dart';
import 'services/notifier.dart';

const _taskName = 'myrecover-match-check';

/// Runs in a background isolate when Android wakes the app (about every
/// 15 minutes at best; the OS may delay it to save battery).
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      await FirebaseAuth.instance.authStateChanges().first; // restore the saved sign-in
      await Notifier.init();
      await MatchWatcher.run();
    } catch (_) {
      // Never crash the background job; it simply runs again later.
    }
    return true;
  });
}

Future<void> initBackgroundChecks() => Workmanager().initialize(backgroundDispatcher);

Future<void> scheduleBackgroundChecks() => Workmanager().registerPeriodicTask(
  _taskName,
  _taskName,
  frequency: const Duration(minutes: 15),
  constraints: Constraints(networkType: NetworkType.connected),
  existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
);
