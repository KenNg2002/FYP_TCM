import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'ipaddress.dart';

// 统一管理推送通知：
// 1. init()          — App 启动时调用一次，设置本地通知 + 前台推送展示
// 2. registerToken()  — 登录成功 / 进入首页后调用，把这台设备的 FCM token 存进 Firestore
// 3. send(...)        — 业务代码在关键节点（下单、指派骑手、批准退款...）调用，触发后端群发推送
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

    // App 在前台收到推送时，FCM 不会自动弹系统通知，要自己用本地通知显示出来
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

  // 登录成功后调用：把当前设备的 FCM token 存到 User 表，后端发推送时靠这个找到设备
  Future<void> registerToken() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('User').doc(uid).update({'fcmToken': token});
      }

      // token 会不定期轮换，监听一下确保存的一直是最新的
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance.collection('User').doc(uid).update({'fcmToken': newToken});
      });
    } catch (e) {
      // 存 token 失败不该阻断登录流程，顶多这台设备收不到推送
      // ignore: avoid_print
      print('Failed to register FCM token: $e');
    }
  }

  // 触发一次推送：uids 指定收件人，或用 role 群发（例如 role: 'Admin' 通知所有管理员）
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
      // 推送发送失败不该阻断正常业务流程（比如下单已经成功了），只记录日志
      // ignore: avoid_print
      print('Failed to send notification: $e');
    }
  }
}
