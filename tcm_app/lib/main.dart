import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_service.dart';

// Import your screen routes
import 'login_screen.dart';

// 必须是顶层/静态函数：App 被杀掉、只有后台服务在跑的时候，FCM 会在独立的 isolate 里调用它。
// 这里不需要做任何事——系统在这种情况下会自己把 notification payload 显示成系统通知，
// 这个 handler 只是用来告诉 FCM「后台消息已处理」，避免报错。
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  // 1. Ensure Flutter bindings are ready before interacting with native cloud services
  WidgetsFlutterBinding.ensureInitialized();

  // 2. THIS IS YOUR DATABASE LINK: Initializes connection to Firebase & Firestore
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  Stripe.publishableKey = 'pk_test_51TmUWCC91fCS0pGOsYhwjyZN1cqNVKgT4OimnkuSASKpbGwjy5tt8z7ncgz3xKcQtMxHxL3ntYWKwf0XSwXiM5t900SWGABtdJ';

  // 3. 推送通知：注册后台消息 handler + 初始化前台本地通知展示
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService.instance.init();

  // 4. Run the application
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Removes the red debug banner
      title: 'SH Wellness',
      theme: ThemeData(
        // Set the global seed color to your SH Wellness primary green
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true, // Modern Material Design 3 UI standards
      ),
      // 4. The app entry point. 
      // LoginScreen will consult the database and route users to their respective dashboards.
      home: const LoginScreen(), 
    );
  }
}