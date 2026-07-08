import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_service.dart';

// Import your screen routes
import 'login_screen.dart';

// Must be a top-level/static function: when the app is killed and only background
// services are running, FCM invokes this in a separate isolate. No action needed here —
// the system already displays the notification payload automatically in that case; this
// handler just tells FCM the background message was handled, to avoid errors.
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

  // 3. Push notifications: register the background message handler and init foreground local notifications
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