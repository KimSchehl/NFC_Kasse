import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static const _channelId = 'help_requests';
  static const _channelName = 'Hilfe-Anfragen';
  static const _channelDesc = 'Alarme bei eingehenden Hilfe-Anfragen';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    // Create high-importance channel so heads-up + sound works even when app
    // is in the foreground on Android 8+.
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Request POST_NOTIFICATIONS permission (Android 13+).
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> showHelpAlert(int requestId, String requesterName) async {
    const details = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
    );
    await _plugin.show(
      requestId,
      'Hilfe benötigt!',
      '$requesterName braucht Hilfe',
      const NotificationDetails(android: details),
    );
  }

  Future<void> cancelAlert(int requestId) async {
    await _plugin.cancel(requestId);
  }
}
