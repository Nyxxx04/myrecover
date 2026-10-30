import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'inbox_service.dart';

/// Local notifications for AI matches and claim results.
class Notifier {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'matches',
      'Matches & claims',
      channelDescription: 'Possible matches for your reports and ownership claims',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _ready = true;
  }

  /// Asks for permission on Android 13+ (no-op elsewhere).
  static Future<void> requestPermission() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> show(String key, String title, String body) async {
    await init();
    await _plugin.show(id: key.hashCode & 0x7fffffff, title: title, body: body, notificationDetails: _details);
    await InboxService.instance.add(key, title, body);
  }
}
