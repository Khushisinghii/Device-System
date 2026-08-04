import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import '../../core/services/api_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class FcmService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    // Request notification permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    debugPrint("Permission: ${settings.authorizationStatus}");

    // Initialize Local Notifications for Foreground
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
    );
    await _localNotifications.initialize(settings: initSettings);

    // Get FCM Token
    String? token = await _messaging.getToken();

    debugPrint("FCM TOKEN:");
    debugPrint(token);

    // Foreground Notification
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Foreground Notification Received");

      if (message.notification != null) {
        _showLocalNotification(message.notification!);
      }
    });

    // Notification Click
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("Notification Clicked");
    });
  }

  static Future<void> _showLocalNotification(
    RemoteNotification notification,
  ) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'high_importance_channel', // id
          'High Importance Notifications', // title
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: platformDetails,
    );
  }

  static Future<void> updateTokenOnServer(int userId) async {
    try {
      String? token = await _messaging.getToken();
      if (token == null || userId == 0) return;

      final response = await ApiService.post(
        Uri.parse(
          "https://huntington-ware-seasons-first.trycloudflare.com/update_fcm_token",
        ),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"user_id": userId, "fcm_token": token}),
      );

      debugPrint("FCM token updated on server: ${response.statusCode}");
    } catch (e) {
      debugPrint("Error updating FCM token on server: $e");
    }
  }
}
