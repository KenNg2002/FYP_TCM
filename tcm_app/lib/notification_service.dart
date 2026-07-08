import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'ipaddress.dart';

// Centralizes push notification handling:
// 1. init()           — called once on app start; sets up local notifications + foreground push display
// 2. registerToken()  — called after login / entering the home screen; stores this device's FCM token in Firestore
// 3. send(...)        — called by business code at key events (order placed, rider assigned, refund approved...) to trigger a backend push
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'General Notifications',
    description: 'Order updates, delivery status, and admin alerts.',
    importance: Importance.high,
  );

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await _localNotifications.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );

    await FirebaseMessaging.instance.requestPermission();

    // FCM doesn't auto-show a system notification for foreground messages, so show one manually via local notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      if (notification == null) return;
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    });
  }

  // Call after login: stores this device's FCM token on the User doc so the backend can target it for push
  Future<void> registerToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('User').doc(uid).update({'fcmToken': token});
      }

      // Tokens rotate periodically — listen for refreshes so the stored token stays current
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance.collection('User').doc(uid).update({'fcmToken': newToken});
      });
    } catch (e) {
      // A failed token save shouldn't block login — worst case this device just won't get push notifications
      // ignore: avoid_print
      print('Failed to register FCM token: $e');
    }
  }

  // Trigger a push: target specific uids, or broadcast by role (e.g. role: 'Admin' notifies all admins)
  Future<void> send({List<String>? uids, String? role, required String title, required String body, Map<String, dynamic>? data}) async {
    try {
      await http.post(
        Uri.parse('$serverBaseUrl/send-notification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          if (uids != null) 'uids': uids,
          if (role != null) 'role': role,
          'title': title,
          'body': body,
          if (data != null) 'data': data,
        }),
      );
    } catch (e) {
      // A failed push shouldn't block the business flow (e.g. the order already succeeded) — just log it
      // ignore: avoid_print
      print('Failed to send notification: $e');
    }
  }
}
