import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
        InitializationSettings(android: android);

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse details) async {},
    );
  }

  static Future<void> scheduleDailyReminder(int hour, int minute) async {
    try {
      await _plugin.cancelAll();
      await _plugin.periodicallyShow(
        0,
        'Time to read 📖',
        'Your daily reading goal is waiting for you.',
        RepeatInterval.daily,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'reading_reminder',
            'Reading Reminders',
            channelDescription: 'Daily reading reminder notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Notification schedule error: $e');
    }
  }

  static Future<void> cancelDailyReminder() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Notification cancel error: $e');
    }
  }

  static Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    } catch (e) {
      debugPrint('Notification permission error: $e');
      return false;
    }
  }
}
