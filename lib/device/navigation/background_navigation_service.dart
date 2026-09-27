import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundNavigationService {
  BackgroundNavigationService._internal();
  static final BackgroundNavigationService instance = BackgroundNavigationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;
  static const int _notificationId = 1001;
  static const String _channelId = 'navguardian_live_nav';
  static const String _channelName = 'Live Navigation Guidance';

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);

      await _notifications.initialize(settings: initSettings);

      // Create Android Notification Channel
      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidPlugin != null) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Live turn-by-turn guidance and navigation alerts',
            importance: Importance.high,
            playSound: false,
            enableVibration: false,
            showBadge: false,
          ),
        );
        await androidPlugin.requestNotificationsPermission();
      }

      _isInitialized = true;
    } catch (e) {
      debugPrint('BackgroundNavigationService: Init error: $e');
    }
  }

  Future<void> showOrUpdateNavigationNotification({
    required String maneuverText,
    required String destinationName,
    required String remainingDistance,
    required String eta,
    required int speedKmh,
    bool isGpsLost = false,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      final statusTag = isGpsLost ? '⚡ [AI Dead Reckoning]' : '🟢 [Live GPS]';
      final title = '$maneuverText · $remainingDistance';
      final body = '$destinationName · ETA $eta · $speedKmh km/h $statusTag';

      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Live turn-by-turn guidance and navigation alerts',
        importance: Importance.high,
        priority: Priority.high,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: false,
        subText: 'NavGuardian AI Navigation',
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: '$speedKmh km/h · ETA $eta',
        ),
      );

      final details = NotificationDetails(android: androidDetails);
      await _notifications.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: details,
      );
    } catch (e) {
      debugPrint('BackgroundNavigationService: Show notification error: $e');
    }
  }

  Future<void> cancel() async {
    try {
      await _notifications.cancel(id: _notificationId);
    } catch (_) {}
  }
}
