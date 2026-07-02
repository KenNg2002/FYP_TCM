import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; 
import 'firebase_options.dart'; 
import 'package:flutter_stripe/flutter_stripe.dart';

// Import your screen routes
import 'login_screen.dart';

void main() async {
  // 1. Ensure Flutter bindings are ready before interacting with native cloud services
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. THIS IS YOUR DATABASE LINK: Initializes connection to Firebase & Firestore
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  Stripe.publishableKey = 'pk_test_51TmUWCC91fCS0pGOsYhwjyZN1cqNVKgT4OimnkuSASKpbGwjy5tt8z7ncgz3xKcQtMxHxL3ntYWKwf0XSwXiM5t900SWGABtdJ';

  // 3. Run the application
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Removes the red debug banner
      title: 'TCM App',
      theme: ThemeData(
        // Set the global seed color to your TCM App's primary green
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true, // Modern Material Design 3 UI standards
      ),
      // 4. The app entry point. 
      // LoginScreen will consult the database and route users to their respective dashboards.
      home: const LoginScreen(), 
    );
  }
}